SELECT setval(pg_get_serial_sequence('species', 'species_id'), (SELECT MAX(species_id) FROM species));
SELECT setval(pg_get_serial_sequence('reserve', 'reserve_id'), (SELECT MAX(reserve_id) FROM reserve));
SELECT setval(pg_get_serial_sequence('animal', 'animal_id'), (SELECT MAX(animal_id) FROM animal));
SELECT setval(pg_get_serial_sequence('gps_tracking', 'tracking_id'), (SELECT MAX(tracking_id) FROM gps_tracking));
SELECT setval(pg_get_serial_sequence('risk_zone', 'zone_id'), (SELECT MAX(zone_id) FROM risk_zone));
SELECT setval(pg_get_serial_sequence('animal_risk_event', 'event_id'), (SELECT MAX(event_id) FROM animal_risk_event));
SELECT setval(pg_get_serial_sequence('prediction', 'prediction_id'), (SELECT MAX(prediction_id) FROM prediction));
SELECT setval(pg_get_serial_sequence('alert', 'alert_id'), (SELECT MAX(alert_id) FROM alert));
SELECT setval(pg_get_serial_sequence('ranger', 'ranger_id'), (SELECT MAX(ranger_id) FROM ranger));
SELECT setval(pg_get_serial_sequence('alert_assignment', 'assignment_id'), (SELECT MAX(assignment_id) FROM alert_assignment));
SELECT setval(pg_get_serial_sequence('device', 'device_id'), (SELECT MAX(device_id) FROM device));
SELECT setval(pg_get_serial_sequence('habitat_zone', 'habitat_id'), (SELECT MAX(habitat_id) FROM habitat_zone));
SELECT setval(pg_get_serial_sequence('health_record', 'record_id'), (SELECT MAX(record_id) FROM health_record));
 
COMMIT;
 
-- 1. BASIC SELECT
SELECT * FROM Species;
SELECT * FROM Animal;
SELECT * FROM Health_Record;
SELECT animal_id, tag_id, sex, birth_year, status FROM Animal;

-- 2. WHERE / FILTERING
SELECT * FROM Species WHERE conservation_status = 'Endangered';
SELECT * FROM Animal WHERE status = 'active';
SELECT * FROM Animal WHERE sex = 'F';
SELECT * FROM Prediction WHERE predicted_risk = 'critical';
SELECT * FROM Alert WHERE status = 'open';
SELECT * FROM Device WHERE battery_level < 30;

-- 3. ORDER BY
SELECT animal_id, tag_id, birth_year FROM Animal ORDER BY birth_year ASC;
SELECT device_id, model, battery_level FROM Device ORDER BY battery_level ASC;
SELECT prediction_id, animal_id, risk_probability FROM Prediction ORDER BY risk_probability DESC;
SELECT record_id, animal_id, checkup_date, weight_kg FROM Health_Record ORDER BY checkup_date DESC;

-- 4. JOINS
SELECT a.animal_id, a.tag_id, s.species_name, s.conservation_status FROM Animal a JOIN Species s ON a.species_id = s.species_id;
SELECT a.animal_id, a.tag_id, r.reserve_name, r.state FROM Animal a JOIN Reserve r ON a.home_reserve_id = r.reserve_id;
SELECT a.animal_id, a.tag_id, g.timestamp, g.speed FROM Animal a JOIN GPS_Tracking g ON a.animal_id = g.animal_id;
SELECT p.prediction_id, a.tag_id, p.predicted_risk, p.risk_probability FROM Prediction p JOIN Animal a ON p.animal_id = a.animal_id;
SELECT ar.event_id, a.tag_id, rz.zone_name, ar.risk_level, ar.distance_m FROM Animal_Risk_Event ar JOIN Animal a ON ar.animal_id = a.animal_id JOIN Risk_Zone rz ON ar.zone_id = rz.zone_id;
SELECT aa.assignment_id, al.alert_id, r.name, aa.response_status FROM Alert_Assignment aa JOIN Alert al ON aa.alert_id = al.alert_id JOIN Ranger r ON aa.ranger_id = r.ranger_id;

-- 5. AGGREGATE FUNCTIONS
SELECT COUNT(*) AS total_animals FROM Animal;
SELECT COUNT(*) AS total_species FROM Species;
SELECT AVG(battery_level) AS average_battery FROM Device;
SELECT MIN(battery_level) AS minimum_battery, MAX(battery_level) AS maximum_battery FROM Device;
SELECT AVG(weight_kg) AS average_animal_weight FROM Health_Record;
SELECT MAX(risk_probability) AS highest_risk_probability FROM Prediction;

-- 6. GROUP BY
SELECT status, COUNT(*) AS animal_count FROM Animal GROUP BY status;
SELECT conservation_status, COUNT(*) AS species_count FROM Species GROUP BY conservation_status;
SELECT predicted_risk, COUNT(*) AS prediction_count FROM Prediction GROUP BY predicted_risk;
SELECT risk_level, COUNT(*) AS event_count FROM Animal_Risk_Event GROUP BY risk_level;
SELECT severity, COUNT(*) AS alert_count FROM Alert GROUP BY severity;
SELECT health_status, COUNT(*) AS health_count FROM Health_Record GROUP BY health_status;

-- 7. HAVING
SELECT status, COUNT(*) AS animal_count FROM Animal GROUP BY status HAVING COUNT(*) > 2;
SELECT predicted_risk, COUNT(*) AS prediction_count FROM Prediction GROUP BY predicted_risk HAVING COUNT(*) > 2;
SELECT risk_level, COUNT(*) AS event_count FROM Animal_Risk_Event GROUP BY risk_level HAVING COUNT(*) > 2;
SELECT health_status, COUNT(*) AS health_count FROM Health_Record GROUP BY health_status HAVING COUNT(*) > 2;

-- 8. SUBQUERIES
SELECT animal_id, tag_id FROM Animal WHERE species_id IN (SELECT species_id FROM Species WHERE conservation_status = 'Endangered');
SELECT prediction_id, animal_id, risk_probability FROM Prediction WHERE risk_probability > (SELECT AVG(risk_probability) FROM Prediction);
SELECT animal_id, tag_id FROM Animal WHERE animal_id IN (SELECT animal_id FROM Device WHERE battery_level < 30);
SELECT animal_id, tag_id FROM Animal WHERE animal_id IN (SELECT animal_id FROM Health_Record WHERE health_status = 'critical');

-- 9. DATE / TIME
SELECT * FROM GPS_Tracking WHERE timestamp >= '2026-10-10';
SELECT * FROM Animal_Risk_Event WHERE detected_at >= '2026-10-10';
SELECT * FROM Prediction WHERE predicted_at >= '2026-10-10';
SELECT * FROM Health_Record WHERE checkup_date >= '2026-10-10';

-- 10. POSTGIS / SPATIAL
-- POSTGIS / SPATIAL QUERIES
SELECT tracking_id, animal_id, ST_AsText(location) AS location FROM GPS_Tracking;
SELECT zone_id, zone_name, ST_Area(boundary::geography) AS area_sq_m FROM Risk_Zone;
SELECT habitat_id, habitat_name, ST_Area(boundary::geography) AS area_sq_m FROM Habitat_Zone;
SELECT g.tracking_id, g.animal_id, rz.zone_name FROM GPS_Tracking g JOIN Risk_Zone rz ON ST_Within(g.location, rz.boundary);
SELECT g.tracking_id, g.animal_id, rz.zone_name, ST_Distance(g.location::geography, rz.boundary::geography) AS distance_m FROM GPS_Tracking g CROSS JOIN Risk_Zone rz WHERE ST_DWithin(g.location::geography, rz.boundary::geography, 1000);


CREATE TABLE IF NOT EXISTS Alert_Audit_Log (
    log_id      BIGSERIAL PRIMARY KEY,
    alert_id    BIGINT NOT NULL,
    old_status  VARCHAR(20),
    new_status  VARCHAR(20) NOT NULL,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_by  TEXT NOT NULL DEFAULT current_user
);
CREATE INDEX IF NOT EXISTS idx_audit_alert ON Alert_Audit_Log (alert_id, changed_at);

-- Seed data inserts explicit IDs, so SERIAL sequences are still at 1.
-- Without this, any trigger-generated row would fail with a duplicate-key error.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('species',           'species_id'),
            ('reserve',           'reserve_id'),
            ('animal',            'animal_id'),
            ('gps_tracking',      'tracking_id'),
            ('risk_zone',         'zone_id'),
            ('animal_risk_event', 'event_id'),
            ('prediction',        'prediction_id'),
            ('alert',             'alert_id'),
            ('ranger',            'ranger_id'),
            ('alert_assignment',  'assignment_id'),
            ('device',            'device_id'),
            ('habitat_zone',      'habitat_id'),
            ('health_record',     'record_id')
        ) AS t(tbl, col)
    LOOP
        EXECUTE format(
            'SELECT setval(pg_get_serial_sequence(%L, %L),
                           COALESCE((SELECT MAX(%I) FROM %I), 0) + 1, false)',
            r.tbl, r.col, r.col, r.tbl);
    END LOOP;
