--Returns a rolling average of player points over the previous 5 gameweeks
CREATE OR REPLACE VIEW player_form AS

WITH player_gw AS (
    SELECT 
    pg.player_id AS player_id,
    CONCAT(p.first_name, ' ', p.second_name) AS Name,
    pg.gameweek_id AS gw_id,
    SUM(pg.total_points) AS gw_points

    FROM player_gameweeks pg
    JOIN players p ON pg.player_id = p.player_id

    GROUP BY pg.player_id, p.first_name, p.second_name, pg.gameweek_id

), windowed AS (
    SELECT gwp.*,
    AVG(gwp.gw_points)
    OVER (PARTITION BY gwp.player_id 
    ORDER BY gwp.gw_id
    ROWS BETWEEN 4 PRECEDING AND CURRENT ROW)
    AS rolling_avg
    
    FROM player_gw gwp
)
SELECT *
FROM windowed

;