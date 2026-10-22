"""
FastAPI application entrypoint for RoadsideAssistance AI Service.
Exposes endpoints for vehicle problem classification and smart provider recommendation.
"""

from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

from .schemas import (
    FaultPredictionRequest,
    FaultPredictionResponse,
    ProviderRecommendationRequest,
    ProviderRecommendationResponse,
    HealthResponse,
)
from .predictor import FaultPredictor
from .ranking import ProviderRankingEngine

models_path = Path(__file__).resolve().parent.parent / "models"
try:
    predictor: FaultPredictor = FaultPredictor(models_dir=models_path)
    ranking_engine: ProviderRankingEngine = ProviderRankingEngine()
except Exception as _e:
    predictor = None
    ranking_engine = ProviderRankingEngine()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Ensures ML model artifacts and ranking engine are initialized."""
    global predictor, ranking_engine
    if predictor is None:
        try:
            predictor = FaultPredictor(models_dir=models_path)
        except Exception as e:
            print(f"[AI Service] Warning: Failed to load model artifacts on startup: {e}")
    if ranking_engine is None:
        ranking_engine = ProviderRankingEngine()
    yield


app = FastAPI(
    title="RoadsideAssistance AI Fault Classification API",
    description="Explainable vehicle problem assistant and smart roadside provider ranking for motorists in Sri Lanka.",
    version="1.0.0",
    lifespan=lifespan
)

# Enable CORS for Flutter mobile clients and web interfaces
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse, tags=["Health"])
def health_check():
    """Returns service health status and model deployment metadata."""
    if predictor is None:
        return HealthResponse(
            status="degraded",
            model_loaded=False,
            model_name="unloaded",
            supported_categories=[]
        )
    return HealthResponse(
        status="healthy",
        model_loaded=True,
        model_name=predictor.metadata.get("model_name", "TFIDF-LogReg-v1.0"),
        supported_categories=predictor.classes
    )


@app.post(
    "/predict-fault",
    response_model=FaultPredictionResponse,
    status_code=status.HTTP_200_OK,
    tags=["Fault Classification"]
)
def predict_fault(request: FaultPredictionRequest):
    """
    Analyzes driver problem description, predicts the most appropriate roadside service category,
    checks for safety critical hazards, and provides understandable explanations and follow-up questions.
    """
    if predictor is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI fault classification model is not loaded."
        )

    try:
        response = predictor.predict(request)
        return response
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Inference error during fault classification: {str(exc)}"
        )


@app.post(
    "/recommend-providers",
    response_model=ProviderRecommendationResponse,
    status_code=status.HTTP_200_OK,
    tags=["Provider Recommendation"]
)
def recommend_providers(request: ProviderRecommendationRequest):
    """
    Ranks nearby service providers for a selected service category using
    transparent multi-criteria scoring (distance proximity + validated customer rating).
    """
    if ranking_engine is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Ranking engine is not initialized."
        )

    try:
        response = ranking_engine.rank_providers(request)
        return response
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error evaluating provider candidates: {str(exc)}"
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
