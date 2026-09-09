CitiRide – Paystack Integration Setup

Technical specification for rider wallet funding, ride payment settlement, CitiRide commission, driver earnings, and rider/driver bank withdrawals.

# 1\. Core Payment Architecture

CitiRide should use Paystack as the payment infrastructure for bank-facing collections and transfers, while CitiRide maintains the internal rider and driver wallet ledgers.

- Riders fund their CitiRide wallet through Paystack-supported collection methods, preferably a dedicated virtual account where approved.
- CitiRide credits the rider wallet only after server-side verification of the Paystack transaction/webhook.
- When a driver ends a trip, the rider releases payment for the completed ride.
- The full ride fare is deducted from the rider's CitiRide wallet.
- CitiRide's commission is separated from the fare and recorded as platform revenue.
- The remaining amount is credited to the driver's CitiRide earnings wallet.
- Drivers initiate withdrawals; CitiRide then sends approved amounts to their verified bank accounts through Paystack Transfers.
- Riders can also initiate withdrawals of eligible wallet balances to their verified bank accounts.

# 2\. Rider Wallet Funding

1\. Rider selects Fund Wallet in the Flutter app.

2\. CitiRide displays the rider's assigned Paystack virtual account details, where available.

3\. Rider transfers money from their bank account to the displayed account.

4\. Paystack processes the incoming payment.

5\. Paystack sends a webhook to the CitiRide backend.

6\. Backend verifies the webhook and transaction details.

7\. CitiRide creates a wallet-credit ledger transaction.

8\. Rider's available wallet balance is increased and the transaction appears in history.

The mobile app must never determine that a deposit is successful. Only the backend should credit the wallet after verification.

# 3\. Ride Payment and Commission

After the driver ends the trip, the rider reviews and releases payment. The backend then settles the ride from the rider's wallet.

| Example                           | Amount |
| --------------------------------- | ------ |
| Ride fare                         | ₦5,000 |
| CitiRide commission (example 10%) | ₦500   |
| Driver net earnings               | ₦4,500 |

The commission percentage must be configurable on the backend and should not be hard-coded in the Flutter app.

# 4\. Ride Settlement Sequence

1\. Driver ends the trip.

2\. Backend confirms the final fare.

3\. Rider releases/confirms payment.

4\. Backend verifies sufficient available wallet balance.

5\. Backend locks/reserves the required amount to prevent double spending.

6\. Backend debits the rider's wallet by the full fare.

7\. Backend records CitiRide's commission.

8\. Backend credits the driver's net earnings wallet.

9\. Ride is marked financially settled.

10\. Rider and driver receive updated transaction/earnings records.

# 5\. Paystack Settlement of CitiRide Commission

CitiRide's commission should be recorded as platform revenue. If Paystack's approved settlement/split-payment arrangement supports the required flow, the relevant Paystack settlement mechanism can be configured so CitiRide receives its commission. The exact commercial and technical settlement method should be confirmed with Paystack for CitiRide's live account before implementation.

# 6\. Driver Earnings Wallet

- Completed rides credit the driver's net earnings after CitiRide's commission.
- Driver earnings remain within the CitiRide earnings ledger until the driver requests a withdrawal.
- Pending, disputed, reversed, or locked amounts must not be available for withdrawal.
- Every earnings movement must have a unique transaction reference.
- The driver can withdraw only up to the available balance.

# 7\. Driver Withdrawal

1\. Driver selects Withdraw.

2\. Driver selects a verified bank account and enters an amount.

3\. Backend checks the available earnings balance.

4\. Backend creates a unique withdrawal reference and reserves/debits the amount.

5\. Backend initiates a Paystack transfer to the driver's verified transfer recipient.

6\. Paystack processes the transfer.

7\. CitiRide receives the transfer status webhook.

8\. Successful transfers are marked successful; failed/reversed transfers are reconciled and funds restored according to the transaction state.

