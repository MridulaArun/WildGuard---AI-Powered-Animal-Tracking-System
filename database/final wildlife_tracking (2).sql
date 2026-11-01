-- 1. Completely drop PostGIS with cascade to clear all broken internal bindings
DROP EXTENSION IF EXISTS postgis CASCADE;

-- 2. Wipe the public schema clean
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

-- 3. Reinstall PostGIS fresh into the clean schema
CREATE EXTENSION postgis;

-- =====================================================================
BEGIN;
 
CREATE EXTENSION IF NOT EXISTS postgis;
 
-- Re-runnable reset: drop only our own tables (leaves PostGIS and the
-- public schema itself untouched), children first.
DROP TABLE IF EXISTS
    Audit_Log, Alert_Assignment, Alert, Prediction, Animal_Risk_Event, Health_Record,
    Habitat_Zone, Device, Ranger, Risk_Zone, GPS_Tracking, Animal,
    Reserve, Species
CASCADE;
 
-- ---------- CORE TABLES ----------
 
CREATE TABLE Species (
    species_id          SERIAL PRIMARY KEY,
    species_name        VARCHAR(100) NOT NULL,
    scientific_name     VARCHAR(150) NOT NULL,
    conservation_status VARCHAR(50) NOT NULL
);
 
CREATE TABLE Reserve (
    reserve_id   SERIAL PRIMARY KEY,
    reserve_name VARCHAR(150) NOT NULL,
    state        VARCHAR(100),
    boundary     geometry(Polygon, 4326) NOT NULL
);
 
CREATE TABLE Animal (
    animal_id         SERIAL PRIMARY KEY,
    species_id        INT NOT NULL REFERENCES Species(species_id),
    home_reserve_id   INT REFERENCES Reserve(reserve_id),
    tag_id            VARCHAR(50) NOT NULL UNIQUE,
    sex               CHAR(1) CHECK (sex IN ('M', 'F', 'U')),
    birth_year        INT,
    status            VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'deceased', 'unknown'))
);
 
CREATE TABLE GPS_Tracking (
    tracking_id   BIGSERIAL PRIMARY KEY,
    animal_id     INT NOT NULL REFERENCES Animal(animal_id),
    timestamp     TIMESTAMPTZ NOT NULL,
    location      geometry(Point, 4326) NOT NULL,
    speed         NUMERIC(6,2)
);
 
CREATE TABLE Risk_Zone (
    zone_id       SERIAL PRIMARY KEY,
    reserve_id    INT NOT NULL REFERENCES Reserve(reserve_id),
    zone_name     VARCHAR(150) NOT NULL,
    risk_type     VARCHAR(30) NOT NULL
        CHECK (risk_type IN ('human_settlement', 'road', 'poaching_zone', 'agricultural_land', 'other')),
    risk_level    VARCHAR(10) NOT NULL
        CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    boundary      geometry(Polygon, 4326) NOT NULL
);
 
CREATE TABLE Animal_Risk_Event (
    event_id      BIGSERIAL PRIMARY KEY,
    animal_id     INT NOT NULL REFERENCES Animal(animal_id),
    zone_id       INT NOT NULL REFERENCES Risk_Zone(zone_id),
    tracking_id   BIGINT NOT NULL REFERENCES GPS_Tracking(tracking_id),
    detected_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    distance_m    NUMERIC(10,2) NOT NULL,   -- metres from the GPS fix to the zone boundary (0 = inside)
    risk_level    VARCHAR(10) NOT NULL
        CHECK (risk_level IN ('low', 'medium', 'high', 'critical'))
);
 
CREATE TABLE Prediction (
    prediction_id     BIGSERIAL PRIMARY KEY,
    animal_id         INT NOT NULL REFERENCES Animal(animal_id),
    tracking_id       BIGINT REFERENCES GPS_Tracking(tracking_id),
    predicted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    predicted_risk    VARCHAR(10) NOT NULL
        CHECK (predicted_risk IN ('low', 'medium', 'high', 'critical')),
    risk_probability  NUMERIC(5,4) NOT NULL CHECK (risk_probability BETWEEN 0 AND 1),
    review_status     VARCHAR(20) NOT NULL DEFAULT 'unreviewed'
        CHECK (review_status IN ('unreviewed', 'confirmed', 'overridden', 'rejected'))
);
 
CREATE TABLE Alert (
    alert_id      BIGSERIAL PRIMARY KEY,
    event_id      BIGINT REFERENCES Animal_Risk_Event(event_id),
    prediction_id BIGINT REFERENCES Prediction(prediction_id),
    alert_type    VARCHAR(50) NOT NULL
        CHECK (alert_type IN ('detected', 'predicted')),
    severity      VARCHAR(10) NOT NULL
        CHECK (severity IN ('info', 'warning', 'critical')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    status        VARCHAR(20) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'acknowledged', 'resolved', 'dismissed')),
    CONSTRAINT chk_alert_source CHECK (
        (event_id IS NOT NULL AND prediction_id IS NULL) OR
        (event_id IS NULL AND prediction_id IS NOT NULL)
    ),
    CONSTRAINT chk_alert_type_matches_source CHECK (
        (alert_type = 'detected'  AND event_id IS NOT NULL) OR
        (alert_type = 'predicted' AND prediction_id IS NOT NULL)
    )
);
 
CREATE TABLE Ranger (
    ranger_id     SERIAL PRIMARY KEY,
    reserve_id    INT NOT NULL REFERENCES Reserve(reserve_id),
    name          VARCHAR(100) NOT NULL,
    contact       VARCHAR(50)
);
 
CREATE TABLE Alert_Assignment (
    assignment_id   BIGSERIAL PRIMARY KEY,
    alert_id        BIGINT NOT NULL REFERENCES Alert(alert_id),
    ranger_id       INT NOT NULL REFERENCES Ranger(ranger_id),
    assigned_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    response_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (response_status IN ('pending', 'in_progress', 'resolved', 'escalated')),
    UNIQUE (alert_id, ranger_id, assigned_at)
);
 
CREATE TABLE Device (
    device_id     SERIAL PRIMARY KEY,
    animal_id     INT REFERENCES Animal(animal_id),  -- NULL = unassigned/in storage
    model         VARCHAR(100) NOT NULL,
    battery_level NUMERIC(5,2) CHECK (battery_level BETWEEN 0 AND 100),
    install_date  DATE,
    status        VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'maintenance', 'lost'))
);
 
