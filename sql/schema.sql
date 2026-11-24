-- =====================================================================
-- FPL Analytics Database — schema
-- Engine: DuckDB
--
-- Tables (in dependency order):
--   positions        lookup: GKP / DEF / MID / FWD
--   teams            the 20 Premier League clubs
--   gameweeks        the 38 FPL "events" (deadlines, averages)
--   players          one row per FPL player ("element")
--   fixtures         one row per Premier League match
--   player_gameweeks one row per player per fixture played (the fact table)
--
-- Conventions:
--   * Prices are stored in £m as DECIMAL(4,1) (the API sends 55 for £5.5m).
--   * Every table carries the FPL API id as its primary key, so data can be
--     reloaded idempotently and joined back to the API if needed.
-- =====================================================================

DROP TABLE IF EXISTS player_gameweeks;
DROP TABLE IF EXISTS fixtures;
DROP TABLE IF EXISTS players;
DROP TABLE IF EXISTS gameweeks;
DROP TABLE IF EXISTS teams;
DROP TABLE IF EXISTS positions;

-- ---------------------------------------------------------------------
CREATE TABLE positions (
    position_id      INTEGER     PRIMARY KEY,
    name             VARCHAR     NOT NULL UNIQUE,     -- 'Goalkeeper'
    short_name       VARCHAR(3)  NOT NULL UNIQUE,     -- 'GKP'
    squad_select     INTEGER     NOT NULL,            -- how many you must pick in a 15-man squad
    squad_min_play   INTEGER     NOT NULL,
    squad_max_play   INTEGER     NOT NULL
);

-- ---------------------------------------------------------------------
CREATE TABLE teams (
    team_id                 INTEGER     PRIMARY KEY,
    name                    VARCHAR     NOT NULL UNIQUE,
    short_name              VARCHAR(3)  NOT NULL UNIQUE,
    strength_overall_home   INTEGER,
    strength_overall_away   INTEGER,
    strength_attack_home    INTEGER,
    strength_attack_away    INTEGER,
    strength_defence_home   INTEGER,
    strength_defence_away   INTEGER
);

-- ---------------------------------------------------------------------
CREATE TABLE gameweeks (
    gameweek_id          INTEGER     PRIMARY KEY CHECK (gameweek_id BETWEEN 1 AND 38),
    name                 VARCHAR     NOT NULL,         -- 'Gameweek 1'
    deadline_time        TIMESTAMPTZ NOT NULL,
    is_finished          BOOLEAN     NOT NULL,
    is_current           BOOLEAN     NOT NULL,
    is_next              BOOLEAN     NOT NULL,
    average_score        INTEGER,                      -- NULL until the GW is played
    highest_score        INTEGER,
    most_captained       INTEGER,                      -- player_id (no FK: players loads after)
    most_selected        INTEGER
);

-- ---------------------------------------------------------------------
CREATE TABLE players (
    player_id                INTEGER       PRIMARY KEY,
    first_name               VARCHAR       NOT NULL,
    second_name              VARCHAR       NOT NULL,
    web_name                 VARCHAR       NOT NULL,   -- the name shown in the FPL app
    team_id                  INTEGER       NOT NULL REFERENCES teams (team_id),
    position_id              INTEGER       NOT NULL REFERENCES positions (position_id),
    status                   VARCHAR(1)    NOT NULL,   -- a=available d=doubtful i=injured s=suspended u=unavailable n=not in squad
    news                     VARCHAR,
    now_cost                 DECIMAL(4,1)  NOT NULL CHECK (now_cost > 0),   -- £m
    cost_change_start        DECIMAL(3,1)  NOT NULL,                        -- £m since GW1
    selected_by_percent      DECIMAL(5,2)  NOT NULL CHECK (selected_by_percent BETWEEN 0 AND 100),
    total_points             INTEGER       NOT NULL,
    minutes                  INTEGER       NOT NULL,
    goals_scored             INTEGER       NOT NULL,
    assists                  INTEGER       NOT NULL,
    clean_sheets             INTEGER       NOT NULL,
    form                     DECIMAL(4,1),
    points_per_game          DECIMAL(4,1),
    expected_goals           DECIMAL(6,2),
    expected_assists         DECIMAL(6,2),
    transfers_in_event       INTEGER,
    transfers_out_event      INTEGER
);

