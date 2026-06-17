# HRMS

A cross-platform Human Resource Management System built with Flutter and
Firebase. Runs on macOS, Windows, Linux, iOS, Android, and web.

Features: worker management, attendance, payroll, expenses, time-off, assets,
holidays, and a metrics dashboard. Auth supports email/password, Google, Apple,
and an anonymous guest mode (which uses local sample data).

## Getting started

```bash
flutter pub get
flutter run            # add -d macos / -d chrome / -d ios as needed
```

Requires Flutter SDK matching `environment.sdk` in `pubspec.yaml`.

## Architecture

- **Auth** — `lib/services/auth_service.dart` wraps `firebase_auth` and the
  Google/Apple sign-in flows.
- **Data** — `lib/services/firestore_service.dart` is the single Firestore
  gateway. Every user owns one document at `hrms_user/{userKey}` (userKey is the
  lowercased email, or the uid when no email exists). All HRMS records live in
  subcollections beneath that document, so users are naturally isolated.
- **Guest mode** — anonymous users see `lib/services/dummy_data.dart` instead of
  Firestore; nothing they do is persisted remotely.
- **Screens** — `lib/screens/*` subscribe directly to the Firestore streams
  exposed by `FirestoreService`.

## Security

### Firebase configuration files

The following files are intentionally committed:

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`

These contain **client-side** Firebase configuration (project IDs, app IDs, and
the public API key). They are designed to ship inside the app binary and are not
secrets. Your data is protected by the security rules below, **not** by hiding
these files.

Optional hardening: in the Google Cloud Console, restrict the browser/API key to
your app's bundle IDs and the Firebase APIs it actually uses.

### Firestore & Storage rules

Security rules are version-controlled and must be deployed for the app to be
safe in production:

- `firestore.rules` — locks every document to its owner. A user can only read or
  write `hrms_user/{userKey}` (and its subcollections) when `userKey` matches
  their own email/uid. Everything else is denied.
- `storage.rules` — uploads require an authenticated user and are constrained by
  size and content type (profile pics ≤ 5 MB images; worker documents ≤ 15 MB).
- `firestore.indexes.json` — composite index definitions (currently none
  required).

Deploy them with the Firebase CLI:

```bash
firebase deploy --only firestore:rules,storage,firestore:indexes
```

> **Important:** until these rules are deployed, the database may be running in
> open test mode. Deploying `firestore.rules` and `storage.rules` is the single
> most important step before exposing the app to real users.

### Deleted accounts

Account deletion is a soft delete (`isDeleted: true` on the owner document). On
sign-in the app calls `FirestoreService.isCurrentUserDeleted()`, which reads the
user's **own** document — this keeps the security rules strict (no
collection-wide queries are required).

## Project layout

```
lib/
  main.dart                 App entry, Firebase init, window setup
  firebase_options.dart     Generated Firebase config
  screens/                  UI, one file per feature
  services/                 auth_service, firestore_service, preferences, dummy_data
  utils/                    Dialogs, snackbars
  widgets/                  Shared widgets
firestore.rules             Firestore security rules
storage.rules               Cloud Storage security rules
firestore.indexes.json      Firestore composite indexes
```
