"""
Feature engineering for WildGuard.

The model predicts risk_level from the latest GPS/location context.
The database schema already contains the useful sources:
GPS_Tracking, Animal, Species, Risk_Zone, Animal_Risk_Event,
Health_Record, Device and Reserve.
"""

import math

RISK_RANK = {
    "low": 1,
    "medium": 2,
    "high": 3,
    "critical": 4,
}

RISK_TYPES = [
    "human_settlement",
    "road",
    "poaching_zone",
    "agricultural_land",
    "other",
]

FEATURE_COLUMNS = [
    "speed",
    "distance_to_nearest_zone_m",
    "nearest_zone_risk_rank",
    "distance_to_human_settlement_m",
    "distance_to_road_m",
    "distance_to_poaching_zone_m",
    "distance_to_agricultural_land_m",
    "distance_to_other_zone_m",
    "endangered",
    "recent_event_count",
    "battery_level",
    "health_risk",
    "outside_reserve",
    "hour",
]


def _safe(value, default=0.0):
    return default if value is None else float(value)


def _health_risk(status):
    return {
        "healthy": 0,
        "injured": 1,
        "sick": 2,
        "critical": 3,
        "deceased": 4,
    }.get(status, 0)


def build_feature_row(row):
    return [
        _safe(row.get("speed")),
        _safe(row.get("distance_to_nearest_zone_m"), 999999.0),
        _safe(row.get("nearest_zone_risk_rank")),
        _safe(row.get("distance_to_human_settlement_m"), 999999.0),
        _safe(row.get("distance_to_road_m"), 999999.0),
        _safe(row.get("distance_to_poaching_zone_m"), 999999.0),
        _safe(row.get("distance_to_agricultural_land_m"), 999999.0),
        _safe(row.get("distance_to_other_zone_m"), 999999.0),
        1 if str(row.get("conservation_status", "")).lower() == "endangered" else 0,
        _safe(row.get("recent_event_count")),
        _safe(row.get("battery_level"), 100.0),
        _health_risk(row.get("health_status")),
        int(row.get("outside_reserve", 0) or 0),
        _safe(row.get("hour")),
    ]


