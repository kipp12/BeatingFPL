--gets all gameweeks for each team in a single table
WITH team_fixtures AS (
    SELECT home_team_id AS team_id, home_difficulty AS difficulty, gameweek_id, kickoff_time
    FROM fixtures
    WHERE kickoff_time > now() --filters out played games 
    UNION ALL
    SELECT away_team_id, away_difficulty, gameweek_id, kickoff_time
    FROM fixtures
    WHERE kickoff_time > now()

-- gets the average difficulty of a teams upcoming 5 games
), next_5 AS(
    SELECT team_fixtures.*,
    AVG(team_fixtures.difficulty)
    OVER (PARTITION BY team_fixtures.team_id
    ORDER BY kickoff_time ASC
    ROWS BETWEEN CURRENT ROW AND 4 FOLLOWING)
    AS upcoming_avg_difficulty,

    --returnst the order of the difficulty averages so can discard all that arent 1
    ROW_NUMBER()
    OVER (PARTITION BY team_fixtures.team_id
    ORDER BY kickoff_time ASC)
    AS row_no

    FROM team_fixtures

), team_value AS (
    --finds best point per million of players, ranks them per team,
    --so that final select can also return player recs for the teams
    --with the easiest upcoming matches
    SELECT 
    CONCAT(p.first_name, ' ', p.second_name) AS Name,
    p.team_id,
    p.total_points / p.now_cost AS points_per_m
    FROM players p 
    WHERE p.minutes >= 300
), value_ranked AS(
    SELECT tv.*,
    RANK() OVER (PARTITION BY team_id ORDER BY points_per_m DESC)
    AS player_val_ranked
    
    FROM team_value tv
    
)
--finally returns each team, ranked from easiest upcoming fixtures to hardest, 
--with a player recommendation for each
SELECT t.name, n.upcoming_avg_difficulty, vr.Name
FROM next_5 n
INNER JOIN teams t ON n.team_id = t.team_id
JOIN value_ranked vr ON n.team_id = vr.team_id
WHERE n.row_no = 1
AND vr.player_val_ranked = 1
ORDER BY n.upcoming_avg_difficulty ASC
;