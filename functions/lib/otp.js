"use strict";

const crypto = require("node:crypto");

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function emailDocumentId(email) {
  return crypto.createHash("sha256").update(normalizeEmail(email)).digest("hex");
}

function generateOtp() {
  return crypto.randomInt(100000, 1000000).toString();
}

function generateResetToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function hashSecret({ email, value, pepper, purpose }) {
  return crypto
    .createHmac("sha256", pepper)
    .update(`${purpose}:${normalizeEmail(email)}:${value}`)
    .digest("hex");
}

function safeEqualHex(left, right) {
  if (typeof left !== "string" || typeof right !== "string") return false;
  const leftBuffer = Buffer.from(left, "hex");
  const rightBuffer = Buffer.from(right, "hex");
  if (leftBuffer.length === 0 || leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

module.exports = {
  emailDocumentId,
  generateOtp,
  generateResetToken,
  hashSecret,
  normalizeEmail,
  safeEqualHex,
};
