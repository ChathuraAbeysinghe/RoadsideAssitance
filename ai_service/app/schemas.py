"""
Pydantic schemas for the AI Fault Classification & Smart Provider Recommendation API.
"""

from typing import List, Optional, Dict
from pydantic import BaseModel, Field


class FaultPredictionRequest(BaseModel):
    description: str = Field(
        ...,
        min_length=3,
        max_length=1500,
        description="Driver natural language symptom description",
        examples=["My motorcycle does not start and the lights are completely dead."]
    )
    vehicle_type: Optional[str] = Field(
        None,
        description="Vehicle category such as car, motorbike, van, threeWheeler, truck",
        examples=["motorbike"]
    )


class FaultPredictionResponse(BaseModel):
    predicted_category: str = Field(
        ...,
        description="Target roadside service category mapped to Flutter ServiceType",
        examples=["batteryBoost"]
    )
    raw_label: str = Field(
        ...,
        description="Underlying ML classifier label",
        examples=["battery_boost"]
    )
    confidence: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="Prediction confidence score",
        examples=[0.88]
    )
    requires_clarification: bool = Field(
        ...,
        description="Flag indicating if the symptom description is ambiguous or low-confidence"
    )
    explanation: str = Field(
        ...,
        description="Human-readable explanation of the recommended service category"
    )
    suggested_questions: List[str] = Field(
        default_factory=list,
        description="Targeted follow-up questions when clarification is required"
    )
    safety_alert: Optional[str] = Field(
        None,
        description="Critical roadside safety warning if hazardous conditions are detected"
    )
    model_version: str = Field(
        ...,
        description="Identifier of the deployed model and feature pipeline"
    )


class ProviderCandidate(BaseModel):
    id: str
    name: str
    services: List[str]
    is_available: bool = True
    distance_km: float
    rating: float = 0.0
    rating_count: int = 0
    phone_number: Optional[str] = None
    profile_image_path: Optional[str] = None


class ProviderRecommendationRequest(BaseModel):
    service_category: str = Field(..., description="ServiceType name, e.g. batteryBoost or towTruck")
    max_radius_km: float = Field(default=15.0, ge=1.0, le=50.0)
    providers: List[ProviderCandidate] = Field(default_factory=list)


class RankedProvider(BaseModel):
    id: str
    name: str
    composite_score: float
    distance_km: float
    rating: float
    rating_count: int
    recommendation_reasons: List[str]
    is_eligible: bool
    phone_number: Optional[str] = None
    profile_image_path: Optional[str] = None


class ProviderRecommendationResponse(BaseModel):
    service_category: str
    total_candidates: int
    eligible_count: int
    recommendations: List[RankedProvider]
    ranking_criteria: Dict[str, float]


class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    model_name: str
    supported_categories: List[str]
