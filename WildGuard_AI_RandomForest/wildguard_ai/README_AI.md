# WildGuard AI — Random Forest Risk Prediction

This adds a real Python machine-learning layer to the existing WildGuard PostgreSQL/PostGIS database.

## What the AI predicts

The AI predicts:

- `predicted_risk`: low / medium / high / critical
- `risk_probability`: 0 to 1

These database fields are NOT AI targets:

- `prediction_id` — PostgreSQL generates it.
- `animal_id` — comes from the selected animal/GPS row.
- `tracking_id` — comes from the latest GPS record.
- `predicted_at` — PostgreSQL timestamp.
- `review_status` — human review workflow; new AI predictions are `unreviewed`.

The existing database already has the Prediction table and the risk-event/GPS/risk-zone data used by this model.

## Features used

The Random Forest receives:

1. GPS speed
2. Distance to nearest risk zone
3. Risk level of nearest zone
4. Distance to human settlement
5. Distance to road
6. Distance to poaching zone
7. Distance to agricultural land
8. Distance to other zone
9. Endangered-species flag
10. Number of risk events in the previous 24 hours
11. Collar battery level
12. Latest health status converted to a numeric risk score
13. Outside-reserve flag
14. Hour of day

## Important limitation

The supplied demo database has only a small amount of labelled history. Therefore this is a working prototype AI pipeline, not a scientifically validated wildlife-risk model.

For a stronger model, collect many more historical GPS points with known future risk outcomes.

## Setup

From the `server` directory:

```bash
python -m venv venv
```

Windows:

```bash
venv\Scripts\activate
```

Install:

```bash
pip install -r requirements.txt
```

Create `.env` from `.env.example` and enter your PostgreSQL credentials.

## Train

```bash
python train_model.py
```

This creates:

```text
wildguard_model.joblib
training_metrics.json
```

## Start API

```bash
uvicorn app:app --reload --port 8000
```

API:

```text
http://localhost:8000
```

Swagger:

```text
http://localhost:8000/docs
```

## Generate predictions

All active/latest animals:

```text
POST http://localhost:8000/predict
```

One animal:

```text
POST http://localhost:8000/predict/2
```

Read the Prediction table:

```text
GET http://localhost:8000/predictions
```

## Connect the existing Vite frontend

Where the frontend currently loads predictions, call:

```javascript
fetch("http://localhost:8000/predict", {
  method: "POST"
})
  .then(response => response.json())
  .then(data => {
    console.log(data);
  });
```

Then reload the prediction table from:

```javascript
fetch("http://localhost:8000/predictions")
```

The existing PostgreSQL `Prediction` table will contain the generated AI rows, so the dashboard can display them.

## Recommended demo

1. Start PostgreSQL/PostGIS.
2. Start the FastAPI server.
3. Open the WildGuard dashboard.
4. Add or update a GPS location.
5. Click/trigger "Run AI Prediction".
6. The API reads the latest GPS + risk-zone + animal data.
7. Random Forest predicts risk.
8. The API inserts the result into `Prediction`.
9. The dashboard reads `Prediction`.
10. Ranger reviews the prediction, leaving `review_status` as the human workflow.

## Existing SQL procedure

The database already contains `sp_generate_predictions`, which uses linear extrapolation and hard-coded risk rules.

Do not describe that procedure as machine learning.

The Python service in this folder is the actual Random Forest ML layer.
