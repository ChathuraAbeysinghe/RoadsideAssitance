"""
Vehicle Fault Classification Training Pipeline.
Trains and compares Logistic Regression and Calibrated Linear SVM on vehicle symptom text.
Selects the best model based on held-out test Macro F1-Score.
"""

import json
import os
import re
import joblib
from pathlib import Path
from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.svm import LinearSVC
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import classification_report, f1_score, accuracy_score


def preprocess_text(text: str) -> str:
    """Cleans and normalizes driver symptom descriptions."""
    if not isinstance(text, str):
        return ""
    text = text.lower()
    # Normalize punctuation and extra whitespace
    text = re.sub(r"[^\w\s]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def load_dataset(dataset_path: Path):
    """Loads the dataset from JSON and extracts texts, labels, and metadata."""
    with open(dataset_path, "r", encoding="utf-8") as f:
        payload = json.load(f)
    
    samples = payload.get("data", [])
    texts = [preprocess_text(s["text"]) for s in samples]
    labels = [s["category"] for s in samples]
    return texts, labels, payload.get("metadata", {})


def train_and_compare(dataset_path: Path, models_dir: Path):
    """Executes model training, comparative evaluation, and artifact serialization."""
    models_dir.mkdir(parents=True, exist_ok=True)
    texts, labels, metadata = load_dataset(dataset_path)

    print(f"Loaded {len(texts)} samples across {len(set(labels))} classes: {sorted(list(set(labels)))}")

    # Stratified split to ensure each category is represented in training and testing
    X_train, X_test, y_train, y_test = train_test_split(
        texts,
        labels,
        test_size=0.25,
        random_state=42,
        stratify=labels
    )
    print(f"Training split: {len(X_train)} | Held-out test split: {len(X_test)}")

    # TF-IDF Vectorizer with unigrams & bigrams
    vectorizer = TfidfVectorizer(
        ngram_range=(1, 2),
        sublinear_tf=True,
        min_df=1,
        max_features=1200
    )
    X_train_vec = vectorizer.fit_transform(X_train)
    X_test_vec = vectorizer.transform(X_test)

    # 1. Candidate A: Logistic Regression
    lr = LogisticRegression(C=2.0, max_iter=1000, random_state=42)
    lr.fit(X_train_vec, y_train)
    y_pred_lr = lr.predict(X_test_vec)
    acc_lr = accuracy_score(y_test, y_pred_lr)
    f1_lr = f1_score(y_test, y_pred_lr, average="macro")

    # 2. Candidate B: Calibrated Linear SVM (supports probability calibration)
    base_svm = LinearSVC(C=1.0, random_state=42, dual=False)
    svm = CalibratedClassifierCV(estimator=base_svm, cv=3)
    svm.fit(X_train_vec, y_train)
    y_pred_svm = svm.predict(X_test_vec)
    acc_svm = accuracy_score(y_test, y_pred_svm)
    f1_svm = f1_score(y_test, y_pred_svm, average="macro")

    print("\n--- Model Evaluation on Held-Out Test Set ---")
    print(f"Logistic Regression: Accuracy = {acc_lr:.4f}, Macro F1 = {f1_lr:.4f}")
    print(f"Calibrated Linear SVM: Accuracy = {acc_svm:.4f}, Macro F1 = {f1_svm:.4f}")

    # Select the model with highest Macro F1
    if f1_lr >= f1_svm:
        selected_model = lr
        selected_name = "Logistic Regression"
        best_acc = acc_lr
        best_f1 = f1_lr
        best_pred = y_pred_lr
    else:
        selected_model = svm
        selected_name = "Calibrated Linear SVM"
        best_acc = acc_svm
        best_f1 = f1_svm
        best_pred = y_pred_svm

    print(f"\nSelected Model: {selected_name} (Macro F1: {best_f1:.4f})")
    print("\nDetailed Classification Report for Selected Model:")
    print(classification_report(y_test, best_pred))

    # Save artifacts
    vectorizer_path = models_dir / "vectorizer.pkl"
    model_path = models_dir / "classifier.pkl"
    meta_path = models_dir / "metadata.json"

    joblib.dump(vectorizer, vectorizer_path)
    joblib.dump(selected_model, model_path)

    eval_metadata = {
        "model_name": selected_name,
        "classes": list(selected_model.classes_),
        "accuracy": float(best_acc),
        "macro_f1": float(best_f1),
        "train_samples": len(X_train),
        "test_samples": len(X_test),
        "vectorizer_features": int(X_train_vec.shape[1]),
        "comparison": {
            "logistic_regression": {"accuracy": float(acc_lr), "macro_f1": float(f1_lr)},
            "calibrated_linear_svm": {"accuracy": float(acc_svm), "macro_f1": float(f1_svm)}
        },
        "taxonomy_mapping": metadata.get("category_mapping", {})
    }

    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(eval_metadata, f, indent=2)

    print(f"Artifacts successfully saved to {models_dir}")
    return eval_metadata


if __name__ == "__main__":
    base_dir = Path(__file__).resolve().parent.parent
    dataset_file = base_dir / "datasets" / "vehicle_faults_dataset.json"
    models_output_dir = base_dir / "models"
    train_and_compare(dataset_file, models_output_dir)
