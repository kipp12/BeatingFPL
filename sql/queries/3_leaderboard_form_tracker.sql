--Leadersboard version, shows the 10 most in form players right now
SELECT * 
FROM player_form
WHERE gw_id = 10
ORDER BY rolling_avg DESC
LIMIT 10
;