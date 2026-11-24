SELECT 
CONCAT(p.first_name,' ', p.second_name) AS Name, 
t.name AS Team,
pos.name AS Position,
p.points_per_game AS PPG,
p.form AS Form,
p.selected_by_percent AS 'Selected %'

FROM players p
LEFT JOIN teams t ON p.team_id = t.team_id
LEFT JOIN positions pos ON p.position_id = pos.position_id

WHERE 
CAST(p.selected_by_percent AS DOUBLE) < 5
AND p.minutes >= 450
AND status = 'a'

ORDER BY CAST(p.points_per_game AS DOUBLE) DESC

LIMIT 10;