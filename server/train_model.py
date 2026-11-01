import json
from pathlib import Path

import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report
from sklearn.model_selection import train_test_split

from db import fetch_all
from features import FEATURE_COLUMNS, build_feature_row, sql_training_data

MODEL_PATH = Path(__file__).resolve().parent / "wildguard_model.joblib"
METRICS_PATH = Path(__file__).resolve().parent / "training_metrics.json"

def train():
    rows = fetch_all(sql_training_data())

    if len(rows) < 8:
        raise RuntimeError(
            f"Only {len(rows)} labelled records were found. "
            "Add more Animal_Risk_Event/GPS_Tracking history before training."
        )

    X = [build_feature_row(row) for row in rows]
    y = [row["target_risk"] for row in rows]

    # With a small demo dataset, stratification is only possible when
    # every class has enough examples.
    counts = {label: y.count(label) for label in set(y)}
    can_stratify = min(counts.values()) >= 2

    if len(rows) >= 12 and can_stratify:
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.25, random_state=42, stratify=y
        )
    else:
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.25, random_state=42
        )

    model = RandomForestClassifier(
        n_estimators=300,
        max_depth=10,
        min_samples_leaf=1,
        class_weight="balanced",
        random_state=42,
    )

    model.fit(X_train, y_train)

    metrics = {
        "training_rows": len(X_train),
        "test_rows": len(X_test),
        "class_counts": counts,
    }

    if len(set(y_test)) > 1:
        metrics["classification_report"] = classification_report(
            y_test, model.predict(X_test), output_dict=True, zero_division=0
        )

    joblib.dump(
        {
            "model": model,
            "features": FEATURE_COLUMNS,
            "classes": list(model.classes_),
        },
        MODEL_PATH,
    )

    METRICS_PATH.write_text(json.dumps(metrics, indent=2))

    print("MODEL TRAINED")
    print(f"Saved: {MODEL_PATH}")
    print(f"Rows used: {len(rows)}")
    print("Classes:", list(model.classes_))
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    train()
