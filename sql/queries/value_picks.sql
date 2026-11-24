-- Value picks:
--Returns 10 players from each position (goalkeeper, defender, midfielder, forward)
--who are the current best value for money based on their total
--points and current value.
--All players returned have played at least 300 minutes
--Defenders are the best value for money in general.  

WITH player_values AS (
    SELECT 
    pos.name AS Position,
    CONCAT(p.first_name, ' ', p.second_name) AS Name,
    t.name AS Team,
    ROUND(p.total_points / p.now_cost,1) AS points_per_m,
    total_points AS Points,
    now_cost AS price
    FROM players p 
    JOIN teams t ON p.team_id = t.team_id
    JOIN positions pos ON p.position_id = pos.position_id
    WHERE minutes >= 300
), ranked AS (
    SELECT
    pv.*,
    RANK() OVER (PARTITION BY Position ORDER BY points_per_m DESC) AS value_ranked
    FROM player_values pv
    
)
SELECT *
FROM ranked
WHERE value_ranked <= 10
ORDER BY Position , points_per_m DESC