-- ---------------------------------------------------------------------
CREATE TABLE fixtures (
    fixture_id          INTEGER     PRIMARY KEY,
    gameweek_id         INTEGER     REFERENCES gameweeks (gameweek_id),  -- NULL = postponed / unscheduled
    kickoff_time        TIMESTAMPTZ,
    home_team_id        INTEGER     NOT NULL REFERENCES teams (team_id),
    away_team_id        INTEGER     NOT NULL REFERENCES teams (team_id),
    home_score          INTEGER,                                          -- NULL until played
    away_score          INTEGER,
    home_difficulty     INTEGER     NOT NULL CHECK (home_difficulty BETWEEN 1 AND 5),  -- FDR for the home side
    away_difficulty     INTEGER     NOT NULL CHECK (away_difficulty BETWEEN 1 AND 5),
    is_started          BOOLEAN,                                          -- NULL = postponed / unscheduled
    is_finished         BOOLEAN     NOT NULL,
    CHECK (home_team_id <> away_team_id)
);

-- ---------------------------------------------------------------------
-- Grain: one row per player per fixture. A player can have two rows in the
-- same gameweek (double gameweek), so the key is (player, fixture), not
-- (player, gameweek).
CREATE TABLE player_gameweeks (
    player_id                    INTEGER       NOT NULL REFERENCES players (player_id),
    fixture_id                   INTEGER       NOT NULL REFERENCES fixtures (fixture_id),
    gameweek_id                  INTEGER       NOT NULL REFERENCES gameweeks (gameweek_id),
    opponent_team_id             INTEGER       NOT NULL REFERENCES teams (team_id),
    was_home                     BOOLEAN       NOT NULL,
    total_points                 INTEGER       NOT NULL,
    minutes                      INTEGER       NOT NULL CHECK (minutes BETWEEN 0 AND 130),
    starts                       INTEGER       NOT NULL,
    goals_scored                 INTEGER       NOT NULL,
    assists                      INTEGER       NOT NULL,
    clean_sheets                 INTEGER       NOT NULL,
    goals_conceded               INTEGER       NOT NULL,
    own_goals                    INTEGER       NOT NULL,
    penalties_saved              INTEGER       NOT NULL,
    penalties_missed             INTEGER       NOT NULL,
    yellow_cards                 INTEGER       NOT NULL,
    red_cards                    INTEGER       NOT NULL,
    saves                        INTEGER       NOT NULL,
    bonus                        INTEGER       NOT NULL,
    bps                          INTEGER       NOT NULL,
    defensive_contribution       INTEGER,
    influence                    DECIMAL(6,1),
    creativity                   DECIMAL(6,1),
    threat                       DECIMAL(6,1),
    ict_index                    DECIMAL(6,1),
    expected_goals               DECIMAL(5,2),
    expected_assists             DECIMAL(5,2),
    expected_goal_involvements   DECIMAL(5,2),
    expected_goals_conceded      DECIMAL(5,2),
    price                        DECIMAL(4,1)  NOT NULL,   -- £m at the time of the match
    selected                     INTEGER       NOT NULL,   -- number of managers owning him that GW
    transfers_in                 INTEGER       NOT NULL,
    transfers_out                INTEGER       NOT NULL,
    PRIMARY KEY (player_id, fixture_id)
);

-- Indexes for the joins/filters the analysis queries will lean on.
CREATE INDEX idx_players_team        ON players (team_id);
CREATE INDEX idx_players_position    ON players (position_id);
CREATE INDEX idx_fixtures_gameweek   ON fixtures (gameweek_id);
CREATE INDEX idx_pgw_gameweek        ON player_gameweeks (gameweek_id);
