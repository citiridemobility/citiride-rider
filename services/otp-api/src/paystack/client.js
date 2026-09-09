import crypto from 'node:crypto';

const PAYSTACK_BASE = 'https://api.paystack.co';

function secretKey() {
  return process.env.PAYSTACK_SECRET_KEY?.trim() || '';
}

export function hasPaystack() {
  return Boolean(secretKey());
}

export function isPaystackTestMode() {
  return secretKey().startsWith('sk_test');
}

export function preferredDvaBank() {
  return (
    process.env.PAYSTACK_DVA_BANK?.trim() ||
    (isPaystackTestMode() ? 'test-bank' : 'wema-bank')
  );
}

async function paystackRequest(path, { method = 'GET', body } = {}) {
  const key = secretKey();
  if (!key) {
    throw new Error('PAYSTACK_SECRET_KEY is not configured');
  }

  const res = await fetch(`${PAYSTACK_BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.status === false) {
    const message =
      data.message || data.data?.message || `Paystack HTTP ${res.status}`;
    const error = new Error(message);
    error.status = res.status;
    error.paystack = data;
    throw error;
  }
  return data;
}

export async function createCustomer({ email, firstName, lastName, phone }) {
  return paystackRequest('/customer', {
    method: 'POST',
    body: {
      email,
      first_name: firstName || undefined,
      last_name: lastName || undefined,
      phone: phone || undefined,
    },
  });
}

export async function fetchCustomerByEmail(email) {
  return paystackRequest(`/customer/${encodeURIComponent(email)}`);
}

export async function ensureCustomer({ email, firstName, lastName, phone }) {
  try {
    const existing = await fetchCustomerByEmail(email);
    return existing.data;
  } catch {
    const created = await createCustomer({
      email,
      firstName,
      lastName,
      phone,
    });
    return created.data;
  }
}

export async function createDedicatedVirtualAccount({
  customerCode,
  preferredBank,
  firstName,
  lastName,
  phone,
}) {
  return paystackRequest('/dedicated_account', {
    method: 'POST',
    body: {
      customer: customerCode,
      preferred_bank: preferredBank || preferredDvaBank(),
      first_name: firstName || undefined,
      last_name: lastName || undefined,
      phone: phone || undefined,
    },
  });
}

export async function listBanks({ country = 'NG', currency = 'NGN' } = {}) {
  return paystackRequest(
    `/bank?country=${encodeURIComponent(country)}&currency=${encodeURIComponent(currency)}`,
  );
}

export async function resolveAccountNumber({ accountNumber, bankCode }) {
  return paystackRequest(
    `/bank/resolve?account_number=${encodeURIComponent(accountNumber)}&bank_code=${encodeURIComponent(bankCode)}`,
  );
}

export async function createTransferRecipient({
  name,
  accountNumber,
  bankCode,
  currency = 'NGN',
}) {
  return paystackRequest('/transferrecipient', {
    method: 'POST',
    body: {
      type: 'nuban',
      name,
      account_number: accountNumber,
      bank_code: bankCode,
      currency,
    },
  });
}

export async function initiateTransfer({
  amountKobo,
  recipientCode,
  reference,
  reason,
}) {
  return paystackRequest('/transfer', {
    method: 'POST',
    body: {
      source: 'balance',
      amount: amountKobo,
      recipient: recipientCode,
      reference,
      reason: reason || 'CitiRide wallet withdrawal',
    },
  });
}

export async function verifyTransaction(reference) {
  return paystackRequest(`/transaction/verify/${encodeURIComponent(reference)}`);
}

/**
 * Ask Paystack to re-check a DVA for missed transfers.
 * If found, Paystack sends charge.success to the webhook asynchronously.
 */
export async function requeryDedicatedAccount({
  accountNumber,
  providerSlug,
  date,
}) {
  const params = new URLSearchParams({
    account_number: String(accountNumber),
    provider_slug: String(providerSlug),
  });
  if (date) {
    params.set('date', String(date));
  }
  return paystackRequest(`/dedicated_account/requery?${params.toString()}`);
}

export function verifyPaystackSignature(rawBody, signatureHeader) {
  const key = secretKey();
  if (!key || !signatureHeader) return false;
  const hash = crypto
    .createHmac('sha512', key)
    .update(rawBody)
    .digest('hex');
  return hash === signatureHeader;
}
