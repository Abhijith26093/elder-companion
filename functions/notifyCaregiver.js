const crypto = require("crypto");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const twilio = require("twilio");

const db = admin.firestore();

const PHONE_PATTERN = /^\+[1-9]\d{9,14}$/;
const SMS_LOGS_COLLECTION = "sms_logs";
const SMS_COOLDOWN_MS = 15 * 60 * 1000;
const REGION = process.env.AUTH_API_REGION || "us-central1";

exports.notifyCaregiver = onDocumentWritten(
    {
      document: "users/{userId}",
      region: REGION,
    },
    async (event) => {
      const afterSnapshot = event.data.after;
      const beforeSnapshot = event.data.before;
      const afterData = afterSnapshot.exists ? afterSnapshot.data() : null;
      const beforeData = beforeSnapshot.exists ? beforeSnapshot.data() : null;

      if (!afterData) {
        return null;
      }

      if (!afterData.caregiverNumber) {
        console.log(`No caregiver number found for user ${event.params.userId}.`);
        return null;
      }

      let caregiverNumber;
      try {
        caregiverNumber = normalizePhone(afterData.caregiverNumber);
      } catch (error) {
        console.error(`Invalid caregiver number for user ${event.params.userId}:`, error.message);
        await writeSmsLog({
          userId: event.params.userId,
          caregiverNumber: String(afterData.caregiverNumber),
          name: afterData.name,
          status: "skipped_invalid_number",
          errorMessage: error.message,
        });
        return null;
      }

      const previousNumber = normalizeOptionalPhone(beforeData && beforeData.caregiverNumber);
      if (previousNumber === caregiverNumber) {
        console.log(`Caregiver number unchanged for user ${event.params.userId}. Skipping SMS.`);
        return null;
      }

      const existingLog = await getLatestSmsLog(event.params.userId, caregiverNumber);
      if (existingLog && isWithinCooldown(existingLog.lastSentAt)) {
        console.log(`Skipping duplicate SMS for user ${event.params.userId} within cooldown window.`);
        return null;
      }

      const messageBody = buildMessage(afterData);

      try {
        const client = getTwilioClient();
        const response = await client.messages.create({
          body: messageBody,
          from: getRequiredEnv("TWILIO_PHONE_NUMBER"),
          to: caregiverNumber,
        });

        console.log(`SMS sent to caregiver ${caregiverNumber}: ${response.sid}`);
        await writeSmsLog({
          userId: event.params.userId,
          caregiverNumber,
          name: afterData.name,
          status: "sent",
          messageBody,
          providerMessageId: response.sid,
          providerStatus: response.status || "queued",
        });
      } catch (error) {
        console.error(`SMS sending failed for user ${event.params.userId}:`, error);
        await writeSmsLog({
          userId: event.params.userId,
          caregiverNumber,
          name: afterData.name,
          status: "failed",
          messageBody,
          errorMessage: formatTwilioError(error),
        });
      }

      return null;
    },
);

function normalizePhone(value) {
  const input = String(value || "").trim();
  if (!PHONE_PATTERN.test(input)) {
    throw new Error("Provide caregiverNumber in E.164 format, for example +919207027558.");
  }
  return input;
}

function normalizeOptionalPhone(value) {
  if (!value) {
    return null;
  }

  try {
    return normalizePhone(value);
  } catch (_) {
    return null;
  }
}

function buildMessage(data) {
  const name = typeof data.name === "string" && data.name.trim() ?
    data.name.trim() :
    "The elderly user";
  return `Mitra Alert: ${name} may need assistance.`;
}

function getTwilioClient() {
  return twilio(
      getRequiredEnv("TWILIO_ACCOUNT_SID"),
      getRequiredEnv("TWILIO_AUTH_TOKEN"),
  );
}

function getRequiredEnv(key) {
  const value = process.env[key];
  if (!value || !value.trim()) {
    throw new Error(`Missing required Twilio env value: ${key}`);
  }
  return value.trim();
}

async function getLatestSmsLog(userId, caregiverNumber) {
  const snapshot = await db
      .collection(SMS_LOGS_COLLECTION)
      .doc(logIdFor(userId, caregiverNumber))
      .get();

  return snapshot.exists ? snapshot.data() : null;
}

function isWithinCooldown(timestamp) {
  if (!timestamp || typeof timestamp.toMillis !== "function") {
    return false;
  }

  return Date.now() - timestamp.toMillis() < SMS_COOLDOWN_MS;
}

async function writeSmsLog({
  userId,
  caregiverNumber,
  name,
  status,
  messageBody,
  providerMessageId,
  providerStatus,
  errorMessage,
}) {
  const logRef = db.collection(SMS_LOGS_COLLECTION).doc(logIdFor(userId, caregiverNumber));

  await logRef.set(
      {
        userId,
        name: name || null,
        caregiverNumber,
        status,
        messageBody: messageBody || null,
        provider: "twilio",
        providerMessageId: providerMessageId || null,
        providerStatus: providerStatus || null,
        errorMessage: errorMessage || null,
        lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
  );
}

function logIdFor(userId, caregiverNumber) {
  const digest = crypto
      .createHash("sha256")
      .update(`${userId}:${caregiverNumber}`)
      .digest("hex");
  return `caregiver_sms_${digest}`;
}

function formatTwilioError(error) {
  if (!error) {
    return "Unknown Twilio error.";
  }

  const code = error.code ? `Code ${error.code}: ` : "";
  return `${code}${error.message || String(error)}`;
}
