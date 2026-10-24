# Roadside Assistance Vehicle Fault Symptom Dataset

## Overview
This dataset contains natural language problem descriptions from motorists experiencing roadside breakdowns. Each entry is annotated with one of the primary roadside service categories, vehicle type context, data provenance (real/survey vs synthetic), and safety criticality flags.

## Taxonomy & Category Mapping
The dataset maps directly to the application's domain `ServiceType`:

| ML Category Label | Application `ServiceType` | Typical Breakdown Symptoms |
|---|---|---|
| `battery_boost` | `batteryBoost` | Dead battery, alternator failure, rapid starter clicking, dim lights, jump start request |
| `flat_tire` | `flatTireChange` | Puncture from nail/debris, blowout, bead leak, stuck lug nuts, spare tire replacement |
| `fuel_delivery` | `fuelDelivery` | Empty fuel tank, sputtering due to fuel starvation, emergency petrol/diesel delivery |
| `mechanic` | `mechanic` | Radiator overheating, brake loss, clutch/gearbox issues, belt snaps, unusual engine knocks |
| `tow_truck` | `towTruck` | Severe collision damage, immobilized vehicle, broken axle, ditch recovery, flatbed towing |
| `uncertain` | `uncertain` | Ambiguous input ("car acts weird", "hello"), insufficient details, unidentifiable problem |

## Schema
- `id` (int): Unique identifier
- `text` (string): Driver natural language breakdown description
- `category` (string): Target classification category
- `vehicle_type` (string): Contextual vehicle type (`car`, `motorbike`, `van`, `threeWheeler`, `truck`, `bus`)
- `is_synthetic` (boolean): `false` for real survey responses collected from Sri Lankan drivers; `true` for curated synthetic linguistic augmentations
- `safety_critical` (boolean): `true` if the symptom indicates immediate fire, smoke, collision, or life-safety danger

## Licensing & Provenance
- **License**: MIT / Academic Research Use
- **Origin**: Initial sample derived from the IT3060 HCI Roadside Assistance driver surveys (53 respondents) and expanded with synthetic variations covering regional and conversational English.

## Limitations & Retraining Guidelines
- **Limitations**: Synthetic variations were generated to prevent class imbalance. Real-world driver queries may contain spelling errors, Sinhala/Tamil transliterations, or regional slang not fully captured in the initial development dataset.
- **Retraining**: When real, consented driver request logs accumulate in production Firestore, append them to `vehicle_faults_dataset.json` and re-run `python training/train_model.py`.
