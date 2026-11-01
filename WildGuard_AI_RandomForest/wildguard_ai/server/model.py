from pathlib import Path
import joblib

MODEL_PATH = Path(__file__).resolve().parent / "wildguard_model.joblib"

def load_model():
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            "AI model not found. Run: python train_model.py"
        )
    return joblib.load(MODEL_PATH)
