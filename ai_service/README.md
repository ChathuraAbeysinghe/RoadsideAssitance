# RoadsideAssistance AI Fault Classification & Provider Recommendation Service

FastAPI-powered machine learning microservice that classifies natural language vehicle breakdown symptoms into validated roadside assistance service categories and performs transparent multi-criteria provider recommendation.

---

## 1. Architecture Overview
- **Model Framework**: scikit-learn (`TfidfVectorizer` + `LogisticRegression` selected via held-out cross-validation against `LinearSVC`).
- **Feature Pipeline**: Sublinear TF-IDF with unigrams & bigrams, normalized text preprocessing.
- **Service Categories**: Mapped directly to Flutter `ServiceType`:
  - `batteryBoost` (Battery Boosting / Jump Start)
  - `flatTireChange` (Flat Tire Replacement)
  - `fuelDelivery` (Emergency Fuel Delivery)
  - `mechanic` (On-site Diagnostic & Mechanical Repair)
  - `towTruck` (Emergency Towing & Vehicle Recovery)
  - `uncertain` (Ambiguity fallback with targeted follow-up questions)
- **Safety Engine**: Real-time regex detection of roadside fire, smoke, fuel leaks, and brake failure.
- **Provider Ranking**: Transparent, explainable multi-criteria ranking combining proximity distance ($0.60$) and damped star rating ($0.40$) with strict eligibility filtering.

---

## 2. Directory Structure
```text
ai_service/
├── app/
│   ├── main.py              # FastAPI server entrypoint & CORS setup
│   ├── schemas.py           # Pydantic data contracts
│   ├── predictor.py         # Inference engine & uncertainty thresholding
│   ├── service_mapping.py   # Category mapping, safety alerts, follow-up questions
│   └── ranking.py           # Multi-criteria provider scoring engine
├── datasets/
│   ├── vehicle_faults_dataset.json  # Documented symptom dataset
│   └── README.md            # Dataset documentation, license & schema
├── models/
│   ├── classifier.pkl       # Serialized Logistic Regression model
│   ├── vectorizer.pkl       # Serialized TF-IDF vectorizer
│   └── metadata.json        # Evaluation metrics & class taxonomy
├── tests/
│   └── test_api.py          # Automated test suite (10 test cases)
├── training/
│   ├── train_model.py       # Training & model comparison pipeline
│   └── evaluate_model.py    # Confusion matrix & test evaluation script
├── .env.example             # Sample environment variables
└── requirements.txt         # Python package dependencies
```

---

## 3. Setup Instructions (Windows)

### Prerequisites
- Python 3.10+ (Tested on Python 3.14.8)
- pip

### Step 1: Install Dependencies
Open PowerShell or Command Prompt in the project root:
```powershell
python -m pip install -r ai_service\requirements.txt
```

### Step 2: (Optional) Re-Train the Model
```powershell
python ai_service\training\train_model.py
```

### Step 3: Evaluate the Model
```powershell
python ai_service\training\evaluate_model.py
```

### Step 4: Run Automated Tests
```powershell
python -m pytest ai_service\tests\test_api.py -v
```

### Step 5: Start the API Server
```powershell
python -m uvicorn ai_service.app.main:app --host 0.0.0.0 --port 8000 --reload
```
Interactive Swagger documentation is available at: `http://localhost:8000/docs`

---

## 4. API Endpoints

### 1. `POST /predict-fault`
Classifies a driver's problem description.
- **Request**:
```json
{
  "description": "My motorcycle does not start and the headlights are completely dim.",
  "vehicle_type": "motorbike"
}
```
- **Response**:
```json
{
  "predicted_category": "batteryBoost",
  "raw_label": "battery_boost",
  "confidence": 0.88,
  "requires_clarification": false,
  "explanation": "The reported symptoms indicate a drained battery or starter power problem.",
  "suggested_questions": [
    "Does the engine make a rapid clicking noise when you turn the key?"
  ],
  "safety_alert": null,
  "model_version": "Logistic Regression"
}
```

### 2. `POST /recommend-providers`
Ranks available service providers based on distance and rating.
- **Request**:
```json
{
  "service_category": "batteryBoost",
  "max_radius_km": 15.0,
  "providers": [
    {
      "id": "p1",
      "name": "Quick Battery Fix",
      "services": ["batteryBoost"],
      "is_available": true,
      "distance_km": 2.5,
      "rating": 4.8,
      "rating_count": 25
    }
  ]
}
```
- **Response**:
```json
{
  "service_category": "batteryBoost",
  "total_candidates": 1,
  "eligible_count": 1,
  "recommendations": [
    {
      "id": "p1",
      "name": "Quick Battery Fix",
      "composite_score": 0.885,
      "distance_km": 2.5,
      "rating": 4.8,
      "rating_count": 25,
      "recommendation_reasons": [
        "Verified provider for batteryBoost",
        "Closest to your location (2.5 km)",
        "Top-rated service (4.8 ★)"
      ],
      "is_eligible": true
    }
  ],
  "ranking_criteria": {
    "distance": 0.60,
    "rating_quality": 0.40
  }
}
```

### 3. `GET /health`
Returns system and model health status.
