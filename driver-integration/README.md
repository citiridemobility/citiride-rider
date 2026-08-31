# CitiRide Driver App Integration Pack

Share this entire folder with the **React Native driver app** developer.

It documents how the driver app talks to the same Firebase project and OTP API as the rider Flutter app.

## Firebase project

| Item | Value |
|------|--------|
| Project ID | `citiride-d7743` |
| Auth | Email OTP → custom token (this pack) |
| Database | Cloud Firestore |
| Rider app | Flutter (`citiride-rider`) |
| Driver app | React Native (this pack) |

## What’s inside

| File | Purpose |
|------|---------|
| [AUTH.md](./AUTH.md) | Driver login + Firebase Auth UID |
| [RIDES.md](./RIDES.md) | Listen, accept, and progress ride requests |
| [firestore.types.ts](./firestore.types.ts) | Shared TypeScript types |
| [examples/auth.ts](./examples/auth.ts) | RN auth helpers (copy/adapt) |
| [examples/rides.ts](./examples/rides.ts) | RN ride matching helpers (copy/adapt) |

## Quick start for the RN developer

1. Add Firebase to the RN app with project `citiride-d7743` (`@react-native-firebase/app`, `auth`, `firestore`).
2. Implement email OTP using the **driver** endpoints in [AUTH.md](./AUTH.md).
3. After `signInWithCustomToken`, use `auth().currentUser.uid` as `driverId` everywhere.
4. Listen for `rides` where `status == "requested"`, then accept + stream GPS as in [RIDES.md](./RIDES.md).

## OTP API base URL

Production:

```text
https://otp-api-production-db79.up.railway.app
```

Driver endpoints (do **not** use the rider `/v1/otp/*` routes):

- `POST /v1/driver/otp/send`
- `POST /v1/driver/otp/verify`

## Driver Auth UID format

Driver UIDs are derived from email and prefixed with `drv_`:

```text
email: driver@example.com
uid:   drv_driver@example.com
```

(non-alphanumeric chars other than `@._+-` become `_`)

This keeps rider and driver Auth accounts separate even if the same email is used in both apps.

## Rules reminder

Firestore rules require the signed-in Auth UID to match `driverId` on accept/update. Signing in with the custom token from `/v1/driver/otp/verify` is mandatory before accepting rides.
