# WildGuard - AI Wildlife Conservation Dashboard

## Project abstract

Wildlife teams often need to combine animal location, health, habitat, equipment, and incident information to identify threats and coordinate a response. WildGuard is a wildlife-monitoring dashboard prototype that brings these tasks together. Its interface presents animal and collar status, a schematic reserve tracking view, alerts, ranger operations, risk zones, and a prediction review queue. A PostgreSQL/PostGIS schema stores wildlife and geospatial records, while a separate Python service can train a Random Forest classifier to estimate risk from GPS, nearby zones, recent incidents, health, and collar data. The prototype supports a demo mode and an optional database-backed API. Its sample data and model are for demonstration, not field deployment or conservation decision-making.

## Team

Divya Keerthana S 25BCE5741
Kavya Sri K 25BCE5346
Mridula Arun Kumar 25BCE5804


## Functional features

- Overview of monitored animals, current alerts, risk levels, and reserve activity.
- Schematic live-tracking visualization with selectable animal profiles.
- Animal list and detail view with species, location, health, and collar information.
- Alert centre with severity/status presentation and alert review actions.
- Ranger workload, reserve and risk-zone summaries, AI prediction review queue, and collar health.
- Responsive dashboard layout and seeded demo data when the database API is unavailable.
- Optional FastAPI service for Random Forest risk predictions saved to PostgreSQL.

The map is a dashboard schematic, not a live geographic basemap. The standalone prediction API is not automatically invoked by the frontend.

## Technology stack

| Layer | Technologies |
|---|---|
| Frontend | React 18, JavaScript, Vite, Recharts, Lucide |
| Dashboard API | Node.js, Express, `pg` (node-postgres) |
| Prediction API | Python, FastAPI, scikit-learn Random Forest, joblib, psycopg2 |
| Database | PostgreSQL with PostGIS spatial types/functions |

## Requirements

- Node.js 18 or later and npm.
- PostgreSQL with the PostGIS extension available.
- Python 3 and pip to run or train the optional prediction service.
- `psql` on your PATH to create and load the sample database.

## Run the dashboard

From the project root:

```powershell
npm install
npm run dev
```

Open <http://localhost:5173>. `npm run dev` starts the Vite frontend and Express API. Without a configured database, the dashboard uses demo data.

### Configure the database

The SQL scripts below contain destructive schema-reset commands (`DROP SCHEMA public CASCADE`; the database-folder script also drops PostGIS). **Use a new, disposable database only. Do not run these scripts against a database containing data you need to keep.** Use only one script, not both.

From the project root, create a fresh database and load the final schema and its sample data:

```powershell
psql -U postgres -c "CREATE DATABASE wildguard_demo;"
psql -U postgres -d wildguard_demo -f ".\database\final wildlife_tracking (2).sql"
```

If PostGIS is not installed or enabled for your PostgreSQL server, install/enable it before loading the script. The script creates the tables and seeds example records.

Configure the Express API by copying the example environment file and editing `.env` in the project root:

```powershell
Copy-Item env.example .env
```

Set `DATABASE_URL` to your own PostgreSQL connection string for `wildguard_demo`. Keep `.env` private and do not commit credentials. For a local database, set `PG_SSL=false`; set it to `true` only when your database provider requires TLS.

Restart `npm run dev`. The header reports database mode when the API health check succeeds. The frontend currently loads database-backed animal rows only; other dashboard sections and actions still use local demo state.

### Optional: run the Random Forest prediction API

The Python API is separate from `npm run dev`. From the project root:

```powershell
Set-Location .\server
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Create `server\.env` with your own database settings:

```dotenv
DB_HOST=localhost
DB_PORT=5432
DB_NAME=wildguard_demo
DB_USER=postgres
DB_PASSWORD=YOUR_POSTGRES_PASSWORD
```

Then train and start the service:

```powershell
python train_model.py
uvicorn app:app --reload --port 8000
```

The training step requires at least 8 labeled records. The API health check is at <http://localhost:8000/health>, interactive API documentation at <http://localhost:8000/docs>, and prediction endpoints include `POST /predict`, `POST /predict/{animal_id}`, and `GET /predictions`.

## Database tables and relationships

The final SQL script creates **13 tables** and seeds 20 sample rows in each table:

| Table | Purpose |
|---|---|
| `Species` | Species names and conservation status |
| `Reserve` | Protected areas and PostGIS reserve boundaries |
| `Animal` | Tagged animals and their species/reserve |
| `GPS_Tracking` | Timestamped animal locations and speed |
| `Risk_Zone` | Reserve risk categories and spatial boundaries |
| `Animal_Risk_Event` | Risk-zone events linked to an animal and GPS record |
| `Prediction` | Predicted risk, probability, and review status |
| `Alert` | Detected or predicted alerts and their status |
| `Ranger` | Ranger information and assigned reserve |
| `Alert_Assignment` | Ranger-to-alert assignments and response status |
| `Device` | Animal collar/device model, battery, and status |
| `Habitat_Zone` | Reserve habitats, vegetation type, and boundaries |
| `Health_Record` | Animal checkups, weight, and health status |

Key relationships: `Animal` references `Species` and `Reserve`; GPS, health, and device records reference animals; risk events reference animals, GPS records, and risk zones; predictions reference animals and optionally GPS records; alerts reference exactly one risk event or prediction; and alert assignments connect alerts to rangers. Reserves also own risk zones, habitat zones, and rangers.

The seeded dataset includes Indian wildlife species, reserve examples, GPS records, risk zones/events, predictions, alerts, ranger assignments, device readings, habitats, and health records. These records are examples, not current field telemetry.

## Screenshots / implemented-feature summary


## Test instructions

1. Run `npm run build` from the project root; the Vite production build should complete.
2. Run `npm run dev` and open <http://localhost:5173>.
3. Check that the dashboard opens in demo mode and navigate through its pages.
4. With a configured database, check `http://localhost:4000/api/health` and `http://localhost:5173`; confirm the header state and animal list.
5. For the optional Python service, check `/health`, then use `/docs` to call prediction endpoints. Training needs at least 8 labeled database records.

## Known limitations

- The data and UI are a prototype; the sample records and small training dataset are not a scientifically validated wildlife-risk model.
- The tracking visualization is schematic and does not render a geographic basemap.
- The frontend polls the Express health endpoint and loads animals, but its alert/prediction/ranger/device content and review interactions are primarily local demo state. The Python prediction API is not wired into the frontend.
- The supplied SQL script does not create the `v_ranger_workload`, `v_open_alerts`, `v_prediction_review_queue`, `v_reserve_risk_summary`, or `v_device_health` views referenced by some Express API routes. Those views must be created or the API queries changed before those live-data routes can work.
- Demo-mode actions do not persist to PostgreSQL. Do not treat dashboard/model output as field advice.

## YouTube demonstration