CREATE TABLE Habitat_Zone (
    habitat_id        SERIAL PRIMARY KEY,
    reserve_id        INT NOT NULL REFERENCES Reserve(reserve_id),
    habitat_name      VARCHAR(150) NOT NULL,
    vegetation_type   VARCHAR(30) NOT NULL
        CHECK (vegetation_type IN ('forest', 'grassland', 'wetland', 'scrubland', 'other')),
    boundary          geometry(Polygon, 4326) NOT NULL
);
 
CREATE TABLE Health_Record (
    record_id     BIGSERIAL PRIMARY KEY,
    animal_id     INT NOT NULL REFERENCES Animal(animal_id),
    checkup_date  DATE NOT NULL,
    weight_kg     NUMERIC(6,2),
    health_status VARCHAR(20) NOT NULL
        CHECK (health_status IN ('healthy', 'injured', 'sick', 'critical', 'deceased')),
    notes         TEXT
);

CREATE TABLE Audit_Log (
    audit_id    BIGSERIAL PRIMARY KEY,
    table_name  TEXT NOT NULL,
    record_id   TEXT NOT NULL,
    operation   TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_by  TEXT NOT NULL DEFAULT SESSION_USER,
    old_data    JSONB,
    new_data    JSONB
);
 
-- ---------- INDEXES ----------
 
-- Spatial indexes (critical for PostGIS performance)
CREATE INDEX idx_reserve_boundary    ON Reserve USING GIST (boundary);
CREATE INDEX idx_riskzone_boundary   ON Risk_Zone USING GIST (boundary);
CREATE INDEX idx_gps_location        ON GPS_Tracking USING GIST (location);
CREATE INDEX idx_habitat_boundary    ON Habitat_Zone USING GIST (boundary);
 
-- Query-pattern indexes
CREATE INDEX idx_gps_animal_time     ON GPS_Tracking (animal_id, timestamp);
CREATE INDEX idx_event_animal        ON Animal_Risk_Event (animal_id, detected_at);
CREATE INDEX idx_alert_status        ON Alert (status);
CREATE INDEX idx_assignment_ranger   ON Alert_Assignment (ranger_id, response_status);
CREATE INDEX idx_device_animal       ON Device (animal_id);
CREATE INDEX idx_health_animal_date  ON Health_Record (animal_id, checkup_date);
 
-- Foreign-key indexes (Postgres does not create these automatically)
CREATE INDEX idx_animal_species      ON Animal (species_id);
CREATE INDEX idx_animal_reserve      ON Animal (home_reserve_id);
CREATE INDEX idx_riskzone_reserve    ON Risk_Zone (reserve_id);
CREATE INDEX idx_event_zone          ON Animal_Risk_Event (zone_id);
CREATE INDEX idx_event_tracking      ON Animal_Risk_Event (tracking_id);
CREATE INDEX idx_prediction_animal   ON Prediction (animal_id);
CREATE INDEX idx_prediction_tracking ON Prediction (tracking_id);
CREATE INDEX idx_alert_event         ON Alert (event_id);
CREATE INDEX idx_alert_prediction    ON Alert (prediction_id);
CREATE INDEX idx_assignment_alert    ON Alert_Assignment (alert_id);
CREATE INDEX idx_ranger_reserve      ON Ranger (reserve_id);
CREATE INDEX idx_habitat_reserve     ON Habitat_Zone (reserve_id);
 
