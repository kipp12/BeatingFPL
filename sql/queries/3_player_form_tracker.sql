--Shows individual player form swing over the season
SELECT Name, gw_id AS Gameweek, gw_points, rolling_avg
FROM player_form
WHERE Name = 'Florian Wirtz'
ORDER BY gw_id
;