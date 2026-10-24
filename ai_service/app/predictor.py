"""
Inference engine for Vehicle Fault Classification with uncertainty handling and safety checks.
"""

import json
import re
from pathlib import Path
from typing import Optional, Tuple
import joblib

from .schemas import FaultPredictionRequest, FaultPredictionResponse
from .service_mapping import (
    ML_TO_FLUTTER_CATEGORY,
    CATEGORY_EXPLANATIONS,
    FOLLOW_UP_QUESTIONS,
    check_safety_hazards,
)


class FaultPredictor:
    """Encapsulates vectorizer and classification model inference."""

    def __init__(self, models_dir: Optional[Path] = None):
        if models_dir is None:
            models_dir = Path(__file__).resolve().parent.parent / "models"
        self.models_dir = models_dir
        self.vectorizer = None
        self.classifier = None
        self.metadata = {}
        self.classes = []
        self.min_confidence_threshold = 0.30  # Validated uncertainty cutoff
        self.load_artifacts()

    def load_artifacts(self):
        """Loads serialized machine learning artifacts from disk."""
        vec_path = self.models_dir / "vectorizer.pkl"
        cls_path = self.models_dir / "classifier.pkl"
        meta_path = self.models_dir / "metadata.json"

        if not vec_path.exists() or not cls_path.exists():
            raise FileNotFoundError(f"Model artifacts not found in {self.models_dir}. Run training first.")

        self.vectorizer = joblib.load(vec_path)
        self.classifier = joblib.load(cls_path)

        if meta_path.exists():
            with open(meta_path, "r", encoding="utf-8") as f:
                self.metadata = json.load(f)
        
        self.classes = list(self.classifier.classes_)

    @staticmethod
    def preprocess_text(text: str) -> str:
        """Cleans and standardizes text input."""
        if not isinstance(text, str):
            return ""
        text = text.lower()
        text = re.sub(r"[^\w\s]", " ", text)
        text = re.sub(r"\s+", " ", text).strip()
        return text

    def predict(self, req: FaultPredictionRequest) -> FaultPredictionResponse:
        """Processes driver problem description and returns structured prediction."""
        raw_text = req.description
        cleaned = self.preprocess_text(raw_text)

        # 1. Safety Hazard Check
        safety_alert = check_safety_hazards(raw_text)

        # 2. Check for empty or ultra-short input
        words = cleaned.split()
        if len(words) < 2:
            return FaultPredictionResponse(
                predicted_category="uncertain",
                raw_label="uncertain",
                confidence=0.0,
                requires_clarification=True,
                explanation="Your description is very short. Please describe the symptoms in a few more words so we can recommend the best roadside service.",
                suggested_questions=FOLLOW_UP_QUESTIONS["uncertain"],
                safety_alert=safety_alert,
                model_version=self.metadata.get("model_name", "TFIDF-LogReg-v1.0")
            )

        # 3. Model Inference with Probabilities
        vec = self.vectorizer.transform([cleaned])
        probas = self.classifier.predict_proba(vec)[0]
        max_idx = probas.argmax()
        raw_label = self.classes[max_idx]
        confidence = float(probas[max_idx])

        # 4. Uncertainty & Ambiguity Fallback
        # If model predicts 'uncertain' OR top probability is below threshold, flag as requiring clarification
        requires_clarification = (
            raw_label == "uncertain" or confidence < self.min_confidence_threshold
        )

        flutter_category = ML_TO_FLUTTER_CATEGORY.get(raw_label, "uncertain")
        if requires_clarification and raw_label != "uncertain":
            # Still provide the likely candidate, but with explicit uncertainty flag
            explanation = (
                f"We tentatively suggest {flutter_category} based on your description, "
                f"but some details remain ambiguous. Please confirm or select another category."
            )
        else:
            explanation = CATEGORY_EXPLANATIONS.get(
                flutter_category, CATEGORY_EXPLANATIONS["uncertain"]
            )

        suggested_q = FOLLOW_UP_QUESTIONS.get(
            flutter_category, FOLLOW_UP_QUESTIONS["uncertain"]
        )

        return FaultPredictionResponse(
            predicted_category=flutter_category,
            raw_label=raw_label,
            confidence=round(confidence, 3),
            requires_clarification=requires_clarification,
            explanation=explanation,
            suggested_questions=suggested_q,
            safety_alert=safety_alert,
            model_version=self.metadata.get("model_name", "TFIDF-LogReg-v1.0")
        )
