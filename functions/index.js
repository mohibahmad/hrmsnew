"use strict";

const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {
  FieldValue,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");
const {logger} = require("firebase-functions");
const {defineSecret} = require("firebase-functions/params");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {
  emailDocumentId,
  generateOtp,
  generateResetToken,
  hashSecret,
  normalizeEmail,
  safeEqualHex,
} = require("./lib/otp");

initializeApp();

const resendApiKey = defineSecret("RESEND_API_KEY");
const otpPepper = defineSecret("PASSWORD_RESET_OTP_PEPPER");
const passwordResetFrom = defineSecret("PASSWORD_RESET_FROM");

const REGION = "us-central1";
const OTP_LIFETIME_MS = 10 * 60 * 1000;
const VERIFIED_TOKEN_LIFETIME_MS = 5 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const SEND_WINDOW_MS = 60 * 60 * 1000;
const MAX_SENDS_PER_WINDOW = 5;
const MAX_VERIFY_ATTEMPTS = 5;
const GENERIC_SENT_RESPONSE = {
  sent: true,
  expiresInSeconds: OTP_LIFETIME_MS / 1000,
  resendAfterSeconds: RESEND_COOLDOWN_MS / 1000,
};

function requireEmail(data) {
  const email = normalizeEmail(data?.email);
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  if (!valid) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  return email;
}

function requireOtp(data) {
  const otp = String(data?.otp || "").trim();
  if (!/^\d{6}$/.test(otp)) {
    throw new HttpsError("invalid-argument", "Enter the 6-digit OTP.");
  }
  return otp;
}

function requirePassword(data) {
  const password = String(data?.newPassword || "");
  if (password.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "Password must be at least 6 characters.",
    );
  }
  if (password.length > 128) {
    throw new HttpsError("invalid-argument", "Password is too long.");
  }
  return password;
}

function invalidOtpError() {
  return new HttpsError(
    "invalid-argument",
    "The OTP is invalid or has expired.",
  );
}

