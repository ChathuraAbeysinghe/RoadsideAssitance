# RoadsideAssist 🚗🛠️
### Vehicle Breakdown and Roadside Assistance Request Mobile App
**IT3060 Human Computer Interaction (HCI) | Final Consolidated Project**  
**SLIIT — Faculty of Computing | Year 3, Semester 2 (2026)**  
**Group Number:** WD_23 &nbsp;|&nbsp; **Group Name:** WD_2.1  

---

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore%20%7C%20Auth-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com/)
[![OpenStreetMap](https://img.shields.io/badge/Maps-OpenStreetMap%20%7C%20OSRM-7EBC6F?logo=openstreetmap&logoColor=white)](https://www.openstreetmap.org/)
[![License](https://img.shields.io/badge/License-Academic-blue.svg)]()

---

## 📌 Project Overview

**RoadsideAssist** is a real-time mobile application engineered to connect stranded motorists across Sri Lanka with certified nearby roadside service providers (mechanics, tow truck operators, fuel delivery, and tire/battery technicians).

Grounded in Human-Computer Interaction (HCI) methodologies across Milestones 01 to 03, the app addresses key roadside breakdown challenges identified through user research (53 driver survey responses and 5 provider interviews): **lack of automated GPS location sharing**, **unpredictable wait times**, and **lack of upfront pricing transparency**.

---

## 📱 Core Feature Modules

### 1. Driver (Customer) Experience
* **Phone OTP Authentication:** Seamless, passwordless mobile registration and secure verification via Firebase Auth.
* **Vehicle Profile Management:** Full CRUD management of personal vehicles (Type, Make, Model, License Plate) stored in Firestore.
* **Fault-Specific Service Requests:** Custom emergency forms tailored for:
  * 🛞 Flat Tire Replacement
  * 🔋 Battery Jump-Start
  * ⛽ Emergency Fuel Delivery
  * 🚚 Flatbed & Wheel-Lift Towing
  * 🔧 On-site Mechanical Repair
* **Interactive GPS & Map Pinning:** Automatic device GPS detection and interactive OpenStreetMap (flutter_map) location picker with Nominatim reverse-geocoding.
* **Transparent Pricing & Cost Estimates:** Upfront itemized fare calculations based on service type, base fee, and distance rates before booking confirmation.
* **Live Provider Tracking:** Dynamic polyline route tracking powered by the OSRM routing engine, showing real-time provider movement, ETA calculation, and direct Call/SMS buttons.
* **Nearby Service Centers:** Discovery of physical garages, auto repair centers, and service stations near the user's current location.
* **Activity & History:** Multi-tab tracking of Ongoing, Completed, and Cancelled service requests.

---

### 2. Service Provider Dashboard & Operations
* **Provider Home Dashboard:** Real-time operational command center featuring:
  * Floating online/offline availability toggle (automatically disabled when on an active job).
  * Today's Summary analytics (Earnings, Completed Jobs, Rating, Total Requests).
  * Active Job Banner for immediate resumption of in-progress tasks.
  * Distance-filtered incoming request cards with live countdown timers, vehicle info, and route previews.
* **Two-Tab Service Management (`My Services`):**
  * **Services Tab:** Manage mobile service listings (Towing, Mobile Mechanic, Fuel Delivery, etc.) with custom vehicle types, plate numbers, and Pause/Restart toggles.
  * **Service Stations Tab:** Register and manage physical workshops, garages, and service stations with operating hours, categories, contact details, and offered facilities.
* **Incoming Request Evaluation:** Dedicated request inspection screen with route polyline, distance, estimated travel time, customer notes, and atomic Accept/Decline actions.
* **Unified Job Workspace (Job Details Page):**
  * Four-stage operational pipeline: **Accepted → On the Way → Arrived → In Progress → Complete Job**.
  * Dynamic map tracking customer coordinates and route progress.
  * Customer communication card (Phone & SMS triggers).
  * External navigation launch via Google Maps.
  * Itemized completion modal and digital billing summary.
* **Provider Job History:** Complete historical records grouped by service category with status tags and financial breakdowns.
* **Push Notifications & Alerts:** Real-time notification inbox with unread count badges, auto-read on open, and background Firebase Cloud Messaging (FCM) alerts.

---

## 🛠️ Technology Stack & Architecture

| Layer | Technologies Used | Description |
|:---|:---|:---|
| **Frontend UI** | Flutter (Dart 3.x), Material Design 3 | High-performance, cross-platform mobile UI with custom animations and responsive layouts. |
| **Backend & Database** | Google Firebase Cloud Firestore | NoSQL document database utilizing real-time snapshot listeners and atomic transactions. |
| **Authentication** | Firebase Authentication | Phone OTP authentication for driver and service provider verification. |
| **Mapping & Navigation** | `flutter_map`, `latlong2`, OpenStreetMap | Offline-capable, tile-based mapping without paid Google Maps API lock-in. |
| **Routing & Geocoding** | OSRM (Open Source Routing Machine), Nominatim | Real-time driving route calculation, polyline decoding, and reverse-geocoding. |
| **Device Geolocation** | `geolocator` | High-accuracy device GPS tracking and coordinate streaming. |
| **Notifications** | `firebase_messaging`, `flutter_local_notifications` | Push notification service with high-importance Android notification channels and background handlers. |

---

## 📂 Project Directory Structure

```text
RoadsideAssitance/
├── android/                             # Android native configuration & manifests
├── assets/                              # App assets
│   ├── icon/                            # Custom service icons (tow, mechanic, fuel, etc.)
│   └── images/                          # Visual graphics and placeholders
├── lib/
│   ├── main.dart                        # Application entry point & service initializers
│   ├── firebase_options.dart            # Firebase configuration
│   ├── entities/                        # Core domain data models
│   │   ├── app_user.dart                # User profiles (Driver / Provider)
│   │   ├── service_request.dart         # Breakdown request model
│   │   ├── service_center.dart          # Nearby service center model
│   │   └── vehicle.dart                 # Vehicle registration model
│   ├── features/
│   │   ├── _share/                      # Reusable components & animated navigation bar
│   │   ├── auth/                        # Welcome, Phone Login, OTP & Profile Setup
│   │   ├── home/                        # Driver Home screen & service discovery
│   │   ├── request_service/             # Request forms, location selection & summary
│   │   ├── live_tracking/               # Driver live tracking & provider tracking
│   │   ├── nearby_centers/              # Service center discovery, details & receipts
│   │   ├── requests/                    # Customer activity history (Ongoing/Completed/Cancelled)
│   │   ├── vehicles/                    # Customer vehicle management (CRUD)
│   │   └── service_provider/            # Complete Service Provider Module
│   │       ├── models/                  # ProviderService & ProviderStation models
│   │       ├── services/                # ProviderRepository (Firestore streams & transactions)
│   │       └── screens/                 # Dashboard, My Services, Job Details, History, Notifications
│   └── services/                        # App-wide singleton services
│       ├── provider_location_service.dart
│       ├── customer_location_sharer.dart
│       ├── incoming_request_listner.dart
│       └── push_notification_service.dart
└── pubspec.yaml                         # Dependency definitions and asset manifests
```

---

## 🚀 Getting Started

### Prerequisites
* **Flutter SDK:** Version `3.13.1` or higher ([Install Flutter](https://docs.flutter.dev/get-started/install))
* **Dart SDK:** Version `3.1.0` or higher
* **Android Studio / VS Code** with Flutter & Dart extensions
* **Physical Android Device** or Android Emulator (Android 8.0+ / API level 26+ recommended)
* **Google Firebase Account** (with Cloud Firestore and Firebase Authentication enabled)

### Installation Steps

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ChathuraAbeysinghe/RoadsideAssitance.git
   cd RoadsideAssitance
   ```

2. **Install project dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase:**
   * Place your `google-services.json` inside the `android/app/` directory.
   * Ensure Phone Authentication and Cloud Firestore rules are deployed in your Firebase console.

4. **Run the application:**
   ```bash
   flutter run
   ```

---

## 🧪 Testing & Usability Validation

### Functional Test Execution
A comprehensive matrix of **37 functional test cases (TC01–TC37)** was designed and executed against the live application covering Authentication, Vehicle Management, Provider Listings, Request Pipelines, Live Tracking, and Security Rules:
* **Total Test Cases:** 37
* **Passed:** 32 (86.5%)
* **Scoped Out / Deferred:** 5 (Mutual rating backend, automated recommendation ML, SMS SOS broadcast, offline request queue)

### Usability Testing (SUS Benchmark)
Moderated usability evaluations were conducted with 5 representative target participants (motorcyclists, car drivers, three-wheeler drivers, and proxy providers) following the Brooke (1996) System Usability Scale methodology:
* **Average SUS Score:** **82.5 / 100** *(Grade A — "Excellent Usability")*
* Key refinements implemented in response to testing feedback:
  1. Enlarged primary action buttons above the fold.
  2. Clear contextual guidance when no providers are available nearby.
  3. Animated, frictionless bottom navigation across all provider workspaces.

---

## 👥 Group WD_23 Contribution & Workload Distribution

| Student ID | Student Name | Assigned Core Modules & Implementation Scope |
|:---|:---|:---|
| **IT23829206** | **Abeysinghe A M C P** | **Complete Service Provider Module:** Provider Home Dashboard, Two-Tab Service Management (`Services` & `Service Stations`), Incoming Request Detail & Radar, Provider Job Details Workspace, Job History (My Jobs), Provider Notifications, Settings & Animated Navigation. |
| **IT23833166** | **Thennakoon T M T P B** | Driver Home layout, Service Provider Details Screen, and Usability Testing execution. |
| **IT23838802** | **Wimalasingha T K P** | Driver Home integration, Fault-specific Service Request Forms, and Request Summary / Confirmation. |
| **IT23823716** | **Lakshan J M P** | Welcome flow, Phone OTP Authentication, Complete Profile, and Find Service Provider listing. |

---

## 📄 Academic Disclaimer & License
This project was developed strictly for academic evaluation under the **IT3060 Human Computer Interaction** module at the **Sri Lanka Institute of Information Technology (SLIIT)**.  
All third-party icons, packages, and map tiles remain the property of their respective creators.
