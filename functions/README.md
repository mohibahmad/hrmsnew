# HRMS password-reset OTP functions

The Flutter app calls three `us-central1` callable functions:

1. `requestPasswordResetOtp`
2. `verifyPasswordResetOtp`
3. `confirmPasswordResetOtp`

OTP values are six digits, expire after 10 minutes, are never stored in plain
text, allow at most five verification attempts, and are protected by resend
and hourly limits. A verified OTP is exchanged for a one-time reset token that
expires after five minutes.

## One-time Firebase setup

Cloud Functions deployment requires the Firebase project to use the Blaze
plan. Create a Resend API key and verify the sender domain, then run from the
project root:

```sh
firebase functions:secrets:set RESEND_API_KEY
firebase functions:secrets:set PASSWORD_RESET_OTP_PEPPER
firebase deploy --only functions
```

When deployment asks for `PASSWORD_RESET_FROM`, enter a verified sender such
as `HRMS <security@example.com>`. The OTP pepper should be a long random value;
for example, generate one with `openssl rand -base64 48` and paste it into the
secret prompt. Never add either secret to source control.

Add this rule inside the existing Firestore
`match /databases/{database}/documents` block before deploying rules. Admin SDK
calls from the functions bypass it, while app clients remain unable to inspect
or modify reset sessions:

```text
match /passwordResetOtps/{document} {
  allow read, write: if false;
}
```

For additional abuse protection, enable Firebase App Check for the app and set
`enforceAppCheck: true` on the three callable functions after every supported
platform is registered.

For local emulation, put development-only values in
`functions/.secret.local` and use the Firebase Emulator Suite.
