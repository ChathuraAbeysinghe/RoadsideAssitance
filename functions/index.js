const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// Must be the same region as your Firestore database.
const REGION = "asia-south1";

// Distance in km between two lat/lng points (haversine).
function distanceKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

function validGeo(g) {
  return (
    g &&
    typeof g.latitude === "number" &&
    typeof g.longitude === "number" &&
    (g.latitude !== 0 || g.longitude !== 0)
  );
}

// Same names as serviceTypeTitle() in the app.
const SERVICE_TITLES = {
  towTruck: "Emergency Towing",
  mechanic: "Mechanic",
  fuelDelivery: "Fuel Delivery",
  flatTireChange: "Flat Tire",
  batteryBoost: "Battery Boosting",
};

exports.notifyProvidersOfRequest = onDocumentWritten(
  { document: "service_requests/{requestId}", region: REGION },
  async (event) => {
    const requestId = event.params.requestId;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after || after.status !== "pending") return;

    const before = event.data.before.exists ? event.data.before.data() : null;
    const newRadius = after.searchRadiusKm ?? 5;
    const oldRadius =
      before && before.status === "pending" ? before.searchRadiusKm ?? 0 : 0;

    // Same pending request updated for some other reason: nothing to do.
    if (before && before.status === "pending" && newRadius <= oldRadius) return;

    console.log(
      `request ${requestId}: ${after.serviceType}, radius ${oldRadius} -> ${newRadius} km`,
    );

    const pickup = after.pickup;
    if (!validGeo(pickup)) {
      console.log(`request ${requestId}: invalid pickup, stopping`);
      return;
    }

    const usersSnap = await db
      .collection("users")
      .where("isAvailable", "==", true)
      .where("services", "array-contains", after.serviceType)
      .get();

    console.log(
      `request ${requestId}: ${usersSnap.size} available provider(s) offer ${after.serviceType}`,
    );

    const title = `New ${SERVICE_TITLES[after.serviceType] || "assistance"} request`;
    const body = after.pickupAddress || "A driver near you needs help";

    const jobs = usersSnap.docs.map(async (userDoc) => {
      const uid = userDoc.id;
      const user = userDoc.data();

      if (uid === after.customerUid) {
        console.log(`skip ${uid}: this is the customer who made the request`);
        return;
      }

      const tokens = user.fcmTokens || [];
      if (tokens.length === 0) {
        console.log(`skip ${uid}: no fcmTokens saved`);
        return;
      }

      // Service-specific location first, then the live location.
      let base = null;
      const psSnap = await db
        .collection("providerServices")
        .where("providerUid", "==", uid)
        .where("serviceType", "==", after.serviceType)
        .where("isActive", "==", true)
        .limit(1)
        .get();
      if (!psSnap.empty) {
        const geo = psSnap.docs[0].data().locationGeo;
        if (validGeo(geo)) base = geo;
      }
      if (!base && validGeo(user.currentLocation)) base = user.currentLocation;
      if (!base) {
        console.log(`skip ${uid}: no location`);
        return;
      }

      const km = distanceKm(
        base.latitude, base.longitude, pickup.latitude, pickup.longitude,
      );
      const inRange = km <= newRadius && (oldRadius === 0 || km > oldRadius);
      if (!inRange) {
        console.log(
          `skip ${uid}: ${km.toFixed(1)} km away, outside ${oldRadius}-${newRadius} km`,
        );
        return;
      }

      const res = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: { type: "new_request", requestId },
        android: {
          priority: "high",
          notification: { channelId: "incoming_requests", sound: "default" },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default" } },
        },
      });
      console.log(
        `sent to ${uid} (${km.toFixed(1)} km): ${res.successCount} ok, ${res.failureCount} failed`,
      );

      // Drop tokens that are no longer valid.
      const dead = [];
      res.responses.forEach((r, i) => {
        if (r.error) {
          console.log(`token error for ${uid}: ${r.error.code}`);
        }
        const code = r.error && r.error.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          dead.push(tokens[i]);
        }
      });
      if (dead.length) {
        await userDoc.ref.update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead),
        });
      }
    });

    await Promise.all(
      jobs.map((p) => p.catch((e) => console.error("notify failed", e))),
    );
  },
);