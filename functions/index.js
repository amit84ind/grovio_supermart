const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.setPartnerRole = functions.https.onCall(async (data, context) => {
  const targetUid = data.uid;

  if (!targetUid) {
    throw new functions.https.HttpsError("invalid-argument", "UID is required.");
  }

  await admin.auth().setCustomUserClaims(targetUid, { role: "partner" });

  return { message: `User ${targetUid} has been successfully assigned the 'partner' role.` };
});