END $$;


-- ============================================================
-- 1. HELPER FUNCTIONS
-- ============================================================

-- Distance (metres) within which an animal is considered "approaching" a risk zone
CREATE OR REPLACE FUNCTION fn_risk_buffer_m()
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS
$$ SELECT 500::numeric $$;

-- 'low'..'critical'  ->  1..4
CREATE OR REPLACE FUNCTION fn_risk_rank(p_level TEXT)
RETURNS INT
LANGUAGE sql IMMUTABLE AS
$$
    SELECT CASE p_level
        WHEN 'low'      THEN 1
        WHEN 'medium'   THEN 2
        WHEN 'high'     THEN 3
        WHEN 'critical' THEN 4
        ELSE 0
    END
$$;

-- 1..4 -> 'low'..'critical'  (NULL for anything else)
CREATE OR REPLACE FUNCTION fn_rank_to_risk(p_rank INT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS
$$
    SELECT CASE p_rank
        WHEN 1 THEN 'low'
        WHEN 2 THEN 'medium'
        WHEN 3 THEN 'high'
        WHEN 4 THEN 'critical'
        ELSE NULL
    END
$$;

-- Risk level -> alert severity
CREATE OR REPLACE FUNCTION fn_risk_to_severity(p_level TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS
$$
    SELECT CASE p_level
        WHEN 'critical' THEN 'critical'
        WHEN 'high'     THEN 'warning'
        ELSE 'info'
    END
$$;


-- ============================================================
-- 2. TRIGGERS
-- ============================================================

-- ---------- T1: validate GPS fix + auto-compute speed ----------
CREATE OR REPLACE FUNCTION fn_trg_gps_validate()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
DECLARE
    v_status TEXT;
    v_prev   RECORD;
    v_hours  NUMERIC;
BEGIN
    SELECT status INTO v_status FROM Animal WHERE animal_id = NEW.animal_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'GPS rejected: animal % does not exist', NEW.animal_id;
    END IF;

    IF v_status = 'deceased' THEN
        RAISE EXCEPTION 'GPS rejected: animal % is marked deceased', NEW.animal_id;
    END IF;

    IF ST_X(NEW.location) NOT BETWEEN -180 AND 180
       OR ST_Y(NEW.location) NOT BETWEEN -90 AND 90 THEN
        RAISE EXCEPTION 'GPS rejected: coordinates out of range (% , %)',
            ST_X(NEW.location), ST_Y(NEW.location);
    END IF;

    IF NEW."timestamp" > now() + interval '5 minutes' THEN
        RAISE EXCEPTION 'GPS rejected: timestamp % is in the future', NEW."timestamp";
    END IF;

    IF NEW.speed IS NOT NULL AND NEW.speed < 0 THEN
        RAISE EXCEPTION 'GPS rejected: negative speed (%)', NEW.speed;
    END IF;

    -- If the collar did not report speed, derive it (km/h) from the previous fix
    IF NEW.speed IS NULL THEN
        SELECT g.location, g."timestamp"
          INTO v_prev
          FROM GPS_Tracking g
         WHERE g.animal_id = NEW.animal_id
           AND g."timestamp" < NEW."timestamp"
         ORDER BY g."timestamp" DESC
         LIMIT 1;

        IF FOUND THEN
            v_hours := EXTRACT(EPOCH FROM (NEW."timestamp" - v_prev."timestamp")) / 3600.0;
            IF v_hours > 0 THEN
                NEW.speed := ROUND(
                    ((ST_Distance(NEW.location::geography, v_prev.location::geography) / 1000.0)
                      / v_hours)::numeric, 2);
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gps_validate ON GPS_Tracking;
CREATE TRIGGER trg_gps_validate
    BEFORE INSERT ON GPS_Tracking
    FOR EACH ROW EXECUTE FUNCTION fn_trg_gps_validate();


-- ---------- T2: geofencing - detect entry / proximity to risk zones ----------
-- Inside a zone      -> event at the zone's risk_level
-- Within 500 m of it -> event one level lower (low zones are ignored when merely nearby)
-- Duplicate events for the same animal/zone/level within 1 hour are suppressed.
CREATE OR REPLACE FUNCTION fn_trg_gps_risk_check()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
DECLARE
    z       RECORD;
    v_level TEXT;
BEGIN
    FOR z IN
        SELECT rz.zone_id,
               rz.risk_level,
               ST_Distance(rz.boundary::geography, NEW.location::geography) AS dist
          FROM Risk_Zone rz
         WHERE ST_DWithin(rz.boundary::geography, NEW.location::geography, fn_risk_buffer_m())
    LOOP
        IF z.dist = 0 THEN
            v_level := z.risk_level;
        ELSE
            v_level := fn_rank_to_risk(fn_risk_rank(z.risk_level) - 1);
        END IF;

        CONTINUE WHEN v_level IS NULL;

        IF EXISTS (SELECT 1
                     FROM Animal_Risk_Event e
                    WHERE e.animal_id   = NEW.animal_id
                      AND e.zone_id     = z.zone_id
                      AND e.risk_level  = v_level
                      AND e.detected_at > now() - interval '1 hour') THEN
            CONTINUE;
        END IF;

        INSERT INTO Animal_Risk_Event (animal_id, zone_id, tracking_id, distance_m, risk_level)
        VALUES (NEW.animal_id, z.zone_id, NEW.tracking_id, ROUND(z.dist::numeric, 2), v_level);
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gps_risk_check ON GPS_Tracking;
CREATE TRIGGER trg_gps_risk_check
    AFTER INSERT ON GPS_Tracking
    FOR EACH ROW EXECUTE FUNCTION fn_trg_gps_risk_check();


-- ---------- T3: risk event -> alert (medium and above) ----------
CREATE OR REPLACE FUNCTION fn_trg_event_create_alert()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF fn_risk_rank(NEW.risk_level) >= 2 THEN
        INSERT INTO Alert (event_id, alert_type, severity)
        VALUES (NEW.event_id, 'detected', fn_risk_to_severity(NEW.risk_level));
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_create_alert ON Animal_Risk_Event;
CREATE TRIGGER trg_event_create_alert
    AFTER INSERT ON Animal_Risk_Event
    FOR EACH ROW EXECUTE FUNCTION fn_trg_event_create_alert();


-- ---------- T4: prediction -> alert (high and critical only) ----------
CREATE OR REPLACE FUNCTION fn_trg_prediction_alert()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF fn_risk_rank(NEW.predicted_risk) >= 3 THEN
        INSERT INTO Alert (prediction_id, alert_type, severity)
        VALUES (NEW.prediction_id, 'predicted', fn_risk_to_severity(NEW.predicted_risk));
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prediction_alert ON Prediction;
CREATE TRIGGER trg_prediction_alert
    AFTER INSERT ON Prediction
    FOR EACH ROW EXECUTE FUNCTION fn_trg_prediction_alert();


-- ---------- T5: auto-assign alert to the least-busy ranger of the reserve ----------
-- 'info' alerts are not assigned. Reserve = animal's home reserve
-- (falls back to the risk zone's reserve for detected events).
CREATE OR REPLACE FUNCTION fn_trg_alert_assign()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
DECLARE
    v_animal  INT;
    v_reserve INT;
    v_ranger  INT;
BEGIN
    IF NEW.severity = 'info' THEN
        RETURN NEW;
    END IF;

    IF NEW.event_id IS NOT NULL THEN
        SELECT e.animal_id INTO v_animal
          FROM Animal_Risk_Event e WHERE e.event_id = NEW.event_id;
    ELSE
        SELECT p.animal_id INTO v_animal
          FROM Prediction p WHERE p.prediction_id = NEW.prediction_id;
    END IF;

    SELECT a.home_reserve_id INTO v_reserve FROM Animal a WHERE a.animal_id = v_animal;

    IF v_reserve IS NULL AND NEW.event_id IS NOT NULL THEN
        SELECT rz.reserve_id INTO v_reserve
          FROM Animal_Risk_Event e
          JOIN Risk_Zone rz ON rz.zone_id = e.zone_id
         WHERE e.event_id = NEW.event_id;
    END IF;

    SELECT r.ranger_id INTO v_ranger
      FROM Ranger r
      LEFT JOIN Alert_Assignment aa
             ON aa.ranger_id = r.ranger_id
            AND aa.response_status IN ('pending', 'in_progress', 'escalated')
     WHERE r.reserve_id = v_reserve
     GROUP BY r.ranger_id
     ORDER BY COUNT(aa.assignment_id), r.ranger_id
     LIMIT 1;

    IF v_ranger IS NULL THEN
        RAISE WARNING 'Alert % has no ranger available in reserve %', NEW.alert_id, v_reserve;
    ELSE
        INSERT INTO Alert_Assignment (alert_id, ranger_id) VALUES (NEW.alert_id, v_ranger);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_alert_assign ON Alert;
CREATE TRIGGER trg_alert_assign
    AFTER INSERT ON Alert
    FOR EACH ROW EXECUTE FUNCTION fn_trg_alert_assign();


-- ---------- T6: keep Alert.status in sync with ranger response ----------
--   in_progress -> alert 'acknowledged'
--   resolved    -> alert 'resolved' once every assignment for it is resolved
CREATE OR REPLACE FUNCTION fn_trg_assignment_sync()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF NEW.response_status = 'in_progress' THEN
        UPDATE Alert SET status = 'acknowledged'
         WHERE alert_id = NEW.alert_id AND status = 'open';

    ELSIF NEW.response_status = 'resolved' THEN
        IF NOT EXISTS (SELECT 1
                         FROM Alert_Assignment aa
                        WHERE aa.alert_id = NEW.alert_id
                          AND aa.response_status <> 'resolved') THEN
            UPDATE Alert SET status = 'resolved'
             WHERE alert_id = NEW.alert_id AND status IN ('open', 'acknowledged');
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assignment_sync ON Alert_Assignment;
CREATE TRIGGER trg_assignment_sync
    AFTER UPDATE OF response_status ON Alert_Assignment
    FOR EACH ROW EXECUTE FUNCTION fn_trg_assignment_sync();


-- ---------- T7: audit log of every alert status change ----------
CREATE OR REPLACE FUNCTION fn_trg_alert_audit()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO Alert_Audit_Log (alert_id, old_status, new_status)
        VALUES (NEW.alert_id, NULL, NEW.status);
    ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO Alert_Audit_Log (alert_id, old_status, new_status)
        VALUES (NEW.alert_id, OLD.status, NEW.status);
    END IF;
    RETURN NULL;   -- AFTER trigger: return value is ignored
END;
$$;

DROP TRIGGER IF EXISTS trg_alert_audit ON Alert;
CREATE TRIGGER trg_alert_audit
    AFTER INSERT OR UPDATE OF status ON Alert
    FOR EACH ROW EXECUTE FUNCTION fn_trg_alert_audit();


-- ---------- T8: a rejected / overridden prediction dismisses its alert ----------
CREATE OR REPLACE FUNCTION fn_trg_prediction_review()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF NEW.review_status IN ('rejected', 'overridden')
       AND OLD.review_status IS DISTINCT FROM NEW.review_status THEN
        UPDATE Alert SET status = 'dismissed'
         WHERE prediction_id = NEW.prediction_id
           AND status IN ('open', 'acknowledged');

        -- clear the ranger's to-do for that alert too
        UPDATE Alert_Assignment SET response_status = 'resolved'
         WHERE response_status <> 'resolved'
           AND alert_id IN (SELECT alert_id FROM Alert
                             WHERE prediction_id = NEW.prediction_id
                               AND status = 'dismissed');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prediction_review ON Prediction;
CREATE TRIGGER trg_prediction_review
    AFTER UPDATE OF review_status ON Prediction
    FOR EACH ROW EXECUTE FUNCTION fn_trg_prediction_review();


-- ---------- T9: collar rules (battery warning, auto-off at 0%, no active collar on dead animal) ----------
CREATE OR REPLACE FUNCTION fn_trg_device_check()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
DECLARE
    v_animal_status TEXT;
BEGIN
    IF NEW.animal_id IS NOT NULL AND NEW.status = 'active' THEN
        SELECT status INTO v_animal_status FROM Animal WHERE animal_id = NEW.animal_id;
        IF v_animal_status = 'deceased' THEN
            RAISE EXCEPTION 'Cannot activate device % on deceased animal %',
                NEW.device_id, NEW.animal_id;
        END IF;
    END IF;

    IF NEW.battery_level IS NOT NULL AND NEW.status = 'active' THEN
        IF NEW.battery_level = 0 THEN
            NEW.status := 'inactive';
            RAISE NOTICE 'Device % battery is empty - marked inactive', NEW.device_id;
        ELSIF NEW.battery_level < 20 THEN
            RAISE WARNING 'Device % battery low (% percent)', NEW.device_id, NEW.battery_level;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_device_check ON Device;
CREATE TRIGGER trg_device_check
    BEFORE INSERT OR UPDATE ON Device
    FOR EACH ROW EXECUTE FUNCTION fn_trg_device_check();


-- ---------- T10: a 'deceased' health record marks the animal deceased ----------
CREATE OR REPLACE FUNCTION fn_trg_health_sync()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF NEW.health_status = 'deceased' THEN
        UPDATE Animal SET status = 'deceased'
         WHERE animal_id = NEW.animal_id AND status <> 'deceased';
    ELSIF NEW.health_status = 'critical' THEN
        RAISE NOTICE 'Animal % is in CRITICAL health - vet attention needed', NEW.animal_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_health_sync ON Health_Record;
CREATE TRIGGER trg_health_sync
    AFTER INSERT ON Health_Record
    FOR EACH ROW EXECUTE FUNCTION fn_trg_health_sync();


-- ---------- T11: animal deceased / inactive -> switch its collars off ----------
CREATE OR REPLACE FUNCTION fn_trg_animal_status_sync()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF NEW.status IN ('deceased', 'inactive') AND OLD.status IS DISTINCT FROM NEW.status THEN
        UPDATE Device SET status = 'inactive'
         WHERE animal_id = NEW.animal_id AND status = 'active';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_animal_status_sync ON Animal;
CREATE TRIGGER trg_animal_status_sync
    AFTER UPDATE OF status ON Animal
    FOR EACH ROW EXECUTE FUNCTION fn_trg_animal_status_sync();


-- ---------- T12: animal data validation + tag normalisation ----------
CREATE OR REPLACE FUNCTION fn_trg_animal_validate()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    NEW.tag_id := upper(trim(NEW.tag_id));

    IF NEW.birth_year IS NOT NULL
       AND (NEW.birth_year < 1900 OR NEW.birth_year > EXTRACT(YEAR FROM now())::int) THEN
        RAISE EXCEPTION 'Invalid birth year % for animal %', NEW.birth_year, NEW.tag_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_animal_validate ON Animal;
CREATE TRIGGER trg_animal_validate
    BEFORE INSERT OR UPDATE ON Animal
    FOR EACH ROW EXECUTE FUNCTION fn_trg_animal_validate();


-- ---------- T13: risk / habitat zones must be valid and overlap their reserve ----------
CREATE OR REPLACE FUNCTION fn_trg_zone_validate()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF NOT ST_IsValid(NEW.boundary) THEN
        RAISE EXCEPTION '% rejected: boundary geometry is invalid', TG_TABLE_NAME;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Reserve r
                    WHERE r.reserve_id = NEW.reserve_id
                      AND ST_Intersects(r.boundary, NEW.boundary)) THEN
        RAISE EXCEPTION '% rejected: boundary does not overlap reserve %',
            TG_TABLE_NAME, NEW.reserve_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_riskzone_validate ON Risk_Zone;
CREATE TRIGGER trg_riskzone_validate
    BEFORE INSERT OR UPDATE ON Risk_Zone
    FOR EACH ROW EXECUTE FUNCTION fn_trg_zone_validate();

DROP TRIGGER IF EXISTS trg_habitat_validate ON Habitat_Zone;
CREATE TRIGGER trg_habitat_validate
    BEFORE INSERT OR UPDATE ON Habitat_Zone
    FOR EACH ROW EXECUTE FUNCTION fn_trg_zone_validate();


-- ============================================================
-- 3. FUNCTIONS
-- ============================================================

-- F1: latest position + reserve check + nearest risk zone for one animal
CREATE OR REPLACE FUNCTION fn_animal_status(p_animal_id INT)
RETURNS TABLE (
    animal           INT,
    tag              TEXT,
    species          TEXT,
    last_seen        TIMESTAMPTZ,
    lon              DOUBLE PRECISION,
    lat              DOUBLE PRECISION,
    inside_reserve   BOOLEAN,
    nearest_zone     TEXT,
    zone_distance_m  NUMERIC,
    zone_risk_level  TEXT
)
LANGUAGE plpgsql STABLE AS
$$
BEGIN
    RETURN QUERY
    SELECT a.animal_id,
           a.tag_id::text,
           s.species_name::text,
           g."timestamp",
           ST_X(g.location),
           ST_Y(g.location),
           CASE WHEN r.boundary IS NULL THEN NULL
                ELSE ST_Within(g.location, r.boundary) END,
           nz.zone_name::text,
           ROUND(nz.d::numeric, 2),
           nz.risk_level::text
      FROM Animal a
      JOIN Species s ON s.species_id = a.species_id
      LEFT JOIN Reserve r ON r.reserve_id = a.home_reserve_id
      LEFT JOIN LATERAL (
            SELECT t."timestamp", t.location
              FROM GPS_Tracking t
             WHERE t.animal_id = a.animal_id
             ORDER BY t."timestamp" DESC
             LIMIT 1
      ) g ON TRUE
      LEFT JOIN LATERAL (
            SELECT rz.zone_name, rz.risk_level,
                   ST_Distance(rz.boundary::geography, g.location::geography) AS d
              FROM Risk_Zone rz
             ORDER BY rz.boundary <-> g.location
             LIMIT 1
      ) nz ON g.location IS NOT NULL
     WHERE a.animal_id = p_animal_id;
END;
$$;


-- F2: active animals whose latest fix is OUTSIDE their home reserve (boundary crossing)
CREATE OR REPLACE FUNCTION fn_animals_outside_reserve()
RETURNS TABLE (
    animal            INT,
    tag               TEXT,
    reserve           TEXT,
    last_seen         TIMESTAMPTZ,
    metres_outside    NUMERIC
)
LANGUAGE plpgsql STABLE AS
$$
BEGIN
    RETURN QUERY
    SELECT a.animal_id,
           a.tag_id::text,
           r.reserve_name::text,
           g."timestamp",
           ROUND(ST_Distance(g.location::geography, r.boundary::geography)::numeric, 2)
      FROM Animal a
      JOIN Reserve r ON r.reserve_id = a.home_reserve_id
      JOIN LATERAL (
            SELECT t."timestamp", t.location
              FROM GPS_Tracking t
             WHERE t.animal_id = a.animal_id
             ORDER BY t."timestamp" DESC
             LIMIT 1
      ) g ON TRUE
     WHERE a.status = 'active'
       AND NOT ST_Within(g.location, r.boundary);
END;
$$;


-- F3: total distance travelled (km) by an animal between two timestamps
CREATE OR REPLACE FUNCTION fn_distance_travelled_km(
    p_animal_id INT,
    p_from      TIMESTAMPTZ,
    p_to        TIMESTAMPTZ
)
RETURNS NUMERIC
LANGUAGE sql STABLE AS
$$
    SELECT COALESCE(
        ROUND((SUM(ST_Distance(x.location::geography, x.prev_loc::geography)) / 1000.0)::numeric, 3),
        0)
      FROM (
            SELECT g.location,
                   LAG(g.location) OVER (ORDER BY g."timestamp") AS prev_loc
              FROM GPS_Tracking g
             WHERE g.animal_id = p_animal_id
               AND g."timestamp" BETWEEN p_from AND p_to
      ) x
     WHERE x.prev_loc IS NOT NULL
$$;


-- F4: home-range estimate: area (km^2) of the convex hull of recent GPS fixes
CREATE OR REPLACE FUNCTION fn_home_range_km2(p_animal_id INT, p_days INT DEFAULT 30)
RETURNS NUMERIC
LANGUAGE sql STABLE AS
$$
    SELECT COALESCE(
        ROUND((ST_Area(ST_ConvexHull(ST_Collect(g.location))::geography) / 1000000.0)::numeric, 3),
        0)
      FROM GPS_Tracking g
     WHERE g.animal_id = p_animal_id
       AND g."timestamp" >= now() - make_interval(days => p_days)
$$;


-- F5: collars that need attention (low battery or flagged lost)
CREATE OR REPLACE FUNCTION fn_low_battery_devices(p_threshold NUMERIC DEFAULT 20)
RETURNS TABLE (
    device         INT,
    model          TEXT,
    battery_level  NUMERIC,
    device_status  TEXT,
    animal_tag     TEXT
)
LANGUAGE plpgsql STABLE AS
$$
BEGIN
    RETURN QUERY
    SELECT d.device_id,
           d.model::text,
           d.battery_level,
           d.status::text,
           a.tag_id::text
      FROM Device d
      LEFT JOIN Animal a ON a.animal_id = d.animal_id
     WHERE d.status IN ('active', 'maintenance', 'lost')
       AND (d.battery_level < p_threshold OR d.status = 'lost')
     ORDER BY d.battery_level;
END;
$$;


-- F6: risk score 0-100 for an animal from its recent risk events
-- weights: low=1, medium=3, high=6, critical=10, multiplied by 5 and capped at 100
CREATE OR REPLACE FUNCTION fn_animal_risk_score(p_animal_id INT, p_days INT DEFAULT 30)
RETURNS NUMERIC
LANGUAGE sql STABLE AS
$$
    SELECT LEAST(100,
        COALESCE(SUM(CASE e.risk_level
                        WHEN 'low'      THEN 1
                        WHEN 'medium'   THEN 3
                        WHEN 'high'     THEN 6
                        WHEN 'critical' THEN 10
                        ELSE 0 END), 0) * 5)::numeric
      FROM Animal_Risk_Event e
     WHERE e.animal_id = p_animal_id
       AND e.detected_at >= now() - make_interval(days => p_days)
$$;


-- F7: active animals whose last known position is within a radius of a point
-- (human-animal conflict: "which animals are near this village?")
CREATE OR REPLACE FUNCTION fn_animals_near_point(
    p_lon      DOUBLE PRECISION,
    p_lat      DOUBLE PRECISION,
    p_radius_m NUMERIC DEFAULT 1000
)
RETURNS TABLE (
    animal      INT,
    tag         TEXT,
    species     TEXT,
    distance_m  NUMERIC,
    last_seen   TIMESTAMPTZ
)
LANGUAGE sql STABLE AS
$$
    SELECT a.animal_id,
           a.tag_id::text,
           s.species_name::text,
           ROUND(ST_Distance(g.location::geography,
                             ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography)::numeric, 2),
           g."timestamp"
      FROM Animal a
      JOIN Species s ON s.species_id = a.species_id
      JOIN LATERAL (
            SELECT t."timestamp", t.location
              FROM GPS_Tracking t
             WHERE t.animal_id = a.animal_id
             ORDER BY t."timestamp" DESC
             LIMIT 1
      ) g ON TRUE
     WHERE a.status = 'active'
       AND ST_DWithin(g.location::geography,
                      ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
                      p_radius_m)
     ORDER BY 4
$$;


-- F8: movement history of an animal as a GeoJSON line (paste into geojson.io / Leaflet)
-- Returns NULL if the animal has fewer than 2 fixes in the period.
CREATE OR REPLACE FUNCTION fn_animal_track_geojson(
    p_animal_id INT,
    p_from      TIMESTAMPTZ,
    p_to        TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE sql STABLE AS
$$
    SELECT ST_AsGeoJSON(ST_MakeLine(g.location ORDER BY g."timestamp"))
      FROM GPS_Tracking g
     WHERE g.animal_id = p_animal_id
       AND g."timestamp" BETWEEN p_from AND p_to
    HAVING COUNT(*) >= 2
$$;


-- F9: active animals that have gone silent (no GPS fix for N hours = possible collar failure)
CREATE OR REPLACE FUNCTION fn_silent_collars(p_hours INT DEFAULT 24)
RETURNS TABLE (
    animal        INT,
    tag           TEXT,
    last_fix      TIMESTAMPTZ,
    hours_silent  NUMERIC
)
LANGUAGE sql STABLE AS
$$
    SELECT a.animal_id,
           a.tag_id::text,
           g.ts,
           ROUND((EXTRACT(EPOCH FROM (now() - g.ts)) / 3600.0)::numeric, 1)
      FROM Animal a
      LEFT JOIN LATERAL (
            SELECT MAX(t."timestamp") AS ts
              FROM GPS_Tracking t
             WHERE t.animal_id = a.animal_id
      ) g ON TRUE
     WHERE a.status = 'active'
       AND (g.ts IS NULL OR g.ts < now() - make_interval(hours => p_hours))
     ORDER BY g.ts NULLS FIRST
$$;


-- F10: animals that have barely moved for N hours (possible injury or death)
CREATE OR REPLACE FUNCTION fn_stationary_animals(
    p_hours      INT DEFAULT 12,
    p_max_move_m NUMERIC DEFAULT 100
)
RETURNS TABLE (
    animal    INT,
    tag       TEXT,
    fixes     BIGINT,
    spread_m  NUMERIC
)
LANGUAGE sql STABLE AS
$$
    SELECT a.animal_id,
           a.tag_id::text,
           x.fixes,
           ROUND(x.spread::numeric, 2)
      FROM Animal a
      JOIN LATERAL (
            SELECT COUNT(*) AS fixes,
                   MAX(ST_Distance(t.location::geography, c.centroid::geography)) AS spread
              FROM GPS_Tracking t
             CROSS JOIN LATERAL (
                    SELECT ST_Centroid(ST_Collect(t2.location)) AS centroid
                      FROM GPS_Tracking t2
                     WHERE t2.animal_id = a.animal_id
                       AND t2."timestamp" >= now() - make_interval(hours => p_hours)
             ) c
             WHERE t.animal_id = a.animal_id
               AND t."timestamp" >= now() - make_interval(hours => p_hours)
      ) x ON x.fixes >= 2 AND x.spread <= p_max_move_m
     WHERE a.status = 'active'
$$;


-- F11: one-row summary of a reserve (reads view v_reserve_risk_summary)
CREATE OR REPLACE FUNCTION fn_reserve_summary(p_reserve_id INT)
RETURNS TABLE (
    reserve          TEXT,
    animals_tracked  BIGINT,
    risk_zones       BIGINT,
    open_alerts      BIGINT,
    events_30d       BIGINT,
    rangers          BIGINT
)
LANGUAGE plpgsql STABLE AS
$$
BEGIN
    RETURN QUERY
    SELECT v.reserve_name::text, v.active_animals, v.risk_zones,
           v.open_alerts, v.events_30d, v.rangers
      FROM v_reserve_risk_summary v
     WHERE v.reserve_id = p_reserve_id;
END;
$$;


-- F12: how busy a risk zone has been
CREATE OR REPLACE FUNCTION fn_zone_activity(p_zone_id INT, p_days INT DEFAULT 30)
RETURNS TABLE (
    events     BIGINT,
    animals    BIGINT,
    last_event TIMESTAMPTZ
)
LANGUAGE sql STABLE AS
$$
    SELECT COUNT(*),
           COUNT(DISTINCT e.animal_id),
           MAX(e.detected_at)
      FROM Animal_Risk_Event e
     WHERE e.zone_id = p_zone_id
       AND e.detected_at >= now() - make_interval(days => p_days)
$$;


-- F13: everything currently on a ranger's plate
CREATE OR REPLACE FUNCTION fn_alerts_for_ranger(p_ranger_id INT)
RETURNS TABLE (
    alert_ref    BIGINT,
    sev          TEXT,
    alert_state  TEXT,
    assigned     TIMESTAMPTZ,
    response     TEXT,
    animal_tag   TEXT
)
LANGUAGE sql STABLE AS
$$
    SELECT al.alert_id,
           al.severity::text,
           al.status::text,
           aa.assigned_at,
           aa.response_status::text,
           an.tag_id::text
      FROM Alert_Assignment aa
      JOIN Alert al ON al.alert_id = aa.alert_id
      LEFT JOIN Animal_Risk_Event e ON e.event_id = al.event_id
      LEFT JOIN Prediction p        ON p.prediction_id = al.prediction_id
      JOIN Animal an ON an.animal_id = COALESCE(e.animal_id, p.animal_id)
     WHERE aa.ranger_id = p_ranger_id
       AND aa.response_status <> 'resolved'
       AND al.status IN ('open', 'acknowledged')
     ORDER BY CASE al.severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
              aa.assigned_at
$$;


CREATE OR REPLACE PROCEDURE sp_generate_predictions(
    p_lookback INTERVAL DEFAULT interval '24 hours'
)
LANGUAGE plpgsql AS
$$
DECLARE
    cur        CURSOR FOR SELECT animal_id, home_reserve_id FROM Animal WHERE status = 'active';
    a          RECORD;
    p1         RECORD;
    p2         RECORD;
    z          RECORD;
    v_proj     geometry;
    v_rank     INT;
    v_prob     NUMERIC;
    v_r        INT;
    v_pr       NUMERIC;
    v_inserted INT := 0;
BEGIN
    FOR a IN cur LOOP
        SELECT g.tracking_id, g.location INTO p2
          FROM GPS_Tracking g
         WHERE g.animal_id = a.animal_id AND g."timestamp" >= now() - p_lookback
         ORDER BY g."timestamp" DESC LIMIT 1;
        CONTINUE WHEN NOT FOUND;

        SELECT g.location INTO p1
          FROM GPS_Tracking g
         WHERE g.animal_id = a.animal_id
           AND g.tracking_id <> p2.tracking_id
           AND g."timestamp" >= now() - p_lookback
         ORDER BY g."timestamp" DESC LIMIT 1;
        CONTINUE WHEN NOT FOUND;

        -- linear extrapolation: next = last + (last - previous)
        v_proj := ST_SetSRID(ST_MakePoint(
                      2 * ST_X(p2.location) - ST_X(p1.location),
                      2 * ST_Y(p2.location) - ST_Y(p1.location)), 4326);

        v_rank := 0;
        v_prob := 0;

        -- (a) risk zones
        FOR z IN
            SELECT rz.risk_level,
                   ST_Distance(rz.boundary::geography, v_proj::geography) AS dist
              FROM Risk_Zone rz
             WHERE ST_DWithin(rz.boundary::geography, v_proj::geography, fn_risk_buffer_m())
        LOOP
            IF z.dist = 0 THEN
                v_r  := fn_risk_rank(z.risk_level);
                v_pr := 0.30 + 0.15 * v_r;
            ELSE
                v_r  := fn_risk_rank(z.risk_level) - 1;
                v_pr := (0.30 + 0.15 * v_r) * 0.7;
            END IF;

            IF v_r >= 1 AND (v_r > v_rank OR (v_r = v_rank AND v_pr > v_prob)) THEN
                v_rank := v_r;
                v_prob := v_pr;
            END IF;
        END LOOP;

        -- (b) boundary crossing
        IF a.home_reserve_id IS NOT NULL
           AND NOT ST_Within(v_proj, (SELECT r.boundary FROM Reserve r
                                       WHERE r.reserve_id = a.home_reserve_id)) THEN
            IF 3 > v_rank OR (3 = v_rank AND 0.85 > v_prob) THEN
                v_rank := 3;
                v_prob := 0.85;
            END IF;
        END IF;

        -- store (skip duplicates raised in the last hour)
        IF v_rank >= 1
           AND NOT EXISTS (SELECT 1 FROM Prediction pr
                            WHERE pr.animal_id      = a.animal_id
                              AND pr.predicted_risk = fn_rank_to_risk(v_rank)
                              AND pr.predicted_at   > now() - interval '1 hour') THEN
            INSERT INTO Prediction (animal_id, tracking_id, predicted_risk, risk_probability)
            VALUES (a.animal_id, p2.tracking_id, fn_rank_to_risk(v_rank), ROUND(v_prob, 4));
            v_inserted := v_inserted + 1;
        END IF;
    END LOOP;

    RAISE NOTICE 'sp_generate_predictions: % prediction(s) created', v_inserted;
END;
$$;


-- P2: ranger accepts an alert (creates the assignment if the ranger was not yet assigned)
CREATE OR REPLACE PROCEDURE sp_acknowledge_alert(p_alert_id BIGINT, p_ranger_id INT)
LANGUAGE plpgsql AS
$$
DECLARE
    v_status TEXT;
BEGIN
    SELECT status INTO v_status FROM Alert WHERE alert_id = p_alert_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Alert % does not exist', p_alert_id;
    END IF;
    IF v_status IN ('resolved', 'dismissed') THEN
        RAISE EXCEPTION 'Alert % is already %', p_alert_id, v_status;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Ranger WHERE ranger_id = p_ranger_id) THEN
        RAISE EXCEPTION 'Ranger % does not exist', p_ranger_id;
    END IF;

    UPDATE Alert_Assignment
       SET response_status = 'in_progress'
     WHERE alert_id = p_alert_id
       AND ranger_id = p_ranger_id
       AND response_status = 'pending';

    IF NOT FOUND THEN
        INSERT INTO Alert_Assignment (alert_id, ranger_id, response_status)
        VALUES (p_alert_id, p_ranger_id, 'in_progress');
    END IF;

    UPDATE Alert SET status = 'acknowledged'
     WHERE alert_id = p_alert_id AND status = 'open';
END;
$$;


-- P3: ranger marks their part of an alert as resolved
-- (trigger T6 closes the alert when all assignments are resolved)
CREATE OR REPLACE PROCEDURE sp_resolve_alert(p_alert_id BIGINT, p_ranger_id INT)
LANGUAGE plpgsql AS
$$
BEGIN
    UPDATE Alert_Assignment
       SET response_status = 'resolved'
     WHERE alert_id = p_alert_id
       AND ranger_id = p_ranger_id
       AND response_status IN ('pending', 'in_progress', 'escalated');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No open assignment of alert % for ranger %', p_alert_id, p_ranger_id;
    END IF;
END;
$$;


-- P4: one monitoring sweep: run predictions, then list animals outside their reserve.
-- Schedule with pg_cron (e.g. every 15 min) or call manually:  CALL sp_run_monitoring_cycle();
CREATE OR REPLACE PROCEDURE sp_run_monitoring_cycle()
LANGUAGE plpgsql AS
$$
DECLARE
    o RECORD;
BEGIN
    CALL sp_generate_predictions();

    FOR o IN SELECT * FROM fn_animals_outside_reserve() LOOP
        RAISE NOTICE 'OUTSIDE RESERVE: % (animal %) is % m outside %, last seen %',
            o.tag, o.animal, o.metres_outside, o.reserve, o.last_seen;
    END LOOP;
END;
$$;


-- P5: register a new tagged animal and (optionally) fit the first free collar
-- Usage: CALL sp_register_animal(1, 1, 'TAG-021', 'F', 2020, true, NULL);   -- returns the new animal_id
CREATE OR REPLACE PROCEDURE sp_register_animal(
    p_species_id    INT,
    p_reserve_id    INT,
    p_tag           TEXT,
    p_sex           CHAR,
    p_birth_year    INT,
    p_assign_device BOOLEAN DEFAULT TRUE,
    INOUT p_animal_id INT DEFAULT NULL
)
LANGUAGE plpgsql AS
$$
DECLARE
    v_device INT;
BEGIN
    BEGIN
        INSERT INTO Animal (species_id, home_reserve_id, tag_id, sex, birth_year)
        VALUES (p_species_id, p_reserve_id, p_tag, p_sex, p_birth_year)
        RETURNING animal_id INTO p_animal_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'Tag % is already registered', upper(trim(p_tag));
        WHEN foreign_key_violation THEN
            RAISE EXCEPTION 'Unknown species % or reserve %', p_species_id, p_reserve_id;
    END;

    IF p_assign_device THEN
        SELECT d.device_id INTO v_device
          FROM Device d
         WHERE d.animal_id IS NULL
         ORDER BY d.device_id
         LIMIT 1;

        IF FOUND THEN
            UPDATE Device
               SET animal_id = p_animal_id, status = 'active', install_date = CURRENT_DATE
             WHERE device_id = v_device;
            RAISE NOTICE 'Animal % registered; collar % fitted', p_animal_id, v_device;
        ELSE
            RAISE NOTICE 'Animal % registered; no free collar available', p_animal_id;
        END IF;
    END IF;
END;
$$;


-- P6: fit a collar to an animal
CREATE OR REPLACE PROCEDURE sp_assign_device(p_device_id INT, p_animal_id INT)
LANGUAGE plpgsql AS
$$
DECLARE
    v_status TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Device WHERE device_id = p_device_id) THEN
        RAISE EXCEPTION 'Device % does not exist', p_device_id;
    END IF;

    SELECT status INTO v_status FROM Animal WHERE animal_id = p_animal_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Animal % does not exist', p_animal_id;
    END IF;
    IF v_status = 'deceased' THEN
        RAISE EXCEPTION 'Animal % is deceased - cannot fit a collar', p_animal_id;
    END IF;

    UPDATE Device
       SET animal_id = p_animal_id, status = 'active', install_date = CURRENT_DATE
     WHERE device_id = p_device_id;
END;
$$;


-- P7: record a vet checkup (trigger T10 marks the animal deceased if needed)
CREATE OR REPLACE PROCEDURE sp_record_health_checkup(
    p_animal_id INT,
    p_weight_kg NUMERIC,
    p_status    TEXT,
    p_notes     TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS
$$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Animal WHERE animal_id = p_animal_id) THEN
        RAISE EXCEPTION 'Animal % does not exist', p_animal_id;
    END IF;

    INSERT INTO Health_Record (animal_id, checkup_date, weight_kg, health_status, notes)
    VALUES (p_animal_id, CURRENT_DATE, p_weight_kg, p_status, p_notes);
END;
$$;


-- P8: escalate warning/critical alerts that no ranger has picked up within N hours
-- Usage: CALL sp_escalate_stale_alerts(6, 0);  -- INOUT value returns how many were escalated
CREATE OR REPLACE PROCEDURE sp_escalate_stale_alerts(
    p_hours INT DEFAULT 6,
    INOUT p_count INT DEFAULT 0
)
LANGUAGE plpgsql AS
$$
BEGIN
    WITH upd AS (
        UPDATE Alert_Assignment aa
           SET response_status = 'escalated'
          FROM Alert al
         WHERE al.alert_id = aa.alert_id
           AND al.status IN ('open', 'acknowledged')
           AND al.severity IN ('warning', 'critical')
           AND aa.response_status = 'pending'
           AND aa.assigned_at < now() - make_interval(hours => p_hours)
        RETURNING aa.assignment_id
    )
    SELECT COUNT(*) INTO p_count FROM upd;

    RAISE NOTICE 'sp_escalate_stale_alerts: % assignment(s) escalated', p_count;
END;
$$;


-- P9: a human reviews an AI prediction (rejected/overridden predictions dismiss their alert via T8)
CREATE OR REPLACE PROCEDURE sp_review_prediction(p_prediction_id BIGINT, p_review TEXT)
LANGUAGE plpgsql AS
$$
BEGIN
    IF p_review NOT IN ('confirmed', 'overridden', 'rejected') THEN
        RAISE EXCEPTION 'Review must be confirmed, overridden or rejected (got %)', p_review;
    END IF;

    UPDATE Prediction SET review_status = p_review WHERE prediction_id = p_prediction_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Prediction % does not exist', p_prediction_id;
    END IF;
END;
$$;


-- P10: move an alert from one ranger to another
CREATE OR REPLACE PROCEDURE sp_reassign_alert(
    p_alert_id    BIGINT,
    p_from_ranger INT,
    p_to_ranger   INT
)
LANGUAGE plpgsql AS
$$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Ranger WHERE ranger_id = p_to_ranger) THEN
        RAISE EXCEPTION 'Ranger % does not exist', p_to_ranger;
    END IF;

    UPDATE Alert_Assignment
       SET ranger_id = p_to_ranger,
           assigned_at = now(),
           response_status = 'pending'
     WHERE alert_id = p_alert_id
       AND ranger_id = p_from_ranger
       AND response_status <> 'resolved';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Alert % has no open assignment for ranger %', p_alert_id, p_from_ranger;
    END IF;