-- ---------- Species ----------
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (1, 'Bengal Tiger', 'Panthera tigris tigris', 'Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (2, 'Asian Elephant', 'Elephas maximus', 'Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (3, 'Indian Rhinoceros', 'Rhinoceros unicornis', 'Vulnerable');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (4, 'Asiatic Lion', 'Panthera leo persica', 'Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (5, 'Indian Leopard', 'Panthera pardus fusca', 'Vulnerable');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (6, 'Sloth Bear', 'Melursus ursinus', 'Vulnerable');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (7, 'Gaur', 'Bos gaurus', 'Vulnerable');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (8, 'Dhole', 'Cuon alpinus', 'Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (9, 'Lion-tailed Macaque', 'Macaca silenus', 'Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (10, 'Nilgiri Tahr', 'Nilgiritragus hylocrius', 'Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (11, 'Indian Wild Ass', 'Equus hemionus khur', 'Near Threatened');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (12, 'Swamp Deer', 'Rucervus duvaucelii', 'Vulnerable');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (13, 'Sambar', 'Rusa unicolor', 'Vulnerable');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (14, 'Chital', 'Axis axis', 'Least Concern');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (15, 'Indian Pangolin', 'Manis crassicaudata', 'Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (16, 'Great Indian Bustard', 'Ardeotis nigriceps', 'Critically Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (17, 'Gharial', 'Gavialis gangeticus', 'Critically Endangered');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (18, 'Indian Rock Python', 'Python molurus', 'Near Threatened');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (19, 'Fishing Cat', 'Prionailurus viverrinus', 'Vulnerable');
INSERT INTO Species (species_id, species_name, scientific_name, conservation_status) VALUES (20, 'Clouded Leopard', 'Neofelis nebulosa', 'Vulnerable');
 
-- ---------- Reserve ----------
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (1, 'Jim Corbett National Park', 'Uttarakhand', ST_GeomFromText('POLYGON((78.8100 29.4100, 79.0500 29.4100, 79.0500 29.6500, 78.8100 29.6500, 78.8100 29.4100))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (2, 'Ranthambore National Park', 'Rajasthan', ST_GeomFromText('POLYGON((76.3800 25.9000, 76.6200 25.9000, 76.6200 26.1400, 76.3800 26.1400, 76.3800 25.9000))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (3, 'Kaziranga National Park', 'Assam', ST_GeomFromText('POLYGON((93.2500 26.4600, 93.4900 26.4600, 93.4900 26.7000, 93.2500 26.7000, 93.2500 26.4600))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (4, 'Bandipur National Park', 'Karnataka', ST_GeomFromText('POLYGON((76.5100 11.5500, 76.7500 11.5500, 76.7500 11.7900, 76.5100 11.7900, 76.5100 11.5500))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (5, 'Periyar Tiger Reserve', 'Kerala', ST_GeomFromText('POLYGON((77.0500 9.3400, 77.2900 9.3400, 77.2900 9.5800, 77.0500 9.5800, 77.0500 9.3400))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (6, 'Sundarbans National Park', 'West Bengal', ST_GeomFromText('POLYGON((88.7800 21.8300, 89.0200 21.8300, 89.0200 22.0700, 88.7800 22.0700, 88.7800 21.8300))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (7, 'Gir National Park', 'Gujarat', ST_GeomFromText('POLYGON((70.6800 21.0100, 70.9200 21.0100, 70.9200 21.2500, 70.6800 21.2500, 70.6800 21.0100))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (8, 'Kanha Tiger Reserve', 'Madhya Pradesh', ST_GeomFromText('POLYGON((80.5000 22.2100, 80.7400 22.2100, 80.7400 22.4500, 80.5000 22.4500, 80.5000 22.2100))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (9, 'Bandhavgarh National Park', 'Madhya Pradesh', ST_GeomFromText('POLYGON((80.9100 23.6000, 81.1500 23.6000, 81.1500 23.8400, 80.9100 23.8400, 80.9100 23.6000))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (10, 'Tadoba Andhari Tiger Reserve', 'Maharashtra', ST_GeomFromText('POLYGON((79.2200 20.1300, 79.4600 20.1300, 79.4600 20.3700, 79.2200 20.3700, 79.2200 20.1300))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (11, 'Pench Tiger Reserve', 'Madhya Pradesh', ST_GeomFromText('POLYGON((79.1800 21.5800, 79.4200 21.5800, 79.4200 21.8200, 79.1800 21.8200, 79.1800 21.5800))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (12, 'Nagarhole National Park', 'Karnataka', ST_GeomFromText('POLYGON((76.0300 11.9300, 76.2700 11.9300, 76.2700 12.1700, 76.0300 12.1700, 76.0300 11.9300))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (13, 'Mudumalai Tiger Reserve', 'Tamil Nadu', ST_GeomFromText('POLYGON((76.2800 11.4300, 76.5200 11.4300, 76.5200 11.6700, 76.2800 11.6700, 76.2800 11.4300))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (14, 'Anamalai Tiger Reserve', 'Tamil Nadu', ST_GeomFromText('POLYGON((77.0800 10.2300, 77.3200 10.2300, 77.3200 10.4700, 77.0800 10.4700, 77.0800 10.2300))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (15, 'Sathyamangalam Tiger Reserve', 'Tamil Nadu', ST_GeomFromText('POLYGON((77.0800 11.3800, 77.3200 11.3800, 77.3200 11.6200, 77.0800 11.6200, 77.0800 11.3800))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (16, 'Manas National Park', 'Assam', ST_GeomFromText('POLYGON((90.8300 26.6000, 91.0700 26.6000, 91.0700 26.8400, 90.8300 26.8400, 90.8300 26.6000))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (17, 'Simlipal National Park', 'Odisha', ST_GeomFromText('POLYGON((86.2300 21.4800, 86.4700 21.4800, 86.4700 21.7200, 86.2300 21.7200, 86.2300 21.4800))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (18, 'Satpura Tiger Reserve', 'Madhya Pradesh', ST_GeomFromText('POLYGON((78.3100 22.3800, 78.5500 22.3800, 78.5500 22.6200, 78.3100 22.6200, 78.3100 22.3800))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (19, 'Dudhwa National Park', 'Uttar Pradesh', ST_GeomFromText('POLYGON((80.4800 28.3800, 80.7200 28.3800, 80.7200 28.6200, 80.4800 28.6200, 80.4800 28.3800))', 4326));
INSERT INTO Reserve (reserve_id, reserve_name, state, boundary) VALUES (20, 'Parambikulam Tiger Reserve', 'Kerala', ST_GeomFromText('POLYGON((76.6800 10.2800, 76.9200 10.2800, 76.9200 10.5200, 76.6800 10.5200, 76.6800 10.2800))', 4326));
 
-- ---------- Animal ----------
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (1, 1, 1, 'TAG-001', 'M', 2015, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (2, 2, 2, 'TAG-002', 'F', 2022, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (3, 3, 3, 'TAG-003', 'U', 2014, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (4, 4, 4, 'TAG-004', 'M', 2021, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (5, 5, 5, 'TAG-005', 'F', 2013, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (6, 6, 6, 'TAG-006', 'U', 2020, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (7, 7, 7, 'TAG-007', 'M', 2012, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (8, 8, 8, 'TAG-008', 'F', 2019, 'unknown');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (9, 9, 9, 'TAG-009', 'U', 2011, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (10, 10, 10, 'TAG-010', 'M', 2018, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (11, 11, 11, 'TAG-011', 'F', 2010, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (12, 12, 12, 'TAG-012', 'U', 2017, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (13, 13, 13, 'TAG-013', 'M', 2009, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (14, 14, 14, 'TAG-014', 'F', 2016, 'inactive');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (15, 15, 15, 'TAG-015', 'U', 2008, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (16, 16, 16, 'TAG-016', 'M', 2015, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (17, 17, 17, 'TAG-017', 'F', 2022, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (18, 18, 18, 'TAG-018', 'U', 2014, 'active');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (19, 19, 19, 'TAG-019', 'M', 2021, 'deceased');
INSERT INTO Animal (animal_id, species_id, home_reserve_id, tag_id, sex, birth_year, status) VALUES (20, 20, 20, 'TAG-020', 'F', 2013, 'active');
 
-- ---------- GPS_Tracking ----------
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (1, 1, '2026-10-01 06:03:00+05:30', ST_SetSRID(ST_MakePoint(78.9800, 29.5600), 4326), 2.20);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (2, 2, '2026-10-02 06:06:00+05:30', ST_SetSRID(ST_MakePoint(76.5100, 26.0300), 4326), 3.90);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (3, 3, '2026-10-03 06:09:00+05:30', ST_SetSRID(ST_MakePoint(93.4200, 26.6100), 4326), 5.60);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (4, 4, '2026-10-04 06:12:00+05:30', ST_SetSRID(ST_MakePoint(76.6400, 11.6800), 4326), 7.30);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (5, 5, '2026-10-05 06:15:00+05:30', ST_SetSRID(ST_MakePoint(77.2200, 9.4900), 4326), 9.00);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (6, 6, '2026-10-06 06:18:00+05:30', ST_SetSRID(ST_MakePoint(88.9100, 21.9600), 4326), 1.70);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (7, 7, '2026-10-07 06:21:00+05:30', ST_SetSRID(ST_MakePoint(70.8500, 21.1600), 4326), 3.40);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (8, 8, '2026-10-08 06:24:00+05:30', ST_SetSRID(ST_MakePoint(80.6300, 22.3400), 4326), 5.10);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (9, 9, '2026-10-09 06:27:00+05:30', ST_SetSRID(ST_MakePoint(81.0800, 23.7500), 4326), 6.80);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (10, 10, '2026-10-10 06:30:00+05:30', ST_SetSRID(ST_MakePoint(79.3500, 20.2600), 4326), 8.50);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (11, 11, '2026-10-11 06:33:00+05:30', ST_SetSRID(ST_MakePoint(79.3500, 21.7300), 4326), 1.20);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (12, 12, '2026-10-12 06:36:00+05:30', ST_SetSRID(ST_MakePoint(76.1600, 12.0600), 4326), 2.90);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (13, 13, '2026-10-13 06:39:00+05:30', ST_SetSRID(ST_MakePoint(76.4500, 11.5800), 4326), 4.60);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (14, 14, '2026-10-14 06:42:00+05:30', ST_SetSRID(ST_MakePoint(77.2100, 10.3600), 4326), 6.30);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (15, 15, '2026-10-15 06:45:00+05:30', ST_SetSRID(ST_MakePoint(77.2500, 11.5300), 4326), 8.00);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (16, 16, '2026-10-16 06:48:00+05:30', ST_SetSRID(ST_MakePoint(90.9600, 26.7300), 4326), 0.70);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (17, 17, '2026-10-17 06:51:00+05:30', ST_SetSRID(ST_MakePoint(86.4000, 21.6300), 4326), 2.40);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (18, 18, '2026-10-18 06:54:00+05:30', ST_SetSRID(ST_MakePoint(78.4400, 22.5100), 4326), 4.10);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (19, 19, '2026-10-19 06:57:00+05:30', ST_SetSRID(ST_MakePoint(80.6500, 28.5300), 4326), 5.80);
INSERT INTO GPS_Tracking (tracking_id, animal_id, timestamp, location, speed) VALUES (20, 20, '2026-10-20 07:00:00+05:30', ST_SetSRID(ST_MakePoint(76.8100, 10.4100), 4326), 7.50);
 
-- ---------- Risk_Zone ----------
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (1, 1, 'Jim Human Settlement Zone', 'human_settlement', 'medium', ST_GeomFromText('POLYGON((78.9600 29.5400, 79.0100 29.5400, 79.0100 29.5900, 78.9600 29.5900, 78.9600 29.5400))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (2, 2, 'Ranthambore Road Zone', 'road', 'high', ST_GeomFromText('POLYGON((76.5300 26.0300, 76.5800 26.0300, 76.5800 26.0800, 76.5300 26.0800, 76.5300 26.0300))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (3, 3, 'Kaziranga Poaching Zone', 'poaching_zone', 'critical', ST_GeomFromText('POLYGON((93.4000 26.5900, 93.4500 26.5900, 93.4500 26.6400, 93.4000 26.6400, 93.4000 26.5900))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (4, 4, 'Bandipur Agricultural Land Zone', 'agricultural_land', 'low', ST_GeomFromText('POLYGON((76.6600 11.6800, 76.7100 11.6800, 76.7100 11.7300, 76.6600 11.7300, 76.6600 11.6800))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (5, 5, 'Periyar Other Zone', 'other', 'medium', ST_GeomFromText('POLYGON((77.2000 9.4700, 77.2500 9.4700, 77.2500 9.5200, 77.2000 9.5200, 77.2000 9.4700))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (6, 6, 'Sundarbans Human Settlement Zone', 'human_settlement', 'high', ST_GeomFromText('POLYGON((88.9300 21.9600, 88.9800 21.9600, 88.9800 22.0100, 88.9300 22.0100, 88.9300 21.9600))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (7, 7, 'Gir Road Zone', 'road', 'critical', ST_GeomFromText('POLYGON((70.8300 21.1400, 70.8800 21.1400, 70.8800 21.1900, 70.8300 21.1900, 70.8300 21.1400))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (8, 8, 'Kanha Poaching Zone', 'poaching_zone', 'low', ST_GeomFromText('POLYGON((80.6500 22.3400, 80.7000 22.3400, 80.7000 22.3900, 80.6500 22.3900, 80.6500 22.3400))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (9, 9, 'Bandhavgarh Agricultural Land Zone', 'agricultural_land', 'medium', ST_GeomFromText('POLYGON((81.0600 23.7300, 81.1100 23.7300, 81.1100 23.7800, 81.0600 23.7800, 81.0600 23.7300))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (10, 10, 'Tadoba Other Zone', 'other', 'high', ST_GeomFromText('POLYGON((79.3700 20.2600, 79.4200 20.2600, 79.4200 20.3100, 79.3700 20.3100, 79.3700 20.2600))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (11, 11, 'Pench Human Settlement Zone', 'human_settlement', 'critical', ST_GeomFromText('POLYGON((79.3300 21.7100, 79.3800 21.7100, 79.3800 21.7600, 79.3300 21.7600, 79.3300 21.7100))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (12, 12, 'Nagarhole Road Zone', 'road', 'low', ST_GeomFromText('POLYGON((76.1800 12.0600, 76.2300 12.0600, 76.2300 12.1100, 76.1800 12.1100, 76.1800 12.0600))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (13, 13, 'Mudumalai Poaching Zone', 'poaching_zone', 'medium', ST_GeomFromText('POLYGON((76.4300 11.5600, 76.4800 11.5600, 76.4800 11.6100, 76.4300 11.6100, 76.4300 11.5600))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (14, 14, 'Anamalai Agricultural Land Zone', 'agricultural_land', 'high', ST_GeomFromText('POLYGON((77.2300 10.3600, 77.2800 10.3600, 77.2800 10.4100, 77.2300 10.4100, 77.2300 10.3600))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (15, 15, 'Sathyamangalam Other Zone', 'other', 'critical', ST_GeomFromText('POLYGON((77.2300 11.5100, 77.2800 11.5100, 77.2800 11.5600, 77.2300 11.5600, 77.2300 11.5100))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (16, 16, 'Manas Human Settlement Zone', 'human_settlement', 'low', ST_GeomFromText('POLYGON((90.9800 26.7300, 91.0300 26.7300, 91.0300 26.7800, 90.9800 26.7800, 90.9800 26.7300))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (17, 17, 'Simlipal Road Zone', 'road', 'medium', ST_GeomFromText('POLYGON((86.3800 21.6100, 86.4300 21.6100, 86.4300 21.6600, 86.3800 21.6600, 86.3800 21.6100))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (18, 18, 'Satpura Poaching Zone', 'poaching_zone', 'high', ST_GeomFromText('POLYGON((78.4600 22.5100, 78.5100 22.5100, 78.5100 22.5600, 78.4600 22.5600, 78.4600 22.5100))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (19, 19, 'Dudhwa Agricultural Land Zone', 'agricultural_land', 'critical', ST_GeomFromText('POLYGON((80.6300 28.5100, 80.6800 28.5100, 80.6800 28.5600, 80.6300 28.5600, 80.6300 28.5100))', 4326));
INSERT INTO Risk_Zone (zone_id, reserve_id, zone_name, risk_type, risk_level, boundary) VALUES (20, 20, 'Parambikulam Other Zone', 'other', 'low', ST_GeomFromText('POLYGON((76.8300 10.4100, 76.8800 10.4100, 76.8800 10.4600, 76.8300 10.4600, 76.8300 10.4100))', 4326));
 
-- ---------- Animal_Risk_Event ----------
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 1, 1, 1, 1, '2026-10-01 06:08:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'medium' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 1 AND z.zone_id = 1;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 2, 2, 2, 2, '2026-10-02 06:11:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'high' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 2 AND z.zone_id = 2;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 3, 3, 3, 3, '2026-10-03 06:14:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'critical' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 3 AND z.zone_id = 3;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 4, 4, 4, 4, '2026-10-04 06:17:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'low' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 4 AND z.zone_id = 4;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 5, 5, 5, 5, '2026-10-05 06:20:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'medium' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 5 AND z.zone_id = 5;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 6, 6, 6, 6, '2026-10-06 06:23:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'high' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 6 AND z.zone_id = 6;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 7, 7, 7, 7, '2026-10-07 06:26:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'critical' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 7 AND z.zone_id = 7;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 8, 8, 8, 8, '2026-10-08 06:29:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'low' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 8 AND z.zone_id = 8;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 9, 9, 9, 9, '2026-10-09 06:32:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'medium' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 9 AND z.zone_id = 9;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 10, 10, 10, 10, '2026-10-10 06:35:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'high' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 10 AND z.zone_id = 10;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 11, 11, 11, 11, '2026-10-11 06:38:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'critical' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 11 AND z.zone_id = 11;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 12, 12, 12, 12, '2026-10-12 06:41:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'low' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 12 AND z.zone_id = 12;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 13, 13, 13, 13, '2026-10-13 06:44:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'medium' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 13 AND z.zone_id = 13;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 14, 14, 14, 14, '2026-10-14 06:47:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'high' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 14 AND z.zone_id = 14;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 15, 15, 15, 15, '2026-10-15 06:50:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'critical' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 15 AND z.zone_id = 15;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 16, 16, 16, 16, '2026-10-16 06:53:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'low' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 16 AND z.zone_id = 16;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 17, 17, 17, 17, '2026-10-17 06:56:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'medium' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 17 AND z.zone_id = 17;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 18, 18, 18, 18, '2026-10-18 06:59:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'high' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 18 AND z.zone_id = 18;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 19, 19, 19, 19, '2026-10-19 07:02:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'critical' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 19 AND z.zone_id = 19;
INSERT INTO Animal_Risk_Event (event_id, animal_id, zone_id, tracking_id, detected_at, distance_m, risk_level) SELECT 20, 20, 20, 20, '2026-10-20 07:05:00+05:30', ROUND(ST_Distance(g.location::geography, z.boundary::geography)::numeric, 2), 'low' FROM GPS_Tracking g, Risk_Zone z WHERE g.tracking_id = 20 AND z.zone_id = 20;
 
-- ---------- Prediction ----------
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (1, 1, 1, '2026-10-01 06:13:00+05:30', 'high', 0.7120, 'unreviewed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (2, 2, 2, '2026-10-02 06:16:00+05:30', 'critical', 0.9760, 'confirmed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (3, 3, 3, '2026-10-03 06:19:00+05:30', 'low', 0.1250, 'overridden');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (4, 4, 4, '2026-10-04 06:22:00+05:30', 'medium', 0.4510, 'rejected');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (5, 5, 5, '2026-10-05 06:25:00+05:30', 'high', 0.7980, 'confirmed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (6, 6, 6, '2026-10-06 06:28:00+05:30', 'critical', 0.8610, 'unreviewed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (7, 7, 7, '2026-10-07 06:31:00+05:30', 'low', 0.2210, 'confirmed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (8, 8, 8, '2026-10-08 06:34:00+05:30', 'medium', 0.5230, 'overridden');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (9, 9, 9, '2026-10-09 06:37:00+05:30', 'high', 0.6340, 'rejected');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (10, 10, 10, '2026-10-10 06:40:00+05:30', 'critical', 0.9170, 'confirmed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (11, 11, 11, '2026-10-11 06:43:00+05:30', 'low', 0.2840, 'unreviewed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (12, 12, 12, '2026-10-12 06:46:00+05:30', 'medium', 0.3720, 'confirmed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (13, 13, 13, '2026-10-13 06:49:00+05:30', 'high', 0.7120, 'overridden');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (14, 14, 14, '2026-10-14 06:52:00+05:30', 'critical', 0.9760, 'rejected');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (15, 15, 15, '2026-10-15 06:55:00+05:30', 'low', 0.1250, 'confirmed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (16, 16, 16, '2026-10-16 06:58:00+05:30', 'medium', 0.4510, 'unreviewed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (17, 17, 17, '2026-10-17 07:01:00+05:30', 'high', 0.7980, 'confirmed');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (18, 18, 18, '2026-10-18 07:04:00+05:30', 'critical', 0.8610, 'overridden');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (19, 19, 19, '2026-10-19 07:07:00+05:30', 'low', 0.2210, 'rejected');
INSERT INTO Prediction (prediction_id, animal_id, tracking_id, predicted_at, predicted_risk, risk_probability, review_status) VALUES (20, 20, 20, '2026-10-20 07:10:00+05:30', 'medium', 0.5230, 'confirmed');
 
-- ---------- Alert ----------
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (1, 1, NULL, 'detected', 'info', '2026-10-01 06:18:00+05:30', 'open');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (2, NULL, 2, 'predicted', 'warning', '2026-10-02 06:21:00+05:30', 'acknowledged');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (3, 3, NULL, 'detected', 'critical', '2026-10-03 06:24:00+05:30', 'resolved');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (4, NULL, 4, 'predicted', 'info', '2026-10-04 06:27:00+05:30', 'dismissed');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (5, 5, NULL, 'detected', 'warning', '2026-10-05 06:30:00+05:30', 'open');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (6, NULL, 6, 'predicted', 'critical', '2026-10-06 06:33:00+05:30', 'acknowledged');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (7, 7, NULL, 'detected', 'info', '2026-10-07 06:36:00+05:30', 'resolved');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (8, NULL, 8, 'predicted', 'warning', '2026-10-08 06:39:00+05:30', 'dismissed');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (9, 9, NULL, 'detected', 'critical', '2026-10-09 06:42:00+05:30', 'open');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (10, NULL, 10, 'predicted', 'info', '2026-10-10 06:45:00+05:30', 'acknowledged');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (11, 11, NULL, 'detected', 'warning', '2026-10-11 06:48:00+05:30', 'resolved');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (12, NULL, 12, 'predicted', 'critical', '2026-10-12 06:51:00+05:30', 'dismissed');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (13, 13, NULL, 'detected', 'info', '2026-10-13 06:54:00+05:30', 'open');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (14, NULL, 14, 'predicted', 'warning', '2026-10-14 06:57:00+05:30', 'acknowledged');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (15, 15, NULL, 'detected', 'critical', '2026-10-15 07:00:00+05:30', 'resolved');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (16, NULL, 16, 'predicted', 'info', '2026-10-16 07:03:00+05:30', 'dismissed');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (17, 17, NULL, 'detected', 'warning', '2026-10-17 07:06:00+05:30', 'open');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (18, NULL, 18, 'predicted', 'critical', '2026-10-18 07:09:00+05:30', 'acknowledged');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (19, 19, NULL, 'detected', 'info', '2026-10-19 07:12:00+05:30', 'resolved');
INSERT INTO Alert (alert_id, event_id, prediction_id, alert_type, severity, created_at, status) VALUES (20, NULL, 20, 'predicted', 'warning', '2026-10-20 07:15:00+05:30', 'dismissed');
 
-- ---------- Ranger ----------
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (1, 1, 'Arjun Rawat', '+91-9819104729');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (2, 2, 'Meera Shekhawat', '+91-9838209458');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (3, 3, 'Dhruba Gogoi', '+91-9857314187');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (4, 4, 'Kiran Gowda', '+91-9876418916');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (5, 5, 'Anil Varghese', '+91-9895523645');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (6, 6, 'Subrata Mondal', '+91-9814628374');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (7, 7, 'Hiren Solanki', '+91-9833733103');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (8, 8, 'Rakesh Uikey', '+91-9852837832');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (9, 9, 'Pooja Baiga', '+91-9871942561');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (10, 10, 'Sanjay Meshram', '+91-9890047290');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (11, 11, 'Lalita Dhurve', '+91-9809152019');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (12, 12, 'Basavaraj Naik', '+91-9828256748');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (13, 13, 'Murugan Selvam', '+91-9847361477');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (14, 14, 'Karthik Rajan', '+91-9866466206');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (15, 15, 'Velmurugan S', '+91-9885570935');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (16, 16, 'Bhaben Basumatary', '+91-9804675664');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (17, 17, 'Sudhir Majhi', '+91-9823780393');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (18, 18, 'Rekha Patel', '+91-9842885122');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (19, 19, 'Imran Siddiqui', '+91-9861989851');
INSERT INTO Ranger (ranger_id, reserve_id, name, contact) VALUES (20, 20, 'Thomas Joseph', '+91-9880094580');
 
-- ---------- Alert_Assignment ----------
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (1, 1, 1, '2026-10-01 06:23:00+05:30', 'pending');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (2, 2, 2, '2026-10-02 06:26:00+05:30', 'in_progress');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (3, 3, 3, '2026-10-03 06:29:00+05:30', 'resolved');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (4, 4, 4, '2026-10-04 06:32:00+05:30', 'escalated');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (5, 5, 5, '2026-10-05 06:35:00+05:30', 'pending');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (6, 6, 6, '2026-10-06 06:38:00+05:30', 'in_progress');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (7, 7, 7, '2026-10-07 06:41:00+05:30', 'resolved');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (8, 8, 8, '2026-10-08 06:44:00+05:30', 'escalated');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (9, 9, 9, '2026-10-09 06:47:00+05:30', 'pending');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (10, 10, 10, '2026-10-10 06:50:00+05:30', 'in_progress');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (11, 11, 11, '2026-10-11 06:53:00+05:30', 'resolved');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (12, 12, 12, '2026-10-12 06:56:00+05:30', 'escalated');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (13, 13, 13, '2026-10-13 06:59:00+05:30', 'pending');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (14, 14, 14, '2026-10-14 07:02:00+05:30', 'in_progress');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (15, 15, 15, '2026-10-15 07:05:00+05:30', 'resolved');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (16, 16, 16, '2026-10-16 07:08:00+05:30', 'escalated');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (17, 17, 17, '2026-10-17 07:11:00+05:30', 'pending');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (18, 18, 18, '2026-10-18 07:14:00+05:30', 'in_progress');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (19, 19, 19, '2026-10-19 07:17:00+05:30', 'resolved');
INSERT INTO Alert_Assignment (assignment_id, alert_id, ranger_id, assigned_at, response_status) VALUES (20, 20, 20, '2026-10-20 07:20:00+05:30', 'escalated');
 
-- ---------- Device ----------
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (1, 1, 'WildTrack GT-200', 49.00, '2024-02-07', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (2, 2, 'WildTrack GT-300', 86.00, '2024-03-01', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (3, 3, 'SatCollar X1', 35.00, '2024-03-24', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (4, 4, 'SatCollar X2', 72.00, '2024-04-16', 'maintenance');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (5, 5, 'TrailSense LR-5', 21.00, '2024-05-09', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (6, 6, 'WildTrack GT-200', 58.00, '2024-06-01', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (7, 7, 'WildTrack GT-300', 95.00, '2024-06-24', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (8, 8, 'SatCollar X1', 44.00, '2024-07-17', 'maintenance');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (9, 9, 'SatCollar X2', 81.00, '2024-08-09', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (10, 10, 'TrailSense LR-5', 30.00, '2024-09-01', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (11, 11, 'WildTrack GT-200', 67.00, '2024-09-24', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (12, 12, 'WildTrack GT-300', 16.00, '2024-10-17', 'maintenance');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (13, 13, 'SatCollar X1', 53.00, '2024-11-09', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (14, 14, 'SatCollar X2', 90.00, '2024-12-02', 'lost');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (15, 15, 'TrailSense LR-5', 39.00, '2024-12-25', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (16, 16, 'WildTrack GT-200', 76.00, '2025-01-17', 'maintenance');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (17, 17, 'WildTrack GT-300', 25.00, '2025-02-09', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (18, 18, 'SatCollar X1', 62.00, '2025-03-04', 'active');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (19, 19, 'SatCollar X2', 99.00, '2025-03-27', 'inactive');
INSERT INTO Device (device_id, animal_id, model, battery_level, install_date, status) VALUES (20, NULL, 'TrailSense LR-5', 48.00, '2025-04-19', 'inactive');
 
-- ---------- Habitat_Zone ----------
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (1, 1, 'Jim Sal Forest', 'forest', ST_GeomFromText('POLYGON((78.8300 29.4500, 78.9800 29.4500, 78.9800 29.6100, 78.8300 29.6100, 78.8300 29.4500))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (2, 2, 'Ranthambore Dry Deciduous Forest', 'forest', ST_GeomFromText('POLYGON((76.4000 25.9400, 76.5500 25.9400, 76.5500 26.1000, 76.4000 26.1000, 76.4000 25.9400))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (3, 3, 'Kaziranga Floodplain Grassland', 'grassland', ST_GeomFromText('POLYGON((93.2700 26.5000, 93.4200 26.5000, 93.4200 26.6600, 93.2700 26.6600, 93.2700 26.5000))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (4, 4, 'Bandipur Teak Forest', 'forest', ST_GeomFromText('POLYGON((76.5300 11.5900, 76.6800 11.5900, 76.6800 11.7500, 76.5300 11.7500, 76.5300 11.5900))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (5, 5, 'Periyar Shola Grassland', 'grassland', ST_GeomFromText('POLYGON((77.0700 9.3800, 77.2200 9.3800, 77.2200 9.5400, 77.0700 9.5400, 77.0700 9.3800))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (6, 6, 'Sundarbans Mangrove Wetland', 'wetland', ST_GeomFromText('POLYGON((88.8000 21.8700, 88.9500 21.8700, 88.9500 22.0300, 88.8000 22.0300, 88.8000 21.8700))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (7, 7, 'Gir Scrub Thicket', 'scrubland', ST_GeomFromText('POLYGON((70.7000 21.0500, 70.8500 21.0500, 70.8500 21.2100, 70.7000 21.2100, 70.7000 21.0500))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (8, 8, 'Kanha Sal-Bamboo Forest', 'forest', ST_GeomFromText('POLYGON((80.5200 22.2500, 80.6700 22.2500, 80.6700 22.4100, 80.5200 22.4100, 80.5200 22.2500))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (9, 9, 'Bandhavgarh Meadow Grassland', 'grassland', ST_GeomFromText('POLYGON((80.9300 23.6400, 81.0800 23.6400, 81.0800 23.8000, 80.9300 23.8000, 80.9300 23.6400))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (10, 10, 'Tadoba Mixed Forest', 'forest', ST_GeomFromText('POLYGON((79.2400 20.1700, 79.3900 20.1700, 79.3900 20.3300, 79.2400 20.3300, 79.2400 20.1700))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (11, 11, 'Pench Teak-Bamboo Forest', 'forest', ST_GeomFromText('POLYGON((79.2000 21.6200, 79.3500 21.6200, 79.3500 21.7800, 79.2000 21.7800, 79.2000 21.6200))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (12, 12, 'Nagarhole Riverine Forest', 'forest', ST_GeomFromText('POLYGON((76.0500 11.9700, 76.2000 11.9700, 76.2000 12.1300, 76.0500 12.1300, 76.0500 11.9700))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (13, 13, 'Mudumalai Thorn Scrub', 'scrubland', ST_GeomFromText('POLYGON((76.3000 11.4700, 76.4500 11.4700, 76.4500 11.6300, 76.3000 11.6300, 76.3000 11.4700))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (14, 14, 'Anamalai Evergreen Forest', 'forest', ST_GeomFromText('POLYGON((77.1000 10.2700, 77.2500 10.2700, 77.2500 10.4300, 77.1000 10.4300, 77.1000 10.2700))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (15, 15, 'Sathyamangalam Foothill Scrub', 'scrubland', ST_GeomFromText('POLYGON((77.1000 11.4200, 77.2500 11.4200, 77.2500 11.5800, 77.1000 11.5800, 77.1000 11.4200))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (16, 16, 'Manas Terai Grassland', 'grassland', ST_GeomFromText('POLYGON((90.8500 26.6400, 91.0000 26.6400, 91.0000 26.8000, 90.8500 26.8000, 90.8500 26.6400))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (17, 17, 'Simlipal Hill Forest', 'forest', ST_GeomFromText('POLYGON((86.2500 21.5200, 86.4000 21.5200, 86.4000 21.6800, 86.2500 21.6800, 86.2500 21.5200))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (18, 18, 'Satpura Riverine Wetland', 'wetland', ST_GeomFromText('POLYGON((78.3300 22.4200, 78.4800 22.4200, 78.4800 22.5800, 78.3300 22.5800, 78.3300 22.4200))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (19, 19, 'Dudhwa Swamp Marsh', 'wetland', ST_GeomFromText('POLYGON((80.5000 28.4200, 80.6500 28.4200, 80.6500 28.5800, 80.5000 28.5800, 80.5000 28.4200))', 4326));
INSERT INTO Habitat_Zone (habitat_id, reserve_id, habitat_name, vegetation_type, boundary) VALUES (20, 20, 'Parambikulam Rainforest', 'forest', ST_GeomFromText('POLYGON((76.7000 10.3200, 76.8500 10.3200, 76.8500 10.4800, 76.7000 10.4800, 76.7000 10.3200))', 4326));
 
-- ---------- Health_Record ----------
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (1, 1, '2026-09-02', 182.40, 'healthy', 'Routine annual checkup; no concerns.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (2, 2, '2026-09-03', 3600.00, 'healthy', 'Good body condition; coat healthy.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (3, 3, '2026-09-04', 2184.00, 'injured', 'Minor laceration on left foreleg; treated and monitored.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (4, 4, '2026-09-05', 189.00, 'healthy', 'Normal weight and behaviour.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (5, 5, '2026-09-06', 53.36, 'sick', 'Mild parasite load; dewormed.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (6, 6, '2026-09-07', 100.80, 'healthy', 'Healthy; slight dental wear.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (7, 7, '2026-09-08', 850.00, 'healthy', 'Normal checkup.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (8, 8, '2026-09-09', 16.64, 'critical', 'Severe dehydration; under observation.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (9, 9, '2026-09-10', 9.18, 'healthy', 'Healthy; collar fit adjusted.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (10, 10, '2026-09-11', 78.20, 'healthy', 'Normal checkup.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (11, 11, '2026-09-12', 211.20, 'healthy', 'Routine annual checkup; no concerns.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (12, 12, '2026-09-13', 180.00, 'healthy', 'Good body condition; coat healthy.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (13, 13, '2026-09-14', 249.60, 'injured', 'Minor laceration on left foreleg; treated and monitored.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (14, 14, '2026-09-15', 64.80, 'healthy', 'Normal weight and behaviour.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (15, 15, '2026-09-16', 11.04, 'sick', 'Mild parasite load; dewormed.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (16, 16, '2026-09-17', 13.44, 'healthy', 'Healthy; slight dental wear.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (17, 17, '2026-09-18', 160.00, 'healthy', 'Normal checkup.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (18, 18, '2026-09-19', 46.80, 'critical', 'Severe dehydration; under observation.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (19, 19, '2026-09-20', 11.88, 'deceased', 'Found dead; suspected snare injury.');
INSERT INTO Health_Record (record_id, animal_id, checkup_date, weight_kg, health_status, notes) VALUES (20, 20, '2026-09-21', 18.40, 'healthy', 'Normal checkup.');
 
-- ---------- Reset sequences (rows above were inserted with explicit IDs) ----------
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

-- ---------- AUDIT LOG ----------
-- Install row-level audit triggers after loading the sample data so initial
-- seed records do not appear as operational changes in the audit history.
CREATE OR REPLACE FUNCTION audit_row_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    old_row JSONB;
    new_row JSONB;
    row_id TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        new_row := to_jsonb(NEW);
        row_id := new_row ->> TG_ARGV[0];
    ELSIF TG_OP = 'UPDATE' THEN
        old_row := to_jsonb(OLD);
        new_row := to_jsonb(NEW);
        row_id := new_row ->> TG_ARGV[0];
    ELSE
        old_row := to_jsonb(OLD);
        row_id := old_row ->> TG_ARGV[0];
    END IF;

    INSERT INTO Audit_Log (table_name, record_id, operation, changed_by, old_data, new_data)
    VALUES (TG_TABLE_NAME, row_id, TG_OP, SESSION_USER, old_row, new_row);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER audit_species_changes
AFTER INSERT OR UPDATE OR DELETE ON Species
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('species_id');
CREATE TRIGGER audit_reserve_changes
AFTER INSERT OR UPDATE OR DELETE ON Reserve
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('reserve_id');
CREATE TRIGGER audit_animal_changes
AFTER INSERT OR UPDATE OR DELETE ON Animal
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('animal_id');
CREATE TRIGGER audit_gps_tracking_changes
AFTER INSERT OR UPDATE OR DELETE ON GPS_Tracking
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('tracking_id');
CREATE TRIGGER audit_risk_zone_changes
AFTER INSERT OR UPDATE OR DELETE ON Risk_Zone
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('zone_id');
CREATE TRIGGER audit_risk_event_changes
AFTER INSERT OR UPDATE OR DELETE ON Animal_Risk_Event
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('event_id');
CREATE TRIGGER audit_prediction_changes
AFTER INSERT OR UPDATE OR DELETE ON Prediction
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('prediction_id');
CREATE TRIGGER audit_alert_changes
AFTER INSERT OR UPDATE OR DELETE ON Alert
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('alert_id');
CREATE TRIGGER audit_ranger_changes
AFTER INSERT OR UPDATE OR DELETE ON Ranger
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('ranger_id');
CREATE TRIGGER audit_assignment_changes
AFTER INSERT OR UPDATE OR DELETE ON Alert_Assignment
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('assignment_id');
CREATE TRIGGER audit_device_changes
AFTER INSERT OR UPDATE OR DELETE ON Device
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('device_id');
CREATE TRIGGER audit_habitat_changes
AFTER INSERT OR UPDATE OR DELETE ON Habitat_Zone
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('habitat_id');
CREATE TRIGGER audit_health_record_changes
AFTER INSERT OR UPDATE OR DELETE ON Health_Record
FOR EACH ROW EXECUTE FUNCTION audit_row_changes('record_id');

CREATE INDEX idx_audit_log_table_record_time
    ON Audit_Log (table_name, record_id, changed_at DESC);

-- 1. BASIC SELECT
SELECT * FROM Species;
SELECT * FROM Animal;
SELECT * FROM Health_Record;
SELECT * FROM Audit_Log ORDER BY changed_at DESC;
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
