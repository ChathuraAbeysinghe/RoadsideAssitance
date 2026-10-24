"""
Model Evaluation Script.
Computes Confusion Matrix, Precision, Recall, and tests unseen edge cases.
"""

import json
from pathlib import Path
import joblib
from sklearn.metrics import confusion_matrix, classification_report
from train_model import preprocess_text, load_dataset


def evaluate_model_pipeline(dataset_path: Path, models_dir: Path):
    """Loads serialized artifacts and runs deep evaluation on dataset."""
    vectorizer = joblib.load(models_dir / "vectorizer.pkl")
    classifier = joblib.load(models_dir / "classifier.pkl")

    with open(models_dir / "metadata.json", "r", encoding="utf-8") as f:
        meta = json.load(f)

    texts, labels, _ = load_dataset(dataset_path)
    X_vec = vectorizer.transform(texts)
    y_pred = classifier.predict(X_vec)

    classes = classifier.classes_
    cm = confusion_matrix(labels, y_pred, labels=classes)

    print("=" * 60)
    print("           MODEL EVALUATION SUMMARY & METRICS")
    print("=" * 60)
    print(f"Architecture : {meta.get('model_name')}")
    print(f"Classes      : {list(classes)}")
    print(f"Test F1      : {meta.get('macro_f1'):.4f}")
    print("-" * 60)
    print("Classification Report on Dataset:")
    print(classification_report(labels, y_pred, target_names=classes))
    print("-" * 60)
    print("Confusion Matrix:")
    header = f"{'True/Pred':<16} " + " ".join([f"{c[:10]:>10}" for c in classes])
    print(header)
    for i, row_label in enumerate(classes):
        row_str = f"{row_label[:15]:<16} " + " ".join([f"{val:>10}" for val in cm[i]])
        print(row_str)
    print("=" * 60)

    # Test unseen out-of-distribution and edge cases
    unseen_cases = [
        ("My motorcycle battery is totally flat and clicks when electric start is pressed", "battery_boost"),
        ("Tire blew out on highway, need wheel change", "flat_tire"),
        ("Out of gas on bypass road, need 5L petrol", "fuel_delivery"),
        ("Engine knocking sound and coolant boiling over", "mechanic"),
        ("Car flipped over into ditch, front axle snapped", "tow_truck"),
        ("Hello, is anyone online?", "uncertain"),
        ("I have no idea what is happening with the car", "uncertain")
    ]

    print("\nEvaluating previously unseen test samples:")
    correct = 0
    for text, expected in unseen_cases:
        cleaned = preprocess_text(text)
        vec = vectorizer.transform([cleaned])
        pred = classifier.predict(vec)[0]
        proba = max(classifier.predict_proba(vec)[0])
        status = "PASS" if pred == expected else "FAIL"
        if status == "PASS":
            correct += 1
        print(f"[{status}] Pred: {pred:<14} (p={proba:.2f}) | Expected: {expected:<14} | Text: '{text}'")
    print(f"\nUnseen Cases Accuracy: {correct}/{len(unseen_cases)} ({correct/len(unseen_cases)*100:.1f}%)")


if __name__ == "__main__":
    base_dir = Path(__file__).resolve().parent.parent
    dataset_file = base_dir / "datasets" / "vehicle_faults_dataset.json"
    models_path = base_dir / "models"
    evaluate_model_pipeline(dataset_file, models_path)
