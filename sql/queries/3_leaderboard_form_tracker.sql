--Leadersboard version, shows the 10 most in form players right now
SELECT Name, rolling_avg
FROM player_form
WHERE gw_id = (SELECT MAX(gw_id) FROM player_form)
ORDER BY rolling_avg DESC
LIMIT 10
;