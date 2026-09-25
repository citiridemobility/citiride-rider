# CitiRide Paystack wallet — go-live checklist

## 1. Railway env (otp-api)

Set these on the `otp-api` service (never in Flutter):

- `PAYSTACK_SECRET_KEY` = your **live** secret key (`sk_live_...`) when going live
- For local/test QA use `sk_test_...`
- `PAYSTACK_DVA_BANK` = preferred DVA bank slug (`wema-bank` or `titan-paystack`; test uses `test-bank`)
- After rotating `PAYSTACK_SECRET_KEY` from test → live, reopen **Add money**. Existing wallets keep the old test DVA until otp-api assigns a live one (test customers/accounts are not valid in live).
- Test wallet balances are cleared on first live wallet load; they are not real Naira and cannot be spent after go-live.
- Keep existing `FIREBASE_SERVICE_ACCOUNT_JSON` so ID tokens and Firestore ledger work
- `CITIRIDE_COMMISSION_PERCENT` = platform take on each trip (default **20**)
- `CITIRIDE_PLATFORM_WALLET_ID` = ledger wallet that receives commission (default `citiride_platform`)

Optional (local/dev only):

- `WALLET_ALLOW_USERID_FALLBACK=true`

## 2. Paystack Dashboard

1. Enable **Dedicated Virtual Accounts** for the business (test and/or live).
2. Enable **Transfers** (and fund the Paystack balance for payouts).
3. Settings → API Keys & Webhooks → Webhook URL:

`https://otp-api-production-db79.up.railway.app/v1/paystack/webhook`

4. Subscribe to / confirm delivery of:
   - `charge.success` (wallet funding)
   - `transfer.success`
   - `transfer.failed`
   - `transfer.reversed`

## 3. Deploy

```bash
cd citiride-rider
railway up --service otp-api
```

## 4. App behaviour

- **Add money**: shows the rider’s assigned Paystack DVA; credits only after webhook verification (or after requery finds a missed deposit).
- **Withdraw**: PIN + email OTP, then Paystack Transfer; bank list comes from Paystack; account name is resolved before PIN.
- **Test helpers** (only when `PAYSTACK_SECRET_KEY` starts with `sk_test_`):
  - Add Money → **Simulate test deposit** credits ₦1,000 on the ledger immediately.
  - **I’ve sent the transfer** calls Paystack DVA requery.

## 5. Testing funding (important)

**Do not fund a test DVA from your real banking app.** Paystack test virtual accounts are not settled by normal NIP transfers.

Options in test:

1. Use **Paystack Demo Bank** (documented in Paystack’s dedicated virtual account test flow) to “transfer” into the test account number, **or**
2. Use **Simulate test deposit** in the rider Add Money screen.

After a real demo-bank payment, wait for the webhook, or tap **I’ve sent the transfer** to requery.

## 6. Testing withdrawals

1. Open Withdraw → pick a bank from the live Paystack list (searchable).
2. Enter a valid 10-digit NUBAN for that bank so resolve returns the account name.
3. In test mode, transfers use Paystack’s transfer test rules; your Paystack **test balance** must cover the payout.

## 7. Important

Confirm with Paystack that CitiRide’s wallet funding + withdrawal model is allowed for your live MCC/product terms before scaling.
