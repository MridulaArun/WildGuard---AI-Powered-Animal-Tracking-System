SELECT ar.event_id, a.tag_id, rz.zone_name, ar.risk_level, ar.distance_m, s.species_name
FROM Animal_Risk_Event ar
JOIN Animal a
    ON ar.animal_id = a.animal_id
JOIN Risk_Zone rz
    ON ar.zone_id = rz.zone_id
JOIN Species s
	ON s.species_id = a.species_id;

-- 2. Pending Alert Assignments
SELECT aa.assignment_id, al.alert_id, r.name, aa.response_status,
       ar.event_id, a.animal_id, s.species_name
FROM Alert_Assignment aa
JOIN Alert al ON aa.alert_id = al.alert_id
JOIN Ranger r
    ON aa.ranger_id = r.ranger_id
JOIN Animal_Risk_Event ar
    ON ar.event_id = al.event_id
JOIN Animal a
    ON a.animal_id = ar.animal_id
JOIN Species s
    ON a.species_id = s.species_id
WHERE aa.response_status = 'pending';

-- 3. Comprehensive Animal Monitoring
SELECT
    a.tag_id,
    s.species_name,
    s.conservation_status,
    r.reserve_name,
    g.timestamp AS last_location_time,
    d.battery_level,
    h.health_status
FROM Animal a
JOIN Species s ON a.species_id = s.species_id
JOIN Reserve r ON a.home_reserve_id = r.reserve_id
LEFT JOIN GPS_Tracking g ON a.animal_id = g.animal_id
LEFT JOIN Device d ON a.animal_id = d.animal_id
LEFT JOIN Health_Record h ON a.animal_id = h.animal_id
WHERE a.status = 'active'
ORDER BY d.battery_level ASC;

-- 4. High-Risk Animal Predictions
SELECT
    a.tag_id,
    s.species_name,
    r.reserve_name,
    g.timestamp AS last_signal,
    d.battery_level,
    p.predicted_risk,
    p.risk_probability,
    p.review_status
FROM Animal a
JOIN Species s ON a.species_id = s.species_id
JOIN Reserve r ON a.home_reserve_id = r.reserve_id
LEFT JOIN GPS_Tracking g ON a.animal_id = g.animal_id
LEFT JOIN Device d ON a.animal_id = d.animal_id
JOIN Prediction p ON a.animal_id = p.animal_id
WHERE p.predicted_risk IN ('high', 'critical')
ORDER BY p.risk_probability DESC;

-- 5. Ranger Workload Analysis
SELECT r.name AS ranger_name, rv.reserve_name,
       COUNT(aa.assignment_id) AS total_assignments,
       COUNT(*) FILTER (WHERE aa.response_status = 'pending') AS pending_assignments,
       COUNT(*) FILTER (WHERE aa.response_status = 'in_progress') AS active_assignments
FROM Ranger r
JOIN Reserve rv ON r.reserve_id = rv.reserve_id
LEFT JOIN Alert_Assignment aa ON r.ranger_id = aa.ranger_id
LEFT JOIN Alert al ON aa.alert_id = al.alert_id
GROUP BY r.ranger_id, r.name, rv.reserve_name
HAVING COUNT(aa.assignment_id) > 0
ORDER BY total_assignments DESC;

-- 6. Animals With Low Battery / Health Issues
SELECT
    a.tag_id,
    s.species_name,
    r.reserve_name,
    d.battery_level,
    d.status AS device_status,
    h.health_status,
    h.checkup_date
FROM Animal a
JOIN Species s ON a.species_id = s.species_id
JOIN Reserve r ON a.home_reserve_id = r.reserve_id
JOIN Device d ON a.animal_id = d.animal_id
JOIN Health_Record h ON a.animal_id = h.animal_id
WHERE d.battery_level < 30
   OR h.health_status IN ('critical', 'needs_review')
ORDER BY d.battery_level ASC;

-- 7. Reserve-Wise Wildlife Risk Analysis
SELECT
    r.reserve_name,
    COUNT(DISTINCT a.animal_id) AS total_animals,
    COUNT(DISTINCT rz.zone_id) AS risk_zones,
    COUNT(DISTINCT e.event_id) AS risk_events,
    COUNT(DISTINCT p.prediction_id) AS predictions
FROM Reserve r
LEFT JOIN Animal a ON r.reserve_id = a.home_reserve_id
LEFT JOIN Risk_Zone rz ON r.reserve_id = rz.reserve_id
LEFT JOIN Animal_Risk_Event e ON a.animal_id = e.animal_id
LEFT JOIN Prediction p ON a.animal_id = p.animal_id
GROUP BY r.reserve_id, r.reserve_name
ORDER BY risk_events DESC;