END;
$$;


-- P11: dismiss a false alarm (alert -> dismissed, ranger workload cleared)
CREATE OR REPLACE PROCEDURE sp_dismiss_alert(p_alert_id BIGINT, p_reason TEXT DEFAULT NULL)
LANGUAGE plpgsql AS
$$
BEGIN
    UPDATE Alert SET status = 'dismissed'
     WHERE alert_id = p_alert_id AND status IN ('open', 'acknowledged');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Alert % does not exist or is already closed', p_alert_id;
    END IF;

    UPDATE Alert_Assignment SET response_status = 'resolved'
     WHERE alert_id = p_alert_id AND response_status <> 'resolved';

    RAISE NOTICE 'Alert % dismissed. Reason: %', p_alert_id, COALESCE(p_reason, 'not given');
END;
$$;


-- P12: text report per reserve (cursor loop over reserves)
CREATE OR REPLACE PROCEDURE sp_generate_daily_report()
LANGUAGE plpgsql AS
$$
DECLARE
    cur CURSOR FOR SELECT reserve_id FROM Reserve ORDER BY reserve_id;
    r   RECORD;
    s   RECORD;
BEGIN
    RAISE NOTICE '===== WILDTRACK DAILY REPORT (%) =====', CURRENT_DATE;
    FOR r IN cur LOOP
        SELECT * INTO s FROM fn_reserve_summary(r.reserve_id);
        RAISE NOTICE '% | animals=% zones=% rangers=% open_alerts=% events_30d=%',
            s.reserve, s.animals_tracked, s.risk_zones, s.rangers, s.open_alerts, s.events_30d;
    END LOOP;
