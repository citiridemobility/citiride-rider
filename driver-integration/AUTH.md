# Driver authentication (React Native)

## Flow

```text
1. Driver enters email
2. App POST /v1/driver/otp/send
3. Driver enters 6-digit code
4. App POST /v1/driver/otp/verify
5. Response includes firebaseCustomToken + driverId
6. App: auth().signInWithCustomToken(firebaseCustomToken)
7. auth().currentUser.uid === driverId  (use this everywhere)
```

## Endpoints

Base URL: `https://otp-api-production-db79.up.railway.app`

### Send OTP

`POST /v1/driver/otp/send`

```json
{ "email": "driver@example.com" }
```

Success:

```json
{
  "ok": true,
  "email": "driver@example.com",
  "purpose": "driver_login",
  "role": "driver",
  "expiresInMs": 600000,
  "demoMode": false
}
```

In demo mode (`OTP_DEMO_MODE=true` or no Resend key), response also includes `"demoCode": "968999"`.

### Verify OTP

`POST /v1/driver/otp/verify`

```json
{
  "email": "driver@example.com",
  "code": "123456"
}
```

Success:

```json
{
  "ok": true,
  "email": "driver@example.com",
  "purpose": "driver_login",
  "role": "driver",
  "verified": true,
  "driverId": "drv_driver@example.com",
  "firebaseCustomToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

If `firebaseCustomToken` is missing, Firebase Admin is not configured on the OTP API — rides cannot be accepted until that is fixed.

## React Native sign-in

```ts
import auth from '@react-native-firebase/auth';
import firestore from '@react-native-firebase/firestore';

export async function completeDriverLogin(params: {
  email: string;
  firebaseCustomToken: string;
  driverId: string;
}) {
  const credential = await auth().signInWithCustomToken(
    params.firebaseCustomToken,
  );
  const uid = credential.user.uid;

  // Must match OTP response driverId / rules expect this as rides.driverId
  if (uid !== params.driverId) {
    throw new Error(`UID mismatch: auth=${uid} expected=${params.driverId}`);
  }

  await firestore().collection('drivers').doc(uid).set(
    {
      email: params.email.trim().toLowerCase(),
      driverId: uid,
      authProvider: 'email_otp',
      role: 'driver',
      updatedAt: firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return uid;
}
```

## Session restore

On app launch, check `auth().currentUser`. If present, reuse `currentUser.uid` as `driverId`. No need to re-OTP until signed out.

```ts
import auth from '@react-native-firebase/auth';

export function getDriverIdOrNull(): string | null {
  return auth().currentUser?.uid ?? null;
}
```

## Sign out

```ts
await auth().signOut();
```

## Do not use rider OTP routes

| App | Send | Verify |
|-----|------|--------|
| Rider (Flutter) | `/v1/otp/send` | `/v1/otp/verify` |
| Driver (RN) | `/v1/driver/otp/send` | `/v1/driver/otp/verify` |

Rider tokens mint `role: "rider"` UIDs without the `drv_` prefix. Driver tokens mint `role: "driver"` UIDs with `drv_`.
