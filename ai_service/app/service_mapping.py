"""
Taxonomy mapping, safety critical keyword analysis, and dynamic explanation generation.
"""

from typing import Dict, List, Optional, Tuple
import re

# Direct bidirectional mapping to Flutter ServiceType names in app_user.dart
ML_TO_FLUTTER_CATEGORY: Dict[str, str] = {
    "battery_boost": "batteryBoost",
    "flat_tire": "flatTireChange",
    "fuel_delivery": "fuelDelivery",
    "mechanic": "mechanic",
    "tow_truck": "towTruck",
    "uncertain": "uncertain"
}

FLUTTER_TO_HUMAN_NAME: Dict[str, str] = {
    "batteryBoost": "Battery Boost (Jump Start)",
    "flatTireChange": "Flat Tire Replacement",
    "fuelDelivery": "Emergency Fuel Delivery",
    "mechanic": "On-Site Mechanic Repair",
    "towTruck": "Emergency Towing & Recovery",
    "uncertain": "Service Category Unclear"
}

# Category explanations explaining why a service is recommended
CATEGORY_EXPLANATIONS: Dict[str, str] = {
    "batteryBoost": (
        "The reported symptoms (such as clicking sounds, dim lights, or failure to crank) "
        "indicate a drained battery or starter power problem. A mobile technician can test the voltage "
        "and perform a jump start or battery check."
    ),
    "flatTireChange": (
        "Your description suggests a flat tyre, blowout, or loss of air pressure. "
        "A technician can assist with mounting your spare wheel or repairing the puncture on-site."
    ),
    "fuelDelivery": (
        "The symptoms indicate the vehicle has run out of fuel or the tank is dry. "
        "An emergency courier can deliver petrol or diesel directly to your location."
    ),
    "mechanic": (
        "The symptoms (engine overheating, unusual noises, belt/clutch issues, or fluid leaks) "
        "indicate a mechanical failure requiring on-site diagnostic inspection and roadside repair."
    ),
    "towTruck": (
        "The damage or breakdown (collision, broken axle, transmission lock, or ditch recovery) "
        "makes the vehicle unsafe or unable to drive. A flatbed or wheel-lift tow truck is recommended "
        "to transport your vehicle safely to a workshop."
    ),
    "uncertain": (
        "We could not definitively determine the exact service needed based on your description. "
        "Please select a category manually or review the follow-up questions below."
    )
}

# Contextual follow-up questions when uncertainty or ambiguity is detected
FOLLOW_UP_QUESTIONS: Dict[str, List[str]] = {
    "batteryBoost": [
        "Does the engine make a rapid clicking noise when you turn the key?",
        "Do your headlights or dashboard lights turn on, or are they completely dark?",
        "Has the vehicle been parked without being started for a long period?"
    ],
    "flatTireChange": [
        "Do you have a working spare tyre and wheel wrench in your boot?",
        "Is the tire visibly punctured, off the rim, or completely flat?",
        "Are the wheel lug nuts stuck or difficult to loosen?"
    ],
    "fuelDelivery": [
        "What type of fuel does your vehicle require (Petrol 92/95 or Auto/Super Diesel)?",
        "Approximately how many liters do you need to reach the nearest filling station?",
        "Did the engine sputter and stop right after the fuel gauge showed empty?"
    ],
    "mechanic": [
        "Is there steam or coolant leaking from under the hood?",
        "Can the vehicle shift gears, or is the clutch/transmission unresponsive?",
        "Is the engine making an unusual knocking, screeching, or grinding noise?"
    ],
    "towTruck": [
        "Has the vehicle been in a collision, or is any wheel/axle completely locked?",
        "Is the vehicle safely parked on the shoulder or blocking active roadway traffic?",
        "Do you need flatbed transport to a specific garage or repair center?"
    ],
    "uncertain": [
        "Does the engine turn over when you turn the key?",
        "Is any tyre flat or damaged?",
        "Did the vehicle run out of fuel or is there a mechanical noise?",
        "Is the vehicle capable of rolling, or does it need to be lifted and towed?"
    ]
}

# Safety critical patterns (fire, fuel leakage, smoke, brake failure)
SAFETY_HAZARD_PATTERNS = [
    (r"\b(flame|flames|fire|burning|smoke)\b", "FIRE / SMOKE DETECTED: Immediately evacuate the vehicle, turn off ignition if safe, move to a safe distance away from traffic, and do not attempt DIY repairs. If there are visible flames, call emergency services (119/110) immediately."),
    (r"\b(fuel leak|petrol spray|diesel leak|gasoline leak|smell of fuel)\b", "FUEL LEAK HAZARD: Avoid all open flames, sparks, or smoking. Do not turn the ignition key or start the engine. Evacuate passengers to the roadside and request emergency assistance."),
    (r"\b(brake failure|no brakes|pedal to the floor|cannot stop)\b", "BRAKE SYSTEM FAILURE: Do not attempt to drive the vehicle. Keep the vehicle in park/gear with the handbrake engaged on flat ground until qualified assistance arrives."),
    (r"\b(expressway|highway)\b.*\b(fast lane|middle of the road|traffic)\b", "HIGHWAY BREAKDOWN WARNING: Turn on your hazard lights immediately. Step outside on the passenger side away from traffic and wait behind the safety barrier.")
]


def check_safety_hazards(text: str) -> Optional[str]:
    """Inspects description for immediate roadside hazards."""
    lowered = text.lower()
    for pattern, alert in SAFETY_HAZARD_PATTERNS:
        if re.search(pattern, lowered):
            return alert
    return None