END;
$$;


-- P13: insert a GPS fix but never crash: failures come back as a message
-- (shows exception handling).  Usage: CALL sp_safe_insert_gps(3, 93.41, 26.60, now(), NULL);
CREATE OR REPLACE PROCEDURE sp_safe_insert_gps(
    p_animal_id INT,
    p_lon       DOUBLE PRECISION,
    p_lat       DOUBLE PRECISION,
    p_ts        TIMESTAMPTZ DEFAULT now(),
    INOUT p_result TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS
$$
BEGIN
    INSERT INTO GPS_Tracking (animal_id, "timestamp", location)
    VALUES (p_animal_id, p_ts, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326));

    p_result := 'OK: GPS fix stored';
EXCEPTION
    WHEN OTHERS THEN
        p_result := 'REJECTED: ' || SQLERRM;
END;
$$;


-- ============================================================
-- 5. VIEWS
-- ============================================================

-- V1: open alerts dashboard (critical first)
CREATE OR REPLACE VIEW v_open_alerts AS
SELECT al.alert_id,
       al.alert_type,
       al.severity,
       al.status,
       al.created_at,
       an.tag_id          AS animal_tag,
       sp.species_name,
       rs.reserve_name,
       rz.zone_name       AS risk_zone,
       p.predicted_risk,
       rg.name            AS ranger,
       aa.response_status
  FROM Alert al
  LEFT JOIN Animal_Risk_Event e ON e.event_id = al.event_id
  LEFT JOIN Risk_Zone rz        ON rz.zone_id = e.zone_id
  LEFT JOIN Prediction p        ON p.prediction_id = al.prediction_id
  JOIN Animal an                ON an.animal_id = COALESCE(e.animal_id, p.animal_id)
  JOIN Species sp               ON sp.species_id = an.species_id
  LEFT JOIN Reserve rs          ON rs.reserve_id = an.home_reserve_id
  LEFT JOIN Alert_Assignment aa ON aa.alert_id = al.alert_id
  LEFT JOIN Ranger rg           ON rg.ranger_id = aa.ranger_id
 WHERE al.status IN ('open', 'acknowledged')
 ORDER BY CASE al.severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
          al.created_at DESC;


