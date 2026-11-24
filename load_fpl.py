"""
Load the current Fantasy Premier League season into a DuckDB database.

    python load_fpl.py              # fetch from the FPL API, build fpl.duckdb
    python load_fpl.py --cached     # rebuild from the JSON saved by the last fetch

The script only extracts and loads. Every table, key and constraint lives in
sql/schema.sql, and all analysis is done in SQL afterwards.
"""

from __future__ import annotations

import argparse
import json
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import duckdb
import requests

API = "https://fantasy.premierleague.com/api"
ROOT = Path(__file__).parent
RAW_DIR = ROOT / "data" / "raw"
DB_PATH = ROOT / "fpl.duckdb"
SCHEMA = ROOT / "sql" / "schema.sql"

session = requests.Session()
session.headers["User-Agent"] = "fpl-analytics-loader/1.0"


# --------------------------------------------------------------------- extract
def fetch(path: str, retries: int = 3) -> dict | list:
    for attempt in range(1, retries + 1):
        try:
            r = session.get(f"{API}/{path}", timeout=30)
            r.raise_for_status()
            return r.json()
        except requests.RequestException:
            if attempt == retries:
                raise
            time.sleep(2 * attempt)


def extract(use_cache: bool) -> tuple[dict, list, dict[int, list]]:
    """Return (bootstrap, fixtures, {player_id: history rows})."""
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    cache = RAW_DIR / "fpl_raw.json"

    if use_cache:
        raw = json.loads(cache.read_text())
        return raw["bootstrap"], raw["fixtures"], {int(k): v for k, v in raw["histories"].items()}

    print("Fetching bootstrap-static ...")
    bootstrap = fetch("bootstrap-static/")
    print("Fetching fixtures ...")
    fixtures = fetch("fixtures/")

    player_ids = [p["id"] for p in bootstrap["elements"]]
    print(f"Fetching gameweek history for {len(player_ids)} players ...")
    # A small thread pool keeps this to ~1 minute without hammering the API.
    with ThreadPoolExecutor(max_workers=8) as pool:
        summaries = pool.map(lambda pid: fetch(f"element-summary/{pid}/"), player_ids)
        histories = {pid: s["history"] for pid, s in zip(player_ids, summaries)}

    cache.write_text(json.dumps({"bootstrap": bootstrap, "fixtures": fixtures, "histories": histories}))
    return bootstrap, fixtures, histories


# ------------------------------------------------------------------- transform
def price(tenths: int | None) -> float | None:
    """The API stores £5.5m as 55."""
    return None if tenths is None else tenths / 10


def num(value) -> float | None:
    """Many numeric fields arrive as strings ('4.5'); blanks become NULL."""
    return None if value in (None, "") else float(value)


def transform(bootstrap: dict, fixtures: list, histories: dict[int, list]) -> dict[str, list[tuple]]:
    positions = [
        (p["id"], p["singular_name"], p["singular_name_short"],
         p["squad_select"], p["squad_min_play"], p["squad_max_play"])
        for p in bootstrap["element_types"]
    ]

    teams = [
        (t["id"], t["name"], t["short_name"],
         t["strength_overall_home"], t["strength_overall_away"],
         t["strength_attack_home"], t["strength_attack_away"],
         t["strength_defence_home"], t["strength_defence_away"])
        for t in bootstrap["teams"]
    ]

    gameweeks = [
        (e["id"], e["name"], e["deadline_time"], e["finished"], e["is_current"], e["is_next"],
         e["average_entry_score"] if e["finished"] else None, e["highest_score"],
         e["most_captained"], e["most_selected"])
        for e in bootstrap["events"]
    ]

    players = [
        (p["id"], p["first_name"], p["second_name"], p["web_name"], p["team"], p["element_type"],
         p["status"], p["news"] or None, price(p["now_cost"]), price(p["cost_change_start"]),
         num(p["selected_by_percent"]), p["total_points"], p["minutes"], p["goals_scored"],
         p["assists"], p["clean_sheets"], num(p["form"]), num(p["points_per_game"]),
         num(p["expected_goals"]), num(p["expected_assists"]),
         p["transfers_in_event"], p["transfers_out_event"])
        for p in bootstrap["elements"]
    ]

    fixture_rows = [
        (f["id"], f["event"], f["kickoff_time"], f["team_h"], f["team_a"],
         f["team_h_score"], f["team_a_score"], f["team_h_difficulty"], f["team_a_difficulty"],
         f["started"], f["finished"])
        for f in fixtures
    ]

    player_gameweeks = [
        (h["element"], h["fixture"], h["round"], h["opponent_team"], h["was_home"],
         h["total_points"], h["minutes"], h["starts"], h["goals_scored"], h["assists"],
         h["clean_sheets"], h["goals_conceded"], h["own_goals"], h["penalties_saved"],
         h["penalties_missed"], h["yellow_cards"], h["red_cards"], h["saves"], h["bonus"], h["bps"],
         h.get("defensive_contribution"),
         num(h["influence"]), num(h["creativity"]), num(h["threat"]), num(h["ict_index"]),
         num(h["expected_goals"]), num(h["expected_assists"]),
         num(h["expected_goal_involvements"]), num(h["expected_goals_conceded"]),
         price(h["value"]), h["selected"], h["transfers_in"], h["transfers_out"])
        for rows in histories.values()
        for h in rows
    ]

    # Parents before children, so foreign keys are satisfied on insert.
    return {
        "positions": positions,
        "teams": teams,
        "gameweeks": gameweeks,
        "players": players,
        "fixtures": fixture_rows,
        "player_gameweeks": player_gameweeks,
    }


# ------------------------------------------------------------------------ load
def load(tables: dict[str, list[tuple]]) -> None:
    con = duckdb.connect(str(DB_PATH))

    # Rebuild and reload in one transaction: if anything fails, the previous
    # data is restored rather than leaving dropped or half-filled tables.
    con.execute("BEGIN TRANSACTION")
    try:
        con.execute(SCHEMA.read_text())
        for table, rows in tables.items():
            if not rows:
                continue
            placeholders = ", ".join("?" * len(rows[0]))
            con.executemany(f"INSERT INTO {table} VALUES ({placeholders})", rows)
        con.execute("COMMIT")
    except Exception:
        con.execute("ROLLBACK")
        con.close()
        raise

    print(f"\nLoaded into {DB_PATH.name}:")
    for table in tables:
        n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table:<18} {n:>6,} rows")
    con.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cached", action="store_true", help="rebuild from data/raw/fpl_raw.json instead of calling the API")
    args = parser.parse_args()

    load(transform(*extract(use_cache=args.cached)))


if __name__ == "__main__":
    main()
