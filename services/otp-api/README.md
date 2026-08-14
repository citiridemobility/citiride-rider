# CitiRide OTP API (Resend)

## Endpoints

- `GET /health`
- `POST /v1/otp/send` `{ "email": "user@example.com", "purpose": "login" | "wallet" | "reset_pin" }`
- `POST /v1/otp/verify` `{ "email": "user@example.com", "code": "123456", "purpose": "login" }`

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
```

4. Deploy this folder (Railway, etc.) and point the Flutter app at it:

```bash
# Optional override — release APKs already default to the Railway URL.
flutter run --dart-define=CITIRIDE_OTP_API_URL=https://your-otp-api.example.com
```

Release/profile builds use `https://otp-api-production-db79.up.railway.app` by default.
Debug builds still target the local API on port `8787`.
