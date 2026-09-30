# CitiRide Paystack wallet — go-live checklist

## 1. Railway env (otp-api)

Set these on the `otp-api` service (never in Flutter):

- `PAYSTACK_SECRET_KEY` = your **live** secret key (`sk_live_...`) when going live
- For local/test QA use `sk_test_...`
- `PAYSTACK_DVA_BANK` = preferred DVA bank slug (`wema-bank` or `titan-paystack`; test uses `test-bank`)
- After rotating `PAYSTACK_SECRET_KEY` from test → live, reopen **Add money**. Existing wallets keep the old test DVA until otp-api assigns a live one (test customers/accounts are not valid in live).
- Test wallet balances are cleared on first live wallet load; they are not real Naira and cannot be spent after go-live.
- Pull to refresh on Wallet home (or **I’ve sent the transfer** on Add money) syncs successful DVA payments from Paystack if the live webhook was missed. Funding the Paystack *business* balance does not credit a rider/driver wallet — users must transfer to the Wema/Titan virtual account shown in Add money.
- Keep existing `FIREBASE_SERVICE_ACCOUNT_JSON` so ID tokens and Firestore ledger work
- `CITIRIDE_COMMISSION_PERCENT` = platform take on each trip (default **20**)
- `CITIRIDE_PLATFORM_WALLET_ID` = ledger wallet that receives commission (default `citiride_platform`)

Optional (local/dev only):

- `WALLET_ALLOW_USERID_FALLBACK=true`

## 2. Paystack Dashboard

1. Enable **Dedicated Virtual Accounts** for the business (test and/or live).
2. Enable **Transfers** and make sure the Paystack **Available Balance** can cover payouts. DVA deposits credit the in-app wallet immediately, but withdrawals spend this Paystack balance (plus the transfer fee). If auto-settlement sends collections to your business bank, turn it off or keep a payout float, or riders will see “not enough balance” even with wallet funds.
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
- **Withdraw**: PIN + email OTP, then Paystack Transfer; bank list comes from Paystack; account name is resolved before PIN. Collection fees on DVA/NIP are taken from the deposit (Paystack’s “customer pays fees” setting does not apply to virtual accounts). Rider withdrawals also debit the Paystack transfer fee from the wallet.
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

In-app wallet balance is **not** what Paystack Transfers spend. DVA deposits credit the rider ledger immediately, then payouts are sent from the **Paystack business available balance** (plus ~₦10 transfer fee). If a rider has ₦200 in the app and withdraw ₦100 fails with “not enough balance”, Paystack’s payout balance is empty or unsettled — often because auto-settlement already moved the DVA money to the business bank.

1. Paystack Dashboard → check **Available Balance** (Transfers), not the customer’s DVA history.
2. Turn **off automatic settlement** to the business bank (or raise the threshold) so DVA deposits stay in Paystack for payouts, **or** keep a Paystack payout float.
3. Open Withdraw → pick a bank from the live Paystack list (searchable).
4. Enter a valid 10-digit NUBAN for that bank so resolve returns the account name.
5. In test mode, transfers use Paystack’s transfer test rules; your Paystack **test balance** must cover the payout.

## 7. Important

Confirm with Paystack that CitiRide’s wallet funding + withdrawal model is allowed for your live MCC/product terms before scaling.
