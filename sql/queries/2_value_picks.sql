SELECT *
FROM value_picks
WHERE value_ranked <= 10
ORDER BY Position , points_per_m DESC
LIMIT 10

;