-- V2: where is every animal right now?
CREATE OR REPLACE VIEW v_animal_latest_position AS
SELECT a.animal_id,
       a.tag_id,
       s.species_name,
       s.conservation_status,
       rs.reserve_name,
       a.status              AS animal_status,
       g."timestamp"         AS last_seen,
       ST_X(g.location)      AS lon,
       ST_Y(g.location)      AS lat,
       g.speed,
       CASE WHEN rs.boundary IS NULL OR g.location IS NULL THEN NULL
            ELSE ST_Within(g.location, rs.boundary) END AS inside_home_reserve
  FROM Animal a
  JOIN Species s ON s.species_id = a.species_id
  LEFT JOIN Reserve rs ON rs.reserve_id = a.home_reserve_id
  LEFT JOIN LATERAL (
        SELECT t."timestamp", t.location, t.speed
          FROM GPS_Tracking t
         WHERE t.animal_id = a.animal_id
         ORDER BY t."timestamp" DESC
         LIMIT 1
  ) g ON TRUE;


-- V3: one row per reserve - animals, zones, rangers, alerts, recent events
CREATE OR REPLACE VIEW v_reserve_risk_summary AS
SELECT r.reserve_id,
       r.reserve_name,
       r.state,
       (SELECT COUNT(*) FROM Animal a
         WHERE a.home_reserve_id = r.reserve_id AND a.status = 'active')   AS active_animals,
       (SELECT COUNT(*) FROM Risk_Zone z WHERE z.reserve_id = r.reserve_id) AS risk_zones,
       (SELECT COUNT(*) FROM Ranger g WHERE g.reserve_id = r.reserve_id)    AS rangers,
       (SELECT COUNT(*) FROM Animal_Risk_Event e
          JOIN Animal a ON a.animal_id = e.animal_id
         WHERE a.home_reserve_id = r.reserve_id
           AND e.detected_at >= now() - interval '30 days')                 AS events_30d,
       (SELECT COUNT(DISTINCT al.alert_id) FROM Alert al
          LEFT JOIN Animal_Risk_Event e ON e.event_id = al.event_id
          LEFT JOIN Prediction p        ON p.prediction_id = al.prediction_id
          JOIN Animal an ON an.animal_id = COALESCE(e.animal_id, p.animal_id)
         WHERE an.home_reserve_id = r.reserve_id
           AND al.status IN ('open', 'acknowledged'))                       AS open_alerts
  FROM Reserve r;


