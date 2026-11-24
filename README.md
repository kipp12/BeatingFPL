# FPL Analytics Database

A DuckDB database of the current Fantasy Premier League season, built from the official FPL API. Python only loads the data; every question is answered in SQL.

## Schema

```
positions ─┐
           ├──< players ──┐
teams ─────┤              ├──< player_gameweeks
           ├──< fixtures ─┤
gameweeks ─┴──────────────┘
```

| Table | Grain | Key |
|---|---|---|
| `positions` | one per position (GKP/DEF/MID/FWD) | `position_id` |
| `teams` | one per club | `team_id` |
| `gameweeks` | one per FPL gameweek (1–38) | `gameweek_id` |
| `players` | one per player, current price/ownership/season totals | `player_id` → `teams`, `positions` |
| `fixtures` | one per match, with home/away difficulty (FDR) | `fixture_id` → `gameweeks`, `teams` ×2 |
| `player_gameweeks` | one per player per fixture | (`player_id`, `fixture_id`) → `players`, `fixtures`, `gameweeks`, `teams` |

`player_gameweeks` is keyed on fixture rather than gameweek so double gameweeks are handled. Prices are stored in £m (`DECIMAL(4,1)`), and `CHECK` constraints guard things like FDR being 1–5 and a team never playing itself. The full DDL is in [`sql/schema.sql`](sql/schema.sql).

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python load_fpl.py          # ~15s, calls the API and builds fpl.duckdb
.venv/bin/python load_fpl.py --cached # rebuild from the saved JSON, no network
```

Each run drops and recreates the tables, so it is safe to rerun after every gameweek.

## Querying

With the [DuckDB CLI](https://duckdb.org/docs/installation/) installed (`brew install duckdb` on macOS):

```bash
duckdb fpl.duckdb < sql/queries/views/3_form_tracker_view.sql  # once, creates the player_form view
duckdb fpl.duckdb < sql/queries/1_differentials.sql
```

or open `fpl.duckdb` in DBeaver or the VS Code SQLTools extension.