async function sendOtpEmail({email, otp}) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey.value()}`,
      "Content-Type": "application/json",
      "User-Agent": "hrms-firebase-password-reset/1.0",
    },
    body: JSON.stringify({
      from: passwordResetFrom.value(),
      to: [email],
      subject: "Your HRMS password reset code",
      text: `Your HRMS password reset code is ${otp}. It expires in 10 minutes. If you did not request this, you can ignore this email.`,
      html: `
        <div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#0f172a">
          <h2 style="color:#0247c4">Reset your HRMS password</h2>
          <p>Enter this verification code in the HRMS app:</p>
          <div style="font-size:32px;font-weight:700;letter-spacing:8px;padding:18px 20px;background:#f1f5f9;border-radius:8px;text-align:center">${otp}</div>
          <p>This code expires in 10 minutes and can be used only once.</p>
          <p style="color:#64748b;font-size:13px">If you did not request a password reset, ignore this email.</p>
        </div>
      `,
    }),
  });

  if (!response.ok) {
    const responseText = await response.text();
    logger.error("Password reset email provider rejected the request", {
      status: response.status,
      response: responseText.slice(0, 500),
    });
    throw new Error("Email delivery failed");
  }
}

exports.requestPasswordResetOtp = onCall(
  {
    region: REGION,
    secrets: [resendApiKey, otpPepper],
  },
  async (request) => {
    const email = requireEmail(request.data);
    let user;
    try {
      user = await getAuth().getUserByEmail(email);
    } catch (error) {
      if (error?.code === "auth/user-not-found") {
        return GENERIC_SENT_RESPONSE;
      }
      logger.error("Unable to look up password reset account", error);
      throw new HttpsError("internal", "Unable to send the OTP right now.");
    }

    const hasPasswordProvider = user.providerData.some(
      (provider) => provider.providerId === "password",
    );
    if (!hasPasswordProvider || user.disabled) return GENERIC_SENT_RESPONSE;

    const now = Date.now();
    const otp = generateOtp();
    const documentRef = getFirestore()
      .collection("passwordResetOtps")
      .doc(emailDocumentId(email));

    const rateLimitResult = await getFirestore().runTransaction(
      async (transaction) => {
        const snapshot = await transaction.get(documentRef);
        const current = snapshot.data() || {};
        const lastSentAt = current.lastSentAt?.toMillis?.() || 0;
        if (now - lastSentAt < RESEND_COOLDOWN_MS) {
          return {allowed: false, reason: "cooldown"};
        }

        const priorWindowStartedAt =
          current.sendWindowStartedAt?.toMillis?.() || 0;
        const inCurrentWindow = now - priorWindowStartedAt < SEND_WINDOW_MS;
        const sendCount = inCurrentWindow ? Number(current.sendCount || 0) : 0;
        if (sendCount >= MAX_SENDS_PER_WINDOW) {
          return {allowed: false, reason: "hourly-limit"};
        }

        transaction.set(documentRef, {
          uid: user.uid,
          email,
          otpHash: hashSecret({
            email,
            value: otp,
            pepper: otpPepper.value(),
            purpose: "otp",
          }),
          expiresAt: Timestamp.fromMillis(now + OTP_LIFETIME_MS),
          attempts: 0,
          lastSentAt: Timestamp.fromMillis(now),
          sendWindowStartedAt: Timestamp.fromMillis(
            inCurrentWindow ? priorWindowStartedAt : now,
          ),
          sendCount: sendCount + 1,
          resetTokenHash: FieldValue.delete(),
          verifiedExpiresAt: FieldValue.delete(),
          consumedAt: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {allowed: true};
      },
    );

    if (!rateLimitResult.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        rateLimitResult.reason === "cooldown"
          ? "Please wait before requesting another OTP."
          : "Too many OTP requests. Try again later.",
      );
    }

    try {
      await sendOtpEmail({email, otp});
    } catch (error) {
      await documentRef.delete().catch(() => {});
      logger.error("Failed to deliver password reset OTP", error);
      throw new HttpsError("internal", "Unable to send the OTP right now.");
    }

    return GENERIC_SENT_RESPONSE;
  },
);

exports.verifyPasswordResetOtp = onCall(
  {
    region: REGION,
    secrets: [otpPepper],
  },
  async (request) => {
    const email = requireEmail(request.data);
    const otp = requireOtp(request.data);
    const now = Date.now();
    const documentRef = getFirestore()
      .collection("passwordResetOtps")
      .doc(emailDocumentId(email));
    const resetToken = generateResetToken();

    const result = await getFirestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(documentRef);
      if (!snapshot.exists) return {verified: false};
      const data = snapshot.data();
      const expiresAt = data.expiresAt?.toMillis?.() || 0;
      const attempts = Number(data.attempts || 0);
      if (expiresAt <= now || attempts >= MAX_VERIFY_ATTEMPTS) {
        transaction.delete(documentRef);
        return {verified: false};
      }

      const suppliedHash = hashSecret({
        email,
        value: otp,
        pepper: otpPepper.value(),
        purpose: "otp",
      });
      if (!safeEqualHex(data.otpHash, suppliedHash)) {
        transaction.update(documentRef, {
          attempts: attempts + 1,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {verified: false};
      }

      transaction.update(documentRef, {
        otpHash: FieldValue.delete(),
        resetTokenHash: hashSecret({
          email,
          value: resetToken,
          pepper: otpPepper.value(),
          purpose: "reset-token",
        }),
        verifiedExpiresAt: Timestamp.fromMillis(
          now + VERIFIED_TOKEN_LIFETIME_MS,
        ),
        verifiedAt: FieldValue.serverTimestamp(),
        attempts: 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {verified: true};
    });

    if (!result.verified) throw invalidOtpError();
    return {
      verified: true,
      resetToken,
      expiresInSeconds: VERIFIED_TOKEN_LIFETIME_MS / 1000,
    };
  },
);

exports.confirmPasswordResetOtp = onCall(
  {
    region: REGION,
    secrets: [otpPepper],
  },
  async (request) => {
    const email = requireEmail(request.data);
    const newPassword = requirePassword(request.data);
    const resetToken = String(request.data?.resetToken || "");
    if (resetToken.length < 40) throw invalidOtpError();

    const now = Date.now();
    const documentRef = getFirestore()
      .collection("passwordResetOtps")
      .doc(emailDocumentId(email));
    const result = await getFirestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(documentRef);
      if (!snapshot.exists) return {allowed: false};
      const data = snapshot.data();
      const verifiedExpiresAt = data.verifiedExpiresAt?.toMillis?.() || 0;
      const suppliedHash = hashSecret({
        email,
        value: resetToken,
        pepper: otpPepper.value(),
        purpose: "reset-token",
      });
      if (
        data.consumedAt ||
        verifiedExpiresAt <= now ||
        !safeEqualHex(data.resetTokenHash, suppliedHash)
      ) {
        return {allowed: false};
      }
      transaction.update(documentRef, {
        consumedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {allowed: true, uid: data.uid};
    });

    if (!result.allowed || !result.uid) throw invalidOtpError();
    try {
      await getAuth().updateUser(result.uid, {password: newPassword});
    } catch (error) {
      logger.error("Failed to update password after OTP verification", error);
      await documentRef.update({
        consumedAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      }).catch((releaseError) => {
        logger.error("Failed to release password reset token", releaseError);
      });
      if (error?.code === "auth/invalid-password") {
        throw new HttpsError(
          "failed-precondition",
          "The new password does not meet the password requirements.",
          {reason: "weak-password"},
        );
      }
      throw new HttpsError("internal", "Unable to reset the password.");
    }

    // The password is already changed at this point. Revocation and reset
    // document cleanup are best-effort housekeeping and must not turn a
    // successful password change into a false failure shown to the user.
    await getAuth().revokeRefreshTokens(result.uid).catch((error) => {
      logger.warn("Password changed but token revocation failed", error);
    });
    await documentRef.delete().catch((error) => {
      logger.warn("Password changed but reset document cleanup failed", error);
    });

    return {reset: true};
  },
);