# 8\. Rider Withdrawal

1\. Rider adds and verifies a personal bank account.

2\. CitiRide creates/stores the corresponding Paystack transfer recipient.

3\. Rider requests a withdrawal.

4\. Backend checks the eligible available wallet balance.

5\. Backend creates a unique withdrawal reference and reserves/debits the amount.

6\. Backend initiates the Paystack transfer.

7\. Paystack sends the transfer status webhook.

8\. CitiRide marks the withdrawal successful, failed, or reversed and reconciles the wallet accordingly.

CitiRide should define which wallet balances are withdrawable. Promotional credits or restricted balances may require separate rules.

# 9\. Bank Account Verification

Before withdrawals are enabled, CitiRide should verify the rider/driver bank account and store the Paystack transfer recipient code. Sensitive banking information should be encrypted and access-controlled.

# 10\. Recommended Database/Ledger Structure

**wallets:** id, user_id, wallet_type, available_balance, pending_balance, currency, status

**wallet_transactions:** id, wallet_id, user_id, reference, type, amount, balance_before, balance_after, status, provider, provider_reference, metadata, created_at

**bank_accounts:** id, user_id, bank_code, bank_name, account_number_encrypted, account_name, paystack_recipient_code, status

**withdrawals:** id, user_id, wallet_id, reference, amount, fee, recipient_id, paystack_transfer_code, status, failure_reason, created_at

**ride_settlements:** id, ride_id, rider_id, driver_id, fare, commission, driver_earnings, currency, status, settled_at

# 11\. Critical Security Controls

- Never put the Paystack secret key in the Flutter application. Keep it only on the backend.
- Verify Paystack webhook signatures before processing events.
- Use idempotency and unique references so duplicate webhooks cannot credit or debit a wallet twice.
- Use database transactions/locking for wallet balance changes.
- Never trust wallet balances, fare values, or payment status supplied by the mobile app.
- Encrypt sensitive bank-account data and restrict access.
- Use HTTPS for all communication.
- Implement authentication, authorization, rate limiting, fraud controls, and audit logs.
- Maintain reconciliation between CitiRide's ledger and Paystack transactions/transfers.
- Use clear states such as pending, successful, failed, reversed, refunded, and disputed.

# 12\. System Architecture

Flutter Rider/Driver Apps → CitiRide Backend → Wallet & Earnings Ledger → Paystack API → Banks

The backend is the source of truth for wallet balances, ride settlement, commission calculation, withdrawal authorization, and transaction status. Paystack should be accessed from the backend, not directly with secret credentials from Flutter.

# 13\. End-to-End Flows

**Rider funding:** Rider → Bank Transfer → Paystack Virtual Account → Paystack Webhook → CitiRide Backend → Rider Wallet

**Ride settlement:** Driver Ends Trip → Rider Releases Payment → Rider Wallet Debit → CitiRide Commission Recorded → Driver Earnings Credited

**Driver withdrawal:** Driver Requests Withdrawal → CitiRide Validates/Reserves Funds → Paystack Transfer → Driver Bank → Webhook → Reconciliation

**Rider withdrawal:** Rider Requests Withdrawal → CitiRide Validates/Reserves Funds → Paystack Transfer → Rider Bank → Webhook → Reconciliation

# 14\. Important Paystack and Regulatory Note

This document describes the proposed technical architecture. CitiRide should confirm with Paystack that its specific wallet, transportation, commission, collection, and withdrawal model is permitted under CitiRide's live merchant category and Paystack's current product terms. CitiRide should also obtain appropriate legal and regulatory advice before operating a wallet that holds and allows withdrawal of monetary balances.

# Conclusion

This model separates CitiRide's internal accounting from Paystack's payment infrastructure. Paystack handles bank-facing collections and transfers, while CitiRide controls wallet balances, ride settlement, commission accounting, driver earnings, withdrawals, and reconciliation.