-- V4: ranger workload
CREATE OR REPLACE VIEW v_ranger_workload AS
SELECT rg.ranger_id,
       rg.name AS ranger,
       rs.reserve_name,
       COUNT(*) FILTER (WHERE aa.response_status = 'pending')     AS pending_cnt,
       COUNT(*) FILTER (WHERE aa.response_status = 'in_progress') AS in_progress_cnt,
       COUNT(*) FILTER (WHERE aa.response_status = 'escalated')   AS escalated_cnt,
       COUNT(*) FILTER (WHERE aa.response_status = 'resolved')    AS resolved_cnt,
       COUNT(aa.assignment_id)                                    AS total_cnt
  FROM Ranger rg
  JOIN Reserve rs ON rs.reserve_id = rg.reserve_id
  LEFT JOIN Alert_Assignment aa ON aa.ranger_id = rg.ranger_id
 GROUP BY rg.ranger_id, rg.name, rs.reserve_name;


-- V5: per-species dashboard (how threatened, how many animals, how many risk events)
CREATE OR REPLACE VIEW v_species_dashboard AS
SELECT s.species_id,
       s.species_name,
       s.conservation_status,
       COUNT(DISTINCT a.animal_id)                                        AS animals_total,
       COUNT(DISTINCT a.animal_id) FILTER (WHERE a.status = 'active')     AS animals_active,
       COUNT(e.event_id)                                                  AS risk_events,
       COUNT(e.event_id) FILTER (WHERE e.risk_level = 'critical')         AS critical_events
  FROM Species s
  LEFT JOIN Animal a ON a.species_id = s.species_id
  LEFT JOIN Animal_Risk_Event e ON e.animal_id = a.animal_id
 GROUP BY s.species_id, s.species_name, s.conservation_status;


