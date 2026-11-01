from decimal import Decimal

from db import execute, fetch_all
from features import build_feature_row, sql_prediction_inputs
from model import load_model

def predict_and_store(animal_id=None):
    bundle = load_model()
    model = bundle["model"]

    params = (animal_id,) if animal_id is not None else ()
    rows = fetch_all(sql_prediction_inputs(animal_id), params)

    if not rows:
        return []

    X = [build_feature_row(row) for row in rows]
    probabilities = model.predict_proba(X)
    classes = list(model.classes_)

    results = []

    for i in range(len(rows)):
        best_index = max(
            range(len(classes)),
            key=lambda j: probabilities[i][j]
        )

        predicted_risk = str(classes[best_index])
        risk_probability = float(probabilities[i][best_index])

        tracking_id = rows[i]["tracking_id"]
        current_animal_id = rows[i]["animal_id"]

        # Keep review_status as a human workflow field.
        execute(
            """
            INSERT INTO Prediction
                (animal_id, tracking_id, predicted_risk,
                 risk_probability, review_status)
            VALUES (%s, %s, %s, %s, 'unreviewed')
            """,
            (
                current_animal_id,
                tracking_id,
                predicted_risk,
                round(risk_probability, 4),
            ),
        )

        results.append({
            "animal_id": current_animal_id,
            "tracking_id": tracking_id,
            "predicted_risk": predicted_risk,
            "risk_probability": round(risk_probability, 4),
        })

    return results