def sql_training_data():
    return """
    WITH gps AS (
        SELECT
            g.tracking_id,
            g.animal_id,
            g."timestamp",
            COALESCE(g.speed, 0) AS speed,
            g.location
        FROM GPS_Tracking g
    ),
    zone_dist AS (
        SELECT
            g.tracking_id,
            rz.risk_type,
            rz.risk_level,
            ST_Distance(
                g.location::geography,
                rz.boundary::geography
            ) AS distance_m
        FROM gps g
        CROSS JOIN Risk_Zone rz
    ),
    nearest AS (
        SELECT DISTINCT ON (tracking_id, risk_type)
            tracking_id,
            risk_type,
            risk_level,
            distance_m
        FROM zone_dist
        ORDER BY tracking_id, risk_type, distance_m
    ),
    all_nearest AS (
        SELECT
            tracking_id,
            MIN(distance_m) AS distance_to_nearest_zone_m,
            MAX(
                CASE risk_type
                    WHEN 'human_settlement' THEN distance_m
                    ELSE NULL
                END
            ) AS dummy
        FROM zone_dist
        GROUP BY tracking_id
    ),
    event_label AS (
        SELECT DISTINCT ON (tracking_id)
            tracking_id,
            risk_level AS target_risk
        FROM Animal_Risk_Event
        ORDER BY tracking_id, detected_at DESC
    ),
    recent_events AS (
        SELECT
            g.tracking_id,
            COUNT(e.event_id) AS recent_event_count
        FROM gps g
        LEFT JOIN Animal_Risk_Event e
            ON e.animal_id = g.animal_id
           AND e.detected_at BETWEEN g."timestamp" - interval '24 hours'
                                AND g."timestamp"
        GROUP BY g.tracking_id
    ),
    health AS (
        SELECT DISTINCT ON (animal_id)
            animal_id,
            health_status
        FROM Health_Record
        ORDER BY animal_id, checkup_date DESC
    ),
    device AS (
        SELECT DISTINCT ON (animal_id)
            animal_id,
            battery_level
        FROM Device
        WHERE animal_id IS NOT NULL
        ORDER BY animal_id, device_id DESC
    ),
    zone_features AS (
        SELECT
            tracking_id,
            MIN(distance_m) AS distance_to_nearest_zone_m,
            MIN(distance_m) FILTER (
                WHERE risk_type = 'human_settlement'
            ) AS distance_to_human_settlement_m,
            MIN(distance_m) FILTER (
                WHERE risk_type = 'road'
            ) AS distance_to_road_m,
            MIN(distance_m) FILTER (
                WHERE risk_type = 'poaching_zone'
            ) AS distance_to_poaching_zone_m,
            MIN(distance_m) FILTER (
                WHERE risk_type = 'agricultural_land'
            ) AS distance_to_agricultural_land_m,
            MIN(distance_m) FILTER (
                WHERE risk_type = 'other'
            ) AS distance_to_other_zone_m,
            MAX(
                CASE
                    WHEN distance_m = (
                        SELECT MIN(z2.distance_m)
                        FROM zone_dist z2
                        WHERE z2.tracking_id = zone_dist.tracking_id
                    )
                    THEN CASE risk_level
                        WHEN 'critical' THEN 4
                        WHEN 'high' THEN 3
                        WHEN 'medium' THEN 2
                        ELSE 1
                    END
                    ELSE 0
                END
            ) AS nearest_zone_risk_rank
        FROM zone_dist
        GROUP BY tracking_id
    )
    SELECT
        g.tracking_id,
        g.animal_id,
        g.speed,
        COALESCE(zf.distance_to_nearest_zone_m, 999999) AS distance_to_nearest_zone_m,
        COALESCE(zf.nearest_zone_risk_rank, 0) AS nearest_zone_risk_rank,
        COALESCE(zf.distance_to_human_settlement_m, 999999) AS distance_to_human_settlement_m,
        COALESCE(zf.distance_to_road_m, 999999) AS distance_to_road_m,
        COALESCE(zf.distance_to_poaching_zone_m, 999999) AS distance_to_poaching_zone_m,
        COALESCE(zf.distance_to_agricultural_land_m, 999999) AS distance_to_agricultural_land_m,
        COALESCE(zf.distance_to_other_zone_m, 999999) AS distance_to_other_zone_m,
        s.conservation_status,
        COALESCE(recent.recent_event_count, 0) AS recent_event_count,
        COALESCE(d.battery_level, 100) AS battery_level,
        COALESCE(h.health_status, 'healthy') AS health_status,
        CASE
            WHEN a.home_reserve_id IS NULL THEN 0
            WHEN NOT ST_Within(
                g.location,
                (SELECT r.boundary
                 FROM Reserve r
                 WHERE r.reserve_id = a.home_reserve_id)
            ) THEN 1
            ELSE 0
        END AS outside_reserve,
        EXTRACT(HOUR FROM g."timestamp") AS hour,
        el.target_risk
    FROM gps g
    JOIN Animal a ON a.animal_id = g.animal_id
    JOIN Species s ON s.species_id = a.species_id
    LEFT JOIN zone_features zf ON zf.tracking_id = g.tracking_id
    LEFT JOIN recent_events recent ON recent.tracking_id = g.tracking_id
    LEFT JOIN health h ON h.animal_id = g.animal_id
    LEFT JOIN device d ON d.animal_id = g.animal_id
    JOIN event_label el ON el.tracking_id = g.tracking_id
    ORDER BY g.tracking_id;
    """