-- V6: collar health
CREATE OR REPLACE VIEW v_device_health AS
SELECT d.device_id,
       d.model,
       d.status,
       d.battery_level,
       CASE WHEN d.battery_level IS NULL THEN 'unknown'
            WHEN d.battery_level < 20    THEN 'low'
            WHEN d.battery_level < 50    THEN 'medium'
            ELSE 'good' END                  AS battery_band,
       a.tag_id                              AS animal_tag,
       d.install_date,
       CURRENT_DATE - d.install_date         AS days_in_service
  FROM Device d
  LEFT JOIN Animal a ON a.animal_id = d.animal_id;


-- V7: latest health checkup per animal
CREATE OR REPLACE VIEW v_animal_health_latest AS
SELECT DISTINCT ON (h.animal_id)
       h.animal_id,
       a.tag_id,
       s.species_name,
       h.checkup_date,
       h.weight_kg,
       h.health_status,
       h.notes
  FROM Health_Record h
  JOIN Animal a  ON a.animal_id = h.animal_id
  JOIN Species s ON s.species_id = a.species_id
 ORDER BY h.animal_id, h.checkup_date DESC, h.record_id DESC;


-- V8: animals ranked by 30-day risk score
CREATE OR REPLACE VIEW v_high_risk_animals AS
SELECT a.animal_id,
       a.tag_id,
       s.species_name,
       fn_animal_risk_score(a.animal_id, 30) AS risk_score,
       (SELECT COUNT(*) FROM Animal_Risk_Event e
         WHERE e.animal_id = a.animal_id
           AND e.detected_at >= now() - interval '30 days') AS events_30d
  FROM Animal a
  JOIN Species s ON s.species_id = a.species_id
 WHERE a.status = 'active'
 ORDER BY risk_score DESC, a.animal_id;


-- V9: AI predictions waiting for human review
CREATE OR REPLACE VIEW v_prediction_review_queue AS
SELECT p.prediction_id,
       a.tag_id        AS animal_tag,
       s.species_name,
       p.predicted_risk,
       p.risk_probability,
       p.predicted_at,
       EXISTS (SELECT 1 FROM Alert al WHERE al.prediction_id = p.prediction_id) AS has_alert
  FROM Prediction p
  JOIN Animal a  ON a.animal_id = p.animal_id
  JOIN Species s ON s.species_id = a.species_id
 WHERE p.review_status = 'unreviewed'
 ORDER BY p.risk_probability DESC;


-- V10: which risk zones are hotspots?
CREATE OR REPLACE VIEW v_zone_hotspots AS
SELECT z.zone_id,
       z.zone_name,
       r.reserve_name,
       z.risk_type,
       z.risk_level            AS zone_level,
       COUNT(e.event_id)       AS events_total,
       COUNT(DISTINCT e.animal_id) AS distinct_animals,
       MAX(e.detected_at)      AS last_event
  FROM Risk_Zone z
  JOIN Reserve r ON r.reserve_id = z.reserve_id
  LEFT JOIN Animal_Risk_Event e ON e.zone_id = z.zone_id
 GROUP BY z.zone_id, z.zone_name, r.reserve_name, z.risk_type, z.risk_level
 ORDER BY events_total DESC, z.zone_id;

DO $$
BEGIN
    INSERT INTO GPS_Tracking (animal_id, "timestamp", location)
    VALUES (9999, now(), ST_SetSRID(ST_MakePoint(78.9, 29.5), 4326));
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

