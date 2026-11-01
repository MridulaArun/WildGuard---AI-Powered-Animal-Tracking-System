# WildGuard — AI Wildlife Conservation Dashboard

A polished React + Express dashboard for your Wildlife Tracking SQL schema. It includes an interactive demo mode immediately, plus an optional Express API that reads your PostgreSQL/PostGIS views and tables.

## Run it

Requires Node.js 18+.

```bash
npm install
npm run dev
```

Open **http://localhost:5173**. The frontend starts in **Demo mode** if the API/database is not connected, so you can explore the interface without risking your existing database.

## Connect your existing PostgreSQL/PostGIS database

1. Copy `.env.example` to `.env`.
2. Put your database connection string in `DATABASE_URL`. Keep `.env` private; never commit it.
3. Ensure the SQL script has been run successfully in the target database, including its views and procedures.
4. Restart `npm run dev`. The header will show **Live database** when `/api/health` confirms the database connection.

The API reads your schema's views including `v_open_alerts`, `v_animal_latest_position`, `v_reserve_risk_summary`, `v_ranger_workload`, `v_species_dashboard`, `v_device_health`, `v_animal_health_latest`, `v_high_risk_animals`, `v_prediction_review_queue`, and `v_zone_hotspots`.

## Features

- Overview: KPI cards, risk trend chart, high-priority queue, reserve pulse
- Live tracking: reserve-focused schematic map with animal positions and risk zones
- Animals: search, status filters, latest location, device and health summary
- Alerts: detected/predicted risk, severity and status filters, acknowledge/resolve/dismiss actions
- Ranger operations: assignments and response workload
- Reserves & risk zones, devices/collar battery, AI prediction review queue
- Responsive layout and demo interactions when no DB is configured

## Important implementation notes

- Your SQL file defines PostgreSQL/PostGIS tables and views, not an HTTP API. This project includes a small Express API adapter for the dashboard.
- The demo data is illustrative and based on entities/columns in the SQL schema. In Demo mode, actions change local UI state only; they do **not** write to PostgreSQL.
- In Live database mode, alert actions update `Alert.status` and assignment response statuses. Confirm these changes suit your team's database workflow before deployment.
- The tracking map is a schematic dashboard visualization, not a geographic basemap. For production, replace it with a Leaflet/MapLibre map and render GeoJSON from PostGIS.
- The provided SQL seeds historical sample records; “live” location status depends on the timestamps and collar cadence in your own deployment.
