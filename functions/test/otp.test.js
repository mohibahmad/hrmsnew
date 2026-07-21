"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  emailDocumentId,
  generateOtp,
  generateResetToken,
  hashSecret,
  normalizeEmail,
  safeEqualHex,
} = require("../lib/otp");

test("normalizes email before deriving its private document id", () => {
  assert.equal(normalizeEmail(" User@Example.COM "), "user@example.com");
  assert.equal(
    emailDocumentId(" User@Example.COM "),
    emailDocumentId("user@example.com"),
  );
});

test("generates a six digit numeric OTP", () => {
  const otp = generateOtp();
  assert.match(otp, /^\d{6}$/);
});

test("hash comparison accepts only the matching secret", () => {
  const input = {
    email: "user@example.com",
    value: "123456",
    pepper: "test-pepper",
    purpose: "otp",
  };
  const expected = hashSecret(input);
  assert.equal(safeEqualHex(expected, hashSecret(input)), true);
  assert.equal(
    safeEqualHex(
      expected,
      hashSecret({...input, value: "654321"}),
    ),
    false,
  );
});

test("reset token has enough entropy and is URL safe", () => {
  const token = generateResetToken();
  assert.ok(token.length >= 40);
  assert.match(token, /^[A-Za-z0-9_-]+$/);
});
