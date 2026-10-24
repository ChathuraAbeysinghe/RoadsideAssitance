"""
Automated unit and integration tests for AI Fault Classification & Provider Recommendation.
"""

import sys
from pathlib import Path
import pytest
from fastapi.testclient import TestClient

# Add app package to system path
app_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(app_dir))

from app.main import app
from app.predictor import FaultPredictor
from app.ranking import ProviderRankingEngine
from app.schemas import (
    FaultPredictionRequest,
    ProviderRecommendationRequest,
    ProviderCandidate,
)

client = TestClient(app)


def test_health_endpoint():
    """Verify health endpoint reports healthy status and model classes."""
    res = client.get("/health")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "healthy"
    assert data["model_loaded"] is True
    assert "battery_boost" in data["supported_categories"]
    assert "flat_tire" in data["supported_categories"]


def test_predict_battery_boost():
    """Test standard battery jumpstart description."""
    payload = {
        "description": "My motorcycle does not start and the headlights are completely dim.",
        "vehicle_type": "motorbike"
    }
    res = client.post("/predict-fault", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["predicted_category"] == "batteryBoost"
    assert data["raw_label"] == "battery_boost"
    assert data["confidence"] > 0.30
    assert "battery" in data["explanation"].lower()


def test_predict_flat_tire():
    """Test tire puncture symptom."""
    payload = {
        "description": "I got a puncture on the highway and my rear tire is completely flat.",
        "vehicle_type": "car"
    }
    res = client.post("/predict-fault", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["predicted_category"] == "flatTireChange"
    assert data["raw_label"] == "flat_tire"
    assert "tire" in data["explanation"].lower() or "tyre" in data["explanation"].lower()


def test_predict_fuel_delivery():
    """Test ran out of gas symptom."""
    payload = {
        "description": "Engine sputtered and died on the road because I ran out of petrol.",
        "vehicle_type": "car"
    }
    res = client.post("/predict-fault", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["predicted_category"] == "fuelDelivery"
    assert data["raw_label"] == "fuel_delivery"


def test_predict_tow_truck():
    """Test severe accident or recovery symptom."""
    payload = {
        "description": "Car went off the road into a deep ditch and front axle is broken.",
        "vehicle_type": "car"
    }
    res = client.post("/predict-fault", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["predicted_category"] == "towTruck"
    assert data["raw_label"] == "tow_truck"


def test_predict_mechanic():
    """Test engine overheating symptom."""
    payload = {
        "description": "Engine is severely overheating with steam and coolant leaking out.",
        "vehicle_type": "van"
    }
    res = client.post("/predict-fault", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["predicted_category"] == "mechanic"


def test_predict_uncertain_or_ambiguous():
    """Test ambiguous description triggers uncertainty fallback."""
    payload = {
        "description": "Hello, is anyone online right now?",
        "vehicle_type": "car"
    }
    res = client.post("/predict-fault", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["requires_clarification"] is True
    assert len(data["suggested_questions"]) > 0


def test_safety_critical_detection():
    """Test that safety critical situations (fire, smoke, fuel spray) trigger immediate safety alert."""
    payload = {
        "description": "Engine bay has thick black smoke and active flames coming out!",
        "vehicle_type": "car"
    }
    res = client.post("/predict-fault", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["safety_alert"] is not None
    assert "FIRE" in data["safety_alert"] or "SMOKE" in data["safety_alert"]


def test_empty_or_too_short_input_validation():
    """Test validation rejection for empty or sub-minimum inputs."""
    res = client.post("/predict-fault", json={"description": ""})
    assert res.status_code == 422  # Pydantic validation error


def test_smart_provider_recommendation_ranking():
    """Test provider recommendation with eligibility constraints and composite scoring."""
    payload = {
        "service_category": "batteryBoost",
        "max_radius_km": 15.0,
        "providers": [
            {
                "id": "p1",
                "name": "Quick Battery Fix",
                "services": ["batteryBoost", "flatTireChange"],
                "is_available": True,
                "distance_km": 2.5,
                "rating": 4.8,
                "rating_count": 25
            },
            {
                "id": "p2",
                "name": "Far Away Battery",
                "services": ["batteryBoost"],
                "is_available": True,
                "distance_km": 12.0,
                "rating": 4.9,
                "rating_count": 50
            },
            {
                "id": "p3",
                "name": "Offline Battery Tech",
                "services": ["batteryBoost"],
                "is_available": False,
                "distance_km": 1.0,
                "rating": 5.0,
                "rating_count": 10
            },
            {
                "id": "p4",
                "name": "Tow Only Operator",
                "services": ["towTruck"],
                "is_available": True,
                "distance_km": 2.0,
                "rating": 5.0,
                "rating_count": 30
            }
        ]
    }
    res = client.post("/recommend-providers", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["eligible_count"] == 2
    recs = data["recommendations"]

    # p1 should be ranked higher than p2 because p1 is 2.5 km away vs 12 km
    assert recs[0]["id"] == "p1"
    assert recs[0]["is_eligible"] is True
    assert any("Closest to your location" in r for r in recs[0]["recommendation_reasons"])

    # p2 is eligible but further away
    assert recs[1]["id"] == "p2"
    assert recs[1]["is_eligible"] is True

    # p3 (offline) and p4 (wrong service) must be flagged ineligible
    ineligible_ids = [r["id"] for r in recs if not r["is_eligible"]]
    assert "p3" in ineligible_ids
    assert "p4" in ineligible_ids
