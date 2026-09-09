# CitiRide OTP API (Resend)

## Endpoints

### Rider (Flutter OTP)

- `GET /health`
- `POST /v1/otp/send` `{ "email": "user@example.com", "purpose": "login" | "wallet" | "reset_pin" | "withdraw" }`
- `POST /v1/otp/verify` `{ "email": "user@example.com", "code": "123456", "purpose": "login" }`  
  → may include `firebaseCustomToken` (`role: rider`)
- `POST /v1/wallet/congratulate` `{ "email": "user@example.com", "role": "rider" | "driver" }`  
  → sends wallet-created congratulations email (`walletEmail`: `sent` | `skipped` | `failed`)

### Rider wallet (Paystack)

- `GET /v1/wallet/status`
- `POST /v1/wallet/ensure` `{ email, fullName?, phone? }` → creates Paystack customer + dedicated virtual account
- `GET /v1/wallet/me` → balance + funding account
- `GET /v1/wallet/me/transactions`
- `GET /v1/wallet/banks`
- `POST /v1/wallet/bank/resolve` `{ accountNumber, bankCode }`
- `POST /v1/wallet/withdraw` `{ amount, bankCode, bankName, accountNumber, accountName? }`
- `POST /v1/paystack/webhook` ← configure this URL in Paystack Dashboard

Auth: `Authorization: Bearer <Firebase ID token>` (preferred).  
Dev fallback (`WALLET_ALLOW_USERID_FALLBACK=true`): `X-User-Id` header.

Env:

```env
PAYSTACK_SECRET_KEY=sk_live_xxx
PAYSTACK_DVA_BANK=wema-bank
```

Webhook URL example:

`https://otp-api-production-db79.up.railway.app/v1/paystack/webhook`

Listen for: `charge.success`, `transfer.success`, `transfer.failed`, `transfer.reversed`.

### Driver (React Native)

- `POST /v1/driver/otp/send` `{ "email": "driver@example.com" }`
- `POST /v1/driver/otp/verify` `{ "email": "driver@example.com", "code": "123456" }`  
  → may include `firebaseCustomToken` + `driverId` (`role: driver`, UID prefixed `drv_`) and `welcomeEmail` (`sent` | `skipped` | `failed`)

See `/driver-integration` in the rider repo for the RN handoff pack.

## Local run

```bash
cd services/otp-api
npm install
cp .env.example .env
npm run dev
```

Without `RESEND_API_KEY`, the API runs in **demo mode** and always issues code `968999` (or `OTP_DEMO_CODE`).

## Production

1. Create a Resend API key at https://resend.com/api-keys
2. Verify your sending domain at https://resend.com/domains
3. Set:

```env
RESEND_API_KEY=re_xxx
OTP_FROM_EMAIL=CitiRide <otp@yourdomain.com>
OTP_DEMO_MODE=false
FIREBASE_PROJECT_ID=citiride-d7743
FIREBASE_SERVICE_ACCOUNT_JSON={...service account json...}
```

4. Deploy from the **monorepo root**:

```bash
cd /path/to/citiride-rider
railway link --service otp-api   # once
railway up --service otp-api
```

**Critical Railway setting (otp-api service → Settings → Source):**

| Setting | Value |
|--------|--------|
| **Root Directory** | `services/otp-api` |
| **Config file** | `railway.toml` |

With Root Directory set to `services/otp-api`, Railway uploads only the Node API (not the Flutter app).  
If Root Directory is empty, the repo-root `nixpacks.toml` fallback is used — but **Option A is strongly recommended**.

`nixpacks.toml` forces a **Node-only** build so Railway does not run `dart pub get` on the Flutter project.

5. Point apps at the deployed URL:

```bash
# Rider (optional override)
flutter run --dart-define=CITIRIDE_OTP_API_URL=https://your-otp-api.example.com
```

Release/profile builds use `https://otp-api-production-db79.up.railway.app` by default.
Debug builds still target the local API on port `8787` when overridden.
