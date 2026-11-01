from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from db import fetch_all
from model import MODEL_PATH
from predict import predict_and_store

app = FastAPI(
    title="WildGuard AI Prediction API",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict this to your Vite URL for production.
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def root():
    return {
        "project": "WildGuard",
        "ai": "Random Forest wildlife risk classifier",
        "status": "running",
        "model_exists": MODEL_PATH.exists(),
    }

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_exists": MODEL_PATH.exists(),
    }

@app.get("/predictions")
def predictions():
    return fetch_all(
        """
        SELECT
            prediction_id,
            animal_id,
            tracking_id,
            predicted_at,
            predicted_risk,
            risk_probability,
            review_status
        FROM Prediction
        ORDER BY prediction_id DESC
        """
    )

@app.post("/predict")
def predict_all():
    try:
        return {
            "success": True,
            "predictions": predict_and_store(),
        }
    except FileNotFoundError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

@app.post("/predict/{animal_id}")
def predict_one(animal_id: int):
    try:
        results = predict_and_store(animal_id)
        if not results:
            raise HTTPException(
                status_code=404,
                detail="No GPS tracking data found for this animal."
            )
        return {"success": True, "predictions": results}
    except FileNotFoundError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
