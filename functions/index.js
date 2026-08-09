/**
 * Cloud Functions for the B2B Inventory & Order Management platform.
 *
 * All business-critical logic (invoice numbering, stock movement, notifications,
 * client provisioning) lives on the server so it cannot be tampered with from
 * the client apps.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const PARTY_EMAIL_DOMAIN = "party.b2bsaas.app";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
async function assertAdmin(auth) {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const snap = await db.collection("users").doc(auth.uid).get();
  const role = snap.exists ? snap.data().role : null;
  if (!["admin", "super_admin", "manager"].includes(role)) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  return snap.data();
}

// ---------------------------------------------------------------------------
// createClientUser — admin provisions a client (Party) login
// ---------------------------------------------------------------------------
exports.createClientUser = onCall(async (request) => {
  await assertAdmin(request.auth);
  // loginCode -> the Party ID the client types (becomes their email).
  // partyId   -> the parties/{id} document id (used by security rules to link
  //              the user to their party and orders).
  const { loginCode, partyId, password, name, companyId, phone } =
    request.data || {};
  if (!loginCode || !partyId || !password || !companyId) {
    throw new HttpsError(
      "invalid-argument",
      "loginCode, partyId, password, companyId required."
    );
  }

  const email = `${String(loginCode).toLowerCase()}@${PARTY_EMAIL_DOMAIN}`;
  const userRecord = await admin.auth().createUser({
    email,
    password,
    displayName: name || loginCode,
  });
  await admin.auth().setCustomUserClaims(userRecord.uid, {
    role: "client",
    companyId,
  });

  await db.collection("users").doc(userRecord.uid).set({
    companyId,
    role: "client",
    name: name || loginCode,
    email,
    phone: phone || null,
    partyId,
    status: "active",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { uid: userRecord.uid, email };
});

// ---------------------------------------------------------------------------
// provisionClientLogin — create OR reset a party's login (idempotent).
//
// Use for dealers created before Functions were deployed (their auth account
// never existed) or to reset a forgotten password. If the account exists the
// password is updated; otherwise it is created. The users/{uid} doc + custom
// claims are always (re)written so access is consistent.
// ---------------------------------------------------------------------------
exports.provisionClientLogin = onCall(async (request) => {
  await assertAdmin(request.auth);
  const { loginCode, partyId, password, name, companyId, phone } =
    request.data || {};
  if (!loginCode || !partyId || !password || !companyId) {
    throw new HttpsError(
      "invalid-argument",
      "loginCode, partyId, password, companyId required."
    );
  }

  const email = `${String(loginCode).toLowerCase()}@${PARTY_EMAIL_DOMAIN}`;
  let uid;
  try {
    const existing = await admin.auth().getUserByEmail(email);
    uid = existing.uid;
    await admin.auth().updateUser(uid, {
      password,
      displayName: name || loginCode,
    });
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      const rec = await admin.auth().createUser({
        email,
        password,
        displayName: name || loginCode,
      });
      uid = rec.uid;
    } else {
      throw new HttpsError("internal", e.message || "Could not provision login.");
    }
  }

  await admin.auth().setCustomUserClaims(uid, { role: "client", companyId });
  await db.collection("users").doc(uid).set(
    {
      companyId,
      role: "client",
      name: name || loginCode,
      email,
      phone: phone || null,
      partyId,
      status: "active",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { uid, email };
});

// ---------------------------------------------------------------------------
// onOrderStatusChange — deliver a PUSH to the party when the status changes.
//
// The app writes the rich in-app notification itself (with invoice numbers,
// rejection reasons, quantity diffs, etc.), so this trigger ONLY sends the FCM
// push to registered devices — it must NOT create a notifications doc, or the
// dealer would see every update twice.
// ---------------------------------------------------------------------------
exports.onOrderStatusChange = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;

    const usersSnap = await db
      .collection("users")
      .where("partyId", "==", after.partyId)
      .get();

    const tokens = [];
    usersSnap.forEach((u) => {
      const fcm = u.data().fcmTokens;
      if (Array.isArray(fcm)) tokens.push(...fcm);
    });

    if (tokens.length) {
      const ref = after.orderNo || after.invoiceNo || "";
      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: "Order update",
          body: `Your order ${ref} is now ${after.status}.`.replace("  ", " "),
        },
      });
    }
  }
);
