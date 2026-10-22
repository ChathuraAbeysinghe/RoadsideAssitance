"""
Smart Provider Recommendation & Ranking Engine.
Transparent, explainable multi-criteria scoring with eligibility filtering.
"""

from typing import List, Dict
from .schemas import (
    ProviderCandidate,
    RankedProvider,
    ProviderRecommendationRequest,
    ProviderRecommendationResponse
)

# Configurable ranking weights (normalized sum = 1.0)
DEFAULT_WEIGHTS: Dict[str, float] = {
    "distance": 0.60,      # Proximity is the highest priority in roadside breakdowns
    "rating_quality": 0.40 # Validated customer rating
}


class ProviderRankingEngine:
    """Applies strict eligibility filtering followed by multi-criteria transparent ranking."""

    def __init__(self, weights: Dict[str, float] = None):
        self.weights = weights or DEFAULT_WEIGHTS

    def rank_providers(self, request: ProviderRecommendationRequest) -> ProviderRecommendationResponse:
        service_target = request.service_category
        max_dist = request.max_radius_km
        candidates = request.providers

        ranked_list: List[RankedProvider] = []
        eligible_count = 0

        for p in candidates:
            # 1. Eligibility constraints
            service_matched = (
                service_target in p.services or
                any(s.lower() == service_target.lower() for s in p.services)
            )
            is_available = p.is_available
            within_radius = (p.distance_km <= max_dist)

            is_eligible = service_matched and is_available and within_radius

            reasons: List[str] = []
            if not is_eligible:
                if not service_matched:
                    reasons.append("Does not offer this service category")
                if not is_available:
                    reasons.append("Provider is currently offline")
                if not within_radius:
                    reasons.append(f"Outside {max_dist:.1f} km search radius")
                
                ranked_list.append(
                    RankedProvider(
                        id=p.id,
                        name=p.name,
                        composite_score=0.0,
                        distance_km=round(p.distance_km, 2),
                        rating=round(p.rating, 1),
                        rating_count=p.rating_count,
                        recommendation_reasons=reasons,
                        is_eligible=False,
                        phone_number=p.phone_number,
                        profile_image_path=p.profile_image_path
                    )
                )
                continue

            eligible_count += 1
            reasons.append(f"Verified provider for {service_target}")

            # 2. Normalized Distance Score (0.0 - 1.0, 1.0 is closest)
            dist_score = max(0.0, 1.0 - (p.distance_km / max_dist))
            if p.distance_km <= 3.0:
                reasons.append(f"Closest to your location ({p.distance_km:.1f} km)")
            elif p.distance_km <= 7.0:
                reasons.append(f"Nearby provider ({p.distance_km:.1f} km)")

            # 3. Normalized Rating Score with Bayesian/damping prior
            # Avoids a 1-review 5-star provider unfairly outranking a 40-review 4.8-star provider
            prior_stars = 3.5
            prior_weight = 3
            if p.rating_count > 0:
                damped_rating = (
                    (p.rating * p.rating_count) + (prior_stars * prior_weight)
                ) / (p.rating_count + prior_weight)
                rating_score = min(1.0, max(0.0, damped_rating / 5.0))
                if p.rating >= 4.5:
                    reasons.append(f"Top-rated service ({p.rating:.1f} ★)")
                elif p.rating >= 4.0:
                    reasons.append(f"Well-rated service ({p.rating:.1f} ★)")
            else:
                rating_score = prior_stars / 5.0  # Neutral score for new providers
                reasons.append("New verified provider")

            # 4. Composite Weighted Score
            composite = (
                self.weights["distance"] * dist_score +
                self.weights["rating_quality"] * rating_score
            )

            ranked_list.append(
                RankedProvider(
                    id=p.id,
                    name=p.name,
                    composite_score=round(composite, 4),
                    distance_km=round(p.distance_km, 2),
                    rating=round(p.rating, 1),
                    rating_count=p.rating_count,
                    recommendation_reasons=reasons,
                    is_eligible=True,
                    phone_number=p.phone_number,
                    profile_image_path=p.profile_image_path
                )
            )

        # Sort: Eligible providers first (highest score to lowest), followed by ineligible
        ranked_list.sort(key=lambda r: (1 if r.is_eligible else 0, r.composite_score), reverse=True)

        return ProviderRecommendationResponse(
            service_category=service_target,
            total_candidates=len(candidates),
            eligible_count=eligible_count,
            recommendations=ranked_list,
            ranking_criteria=self.weights
        )