def sql_prediction_inputs(animal_id=None):
    condition = "WHERE g.animal_id = %s" if animal_id is not None else ""
    return f"""
    WITH latest AS (
        SELECT DISTINCT ON (g.animal_id)
            g.tracking_id,
            g.animal_id,
            g."timestamp",
            COALESCE(g.speed, 0) AS speed,
            g.location
        FROM GPS_Tracking g
        {condition}
        ORDER BY g.animal_id, g."timestamp" DESC
    ),
    zone_dist AS (
        SELECT
            l.tracking_id,
            rz.risk_type,
            rz.risk_level,
            ST_Distance(
                l.location::geography,
                rz.boundary::geography
            ) AS distance_m
        FROM latest l
        CROSS JOIN Risk_Zone rz
    ),
    zone_features AS (
        SELECT
            tracking_id,
            MIN(distance_m) AS distance_to_nearest_zone_m,
            MIN(distance_m) FILTER (WHERE risk_type='human_settlement')
                AS distance_to_human_settlement_m,
            MIN(distance_m) FILTER (WHERE risk_type='road')
                AS distance_to_road_m,
            MIN(distance_m) FILTER (WHERE risk_type='poaching_zone')
                AS distance_to_poaching_zone_m,
            MIN(distance_m) FILTER (WHERE risk_type='agricultural_land')
                AS distance_to_agricultural_land_m,
            MIN(distance_m) FILTER (WHERE risk_type='other')
                AS distance_to_other_zone_m,
            MAX(
                CASE
                    WHEN distance_m = (
                        SELECT MIN(z2.distance_m)
                        FROM zone_dist z2
                        WHERE z2.tracking_id = zone_dist.tracking_id
                    )
                    THEN CASE risk_level
                        WHEN 'critical' THEN 4
                        WHEN 'high' THEN 3
                        WHEN 'medium' THEN 2
                        ELSE 1
                    END
                    ELSE 0
                END
            ) AS nearest_zone_risk_rank
        FROM zone_dist
        GROUP BY tracking_id
    ),
    recent_events AS (
        SELECT
            l.tracking_id,
            COUNT(e.event_id) AS recent_event_count
        FROM latest l
        LEFT JOIN Animal_Risk_Event e
            ON e.animal_id = l.animal_id
           AND e.detected_at BETWEEN l."timestamp" - interval '24 hours'
                                AND l."timestamp"
        GROUP BY l.tracking_id
    ),
    health AS (
        SELECT DISTINCT ON (animal_id)
            animal_id,
            health_status
        FROM Health_Record
        ORDER BY animal_id, checkup_date DESC
    ),
    device AS (
        SELECT DISTINCT ON (animal_id)
            animal_id,
            battery_level
        FROM Device
        WHERE animal_id IS NOT NULL
        ORDER BY animal_id, device_id DESC
    )
    SELECT
        l.tracking_id,
        l.animal_id,
        l.speed,
        COALESCE(zf.distance_to_nearest_zone_m, 999999) AS distance_to_nearest_zone_m,
        COALESCE(zf.nearest_zone_risk_rank, 0) AS nearest_zone_risk_rank,
        COALESCE(zf.distance_to_human_settlement_m, 999999) AS distance_to_human_settlement_m,
        COALESCE(zf.distance_to_road_m, 999999) AS distance_to_road_m,
        COALESCE(zf.distance_to_poaching_zone_m, 999999) AS distance_to_poaching_zone_m,
        COALESCE(zf.distance_to_agricultural_land_m, 999999) AS distance_to_agricultural_land_m,
        COALESCE(zf.distance_to_other_zone_m, 999999) AS distance_to_other_zone_m,
        s.conservation_status,
        COALESCE(recent.recent_event_count, 0) AS recent_event_count,
        COALESCE(d.battery_level, 100) AS battery_level,
        COALESCE(h.health_status, 'healthy') AS health_status,
        CASE
            WHEN a.home_reserve_id IS NULL THEN 0
            WHEN NOT ST_Within(
                l.location,
                (SELECT r.boundary
                 FROM Reserve r
                 WHERE r.reserve_id = a.home_reserve_id)
            ) THEN 1
            ELSE 0
        END AS outside_reserve,
        EXTRACT(HOUR FROM l."timestamp") AS hour
    FROM latest l
    JOIN Animal a ON a.animal_id = l.animal_id
    JOIN Species s ON s.species_id = a.species_id
    LEFT JOIN zone_features zf ON zf.tracking_id = l.tracking_id
    LEFT JOIN recent_events recent ON recent.tracking_id = l.tracking_id
    LEFT JOIN health h ON h.animal_id = l.animal_id
    LEFT JOIN device d ON d.animal_id = l.animal_id
    ORDER BY l.animal_id;
    """