-- ---------- A2: geofence -> risk event -> alert -> ranger assignment ----------
-- Animal 3 (Kaziranga) enters the CRITICAL poaching zone.
-- Expected: critical event, critical alert, ranger Dhruba Gogoi assigned
INSERT INTO GPS_Tracking (animal_id, "timestamp", location)
VALUES (3, now(), ST_SetSRID(ST_MakePoint(93.41, 26.60), 4326));

SELECT event_id, animal_id, zone_id, distance_m, risk_level
  FROM Animal_Risk_Event ORDER BY event_id DESC LIMIT 1;
SELECT alert_id, severity, status, animal_tag, risk_zone, ranger, response_status
  FROM v_open_alerts WHERE animal_tag = 'TAG-003';

-- ---------- A3: prediction -> alert ----------
-- Animal 2 (Ranthambore) is heading toward the HIGH-risk road zone.
INSERT INTO GPS_Tracking (animal_id, "timestamp", location)
VALUES (2, now() - interval '10 minutes', ST_SetSRID(ST_MakePoint(76.480, 26.050), 4326));
INSERT INTO GPS_Tracking (animal_id, "timestamp", location)
VALUES (2, now(),                         ST_SetSRID(ST_MakePoint(76.510, 26.055), 4326));

CALL sp_generate_predictions(interval '1 hour');
-- Expected NOTICE: 1 prediction created (high, probability 0.75) + a warning alert for animal 2

SELECT prediction_id, animal_id, predicted_risk, risk_probability
  FROM Prediction ORDER BY prediction_id DESC LIMIT 1;

-- ---------- A4: ranger workflow ----------
DO $$
DECLARE
    v_alert  BIGINT;
    v_ranger INT;
BEGIN
    SELECT al.alert_id, aa.ranger_id INTO v_alert, v_ranger
      FROM Alert al JOIN Alert_Assignment aa ON aa.alert_id = al.alert_id
     WHERE al.severity = 'critical' AND al.status = 'open'
     ORDER BY al.alert_id DESC LIMIT 1;

    CALL sp_acknowledge_alert(v_alert, v_ranger);
    RAISE NOTICE 'Alert % after acknowledge: %', v_alert,
        (SELECT status FROM Alert WHERE alert_id = v_alert);   -- acknowledged
    CALL sp_resolve_alert(v_alert, v_ranger);
    RAISE NOTICE 'Alert % after resolve: %', v_alert,
        (SELECT status FROM Alert WHERE alert_id = v_alert);   -- resolved
END $$;

-- ---------- A5: audit log (trigger T7) ----------
-- Expected: the rhino alert shows  NULL->open, open->acknowledged, acknowledged->resolved
SELECT alert_id, old_status, new_status, changed_by
  FROM Alert_Audit_Log
 WHERE alert_id = (SELECT MAX(alert_id) FROM Alert WHERE severity = 'critical')
 ORDER BY log_id;


-- ############ PART B: AUTOMATION TRIGGERS ############

-- ---------- B1: collar battery rules (T9) ----------
UPDATE Device SET battery_level = 15 WHERE device_id = 1;   -- expect WARNING: battery low
UPDATE Device SET battery_level = 0  WHERE device_id = 2;   -- expect NOTICE + status becomes inactive
SELECT device_id, battery_level, status FROM Device WHERE device_id IN (1, 2) ORDER BY device_id;

-- ---------- B2: chain  health record -> animal deceased -> collar off (T10 + T11) ----------
CALL sp_record_health_checkup(7, 850, 'deceased', 'Found dead near water hole');
SELECT animal_id, status FROM Animal WHERE animal_id = 7;       -- deceased
SELECT device_id, status FROM Device WHERE animal_id = 7;       -- inactive

-- GPS for a deceased animal is now refused (never crashes, returns a message)
CALL sp_safe_insert_gps(7, 80.0, 23.0, now(), NULL);            -- REJECTED: ... deceased
CALL sp_safe_insert_gps(1, 78.9, 29.5, now(), NULL);            -- OK: GPS fix stored

-- ---------- B3: register a new animal (T12 uppercases the tag; fits a free collar) ----------
CALL sp_register_animal(1, 1, ' tag-021 ', 'F', 2020, true, NULL);
-- Expected: animal 21, tag TAG-021, collar 20 fitted
SELECT animal_id, tag_id, home_reserve_id FROM Animal WHERE tag_id = 'TAG-021';
SELECT device_id, animal_id, status FROM Device WHERE device_id = 20;

DO $$
DECLARE v_id INT;
BEGIN
    CALL sp_register_animal(1, 1, 'TAG-021', 'M', 2020, false, v_id);   -- duplicate tag
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;
DO $$
DECLARE v_id INT;
BEGIN
    CALL sp_register_animal(1, 1, 'TAG-022', 'M', 2999, false, v_id);   -- birth year in the future
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

-- ---------- B4: zone validation (T13) ----------
DO $$
BEGIN
    INSERT INTO Risk_Zone (reserve_id, zone_name, risk_type, risk_level, boundary)
    VALUES (1, 'Zone in the wrong country', 'road', 'high',
            ST_GeomFromText('POLYGON((10 10, 11 10, 11 11, 10 11, 10 10))', 4326));
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

-- ---------- B5: reviewing an AI prediction (T8) ----------
-- Rejecting the elephant prediction should dismiss its alert
DO $$
DECLARE
    v_pred BIGINT;
BEGIN
    SELECT prediction_id INTO v_pred FROM Prediction ORDER BY prediction_id DESC LIMIT 1;
    CALL sp_review_prediction(v_pred, 'rejected');
    RAISE NOTICE 'Alert of prediction % is now: %', v_pred,
        (SELECT status FROM Alert WHERE prediction_id = v_pred);   -- dismissed
END $$;

-- ---------- B6: other alert procedures ----------
CALL sp_dismiss_alert(1, 'False alarm - animal only passing the settlement edge');
DO $$
DECLARE
    v_ranger INT;
BEGIN
    SELECT ranger_id INTO v_ranger FROM Alert_Assignment WHERE alert_id = 5 LIMIT 1;
    CALL sp_reassign_alert(5, v_ranger, CASE WHEN v_ranger = 1 THEN 2 ELSE 1 END);
    RAISE NOTICE 'Alert 5 reassigned';
END $$;
CALL sp_escalate_stale_alerts(6, 0);       -- escalates old pending warning/critical assignments


-- ############ PART C: ANALYSIS FUNCTIONS ############
SELECT * FROM fn_animal_status(1);
SELECT * FROM fn_animals_outside_reserve();                           -- 0 rows: all animals inside
SELECT fn_distance_travelled_km(2, now() - interval '1 day', now())  AS km_travelled_animal2;
SELECT fn_home_range_km2(2, 30)                                       AS home_range_km2_animal2;
SELECT * FROM fn_low_battery_devices(25);
SELECT fn_animal_risk_score(3, 30)                                    AS risk_score_rhino;
SELECT * FROM fn_animals_near_point(78.90, 29.50, 5000);              -- finds the Corbett tiger (TAG-001)
SELECT fn_animal_track_geojson(2, now() - interval '1 day', now())    AS elephant_track_geojson;
SELECT * FROM fn_silent_collars(24) LIMIT 5;
SELECT * FROM fn_stationary_animals(24, 100000);                       -- loose limit so the demo shows rows
SELECT * FROM fn_reserve_summary(3);
SELECT * FROM fn_zone_activity(3, 30);
SELECT * FROM fn_alerts_for_ranger(2);                                -- Meera's open work


-- ############ PART D: VIEWS ############
SELECT * FROM v_open_alerts LIMIT 5;
SELECT animal_id, tag_id, species_name, last_seen, inside_home_reserve FROM v_animal_latest_position LIMIT 5;
SELECT * FROM v_reserve_risk_summary LIMIT 5;
SELECT * FROM v_ranger_workload LIMIT 5;
SELECT species_name, conservation_status, animals_active, risk_events, critical_events FROM v_species_dashboard LIMIT 5;
SELECT * FROM v_device_health LIMIT 5;
SELECT animal_id, tag_id, checkup_date, health_status FROM v_animal_health_latest LIMIT 5;
SELECT * FROM v_high_risk_animals LIMIT 5;
SELECT * FROM v_prediction_review_queue LIMIT 5;
SELECT * FROM v_zone_hotspots LIMIT 5;


-- ############ PART E: FULL SWEEPS ############
CALL sp_run_monitoring_cycle();
CALL sp_generate_daily_report();


-- ############ PART F: OPERATIONAL DASHBOARD QUERIES ############

-- 1. Animal Risk Events + Risk Zones
SELECT ar.event_id, a.tag_id, rz.zone_name, ar.risk_level, ar.distance_m
FROM Animal_Risk_Event ar
JOIN Animal a
    ON ar.animal_id = a.animal_id
JOIN Risk_Zone rz
    ON ar.zone_id = rz.zone_id;

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
