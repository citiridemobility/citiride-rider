import {
  assignDedicatedVirtualAccount,
  createTransferRecipient,
  ensureCustomer,
  fetchCustomer,
  fetchDedicatedAccountById,
  fetchDedicatedAccounts,
  initiateTransfer,
  isPaystackTestMode,
  listPaystackTransactions,
  paystackMode,
  requeryDedicatedAccount,
  resolveAccountNumber,
  verifyTransaction,
} from '../paystack/client.js';
import {
  fromKobo,
  getFirestore,
  newReference,
  platformWalletId,
  splitFareKobo,
  toKobo,
} from './util.js';

const WALLETS = 'wallets';
const TXNS = 'wallet_transactions';
const WITHDRAWALS = 'withdrawals';
const PROCESSED = 'paystack_events';

function splitName(fullName = '') {
  const parts = String(fullName).trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return { firstName: 'Rider', lastName: 'User' };
  if (parts.length === 1) return { firstName: parts[0], lastName: 'User' };
  return {
    firstName: parts[0],
    lastName: parts.slice(1).join(' '),
  };
}

function serializeWallet(doc) {
  const data = doc.data() || {};
  return {
    userId: doc.id,
    walletType: data.walletType || 'rider',
    availableBalance: fromKobo(data.availableBalanceKobo || 0),
    pendingBalance: fromKobo(data.pendingBalanceKobo || 0),
    currency: data.currency || 'NGN',
    status: data.status || 'active',
    fundingAccount: data.fundingAccount || null,
    paystackCustomerCode: data.paystackCustomerCode || null,
    paystackCustomerId: data.paystackCustomerId || null,
    testMode: isPaystackTestMode(),
    updatedAt: data.updatedAt?.toDate?.()?.toISOString?.() || null,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isSuccessStatus(status) {
  const value = String(status || '').toLowerCase();
  return !value || value === 'success' || value === 'successful' || value === 'paid';
}

function chargeFromUnknown(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }
  if (payload.reference && Number(payload.amount || 0) > 0) {
    return payload;
  }
  if (payload.transaction) {
    return chargeFromUnknown(payload.transaction);
  }
  if (Array.isArray(payload.data)) {
    return payload.data.map(chargeFromUnknown).find(Boolean) || null;
  }
  if (payload.data && typeof payload.data === 'object') {
    return chargeFromUnknown(payload.data);
  }
  if (Array.isArray(payload.transactions)) {
    return payload.transactions.map(chargeFromUnknown).find(Boolean) || null;
  }
  return null;
}

/**
 * Ask Paystack to look for missed DVA deposits, credit any that already exist,
 * then return the current wallet.
 */
export async function requeryWalletFunding(userId) {
  const wallet = await getOrCreateWallet(userId);
  const funding = wallet.fundingAccount || {};
  const accountNumber = String(funding.accountNumber || '').trim();
  const providerSlug = String(
    funding.bankSlug || preferredProviderSlug(funding.bankName) || '',
  ).trim();

  if (!accountNumber || !providerSlug) {
    throw new Error('Funding account is not ready yet. Open Add Money again.');
  }

  const before = Number(wallet.availableBalance || 0);
  await syncPaystackTopUps(userId, wallet);

  try {
    const recovered = await requeryDedicatedAccount({
      accountNumber,
      providerSlug,
      date: new Date().toISOString().slice(0, 10),
    });
    const charge = chargeFromUnknown(recovered);
    if (charge) {
      await handleChargeSuccess({ data: charge }, { userId });
    }
  } catch (error) {
    console.warn('Paystack DVA requery failed', error.message || error);
  }

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const current = await getOrCreateWallet(userId);
    await syncPaystackTopUps(userId, current);
    const updated = await getOrCreateWallet(userId);
    if (Number(updated.availableBalance || 0) > before) {
      return updated;
    }
    if (attempt < 3) {
      await sleep(1200);
    }
  }

  return getOrCreateWallet(userId);
}

function receiverAccountNumber(txn) {
  const auth = txn?.authorization || {};
  const metadata = txn?.metadata || {};
  return String(
    auth.receiver_bank_account_number ||
      auth.receiver_account_number ||
      auth.account_number ||
      metadata.receiver_account_number ||
      metadata.account_number ||
      '',
  ).trim();
}

function looksLikeWalletFunding(txn, accountNumber) {
  const channel = String(
    txn?.channel || txn?.authorization?.channel || '',
  ).toLowerCase();
  const receiver = receiverAccountNumber(txn);
  if (accountNumber && receiver && receiver === accountNumber) {
    return true;
  }
  return (
    channel.includes('dedicated') ||
    channel === 'bank_transfer' ||
    channel === 'dedicated_nuban'
  );
}

/**
 * Credit successful Paystack charges that never arrived via webhook.
 */
async function syncPaystackTopUps(userId, wallet) {
  const { rows, customerId, customerCode } = await collectPaystackCharges(wallet);
  if (
    (customerId && customerId !== wallet.paystackCustomerId) ||
    (customerCode && customerCode !== wallet.paystackCustomerCode)
  ) {
    const db = getFirestore();
    await db.collection(WALLETS).doc(userId).set(
      {
        ...(customerId ? { paystackCustomerId: customerId } : {}),
        ...(customerCode ? { paystackCustomerCode: customerCode } : {}),
        updatedAt: new Date(),
      },
      { merge: true },
    );
  }

  let credited = 0;

  for (const row of rows) {
    try {
      const result = await handleChargeSuccess({ data: row }, { userId });
      if (result?.ok) {
        credited += 1;
      }
    } catch (error) {
      console.warn(
        'sync Paystack top-up failed',
        row?.reference,
        error.message || error,
      );
    }
  }

  return { credited };
}

async function collectPaystackCharges(wallet) {
  const accountNumber = String(wallet.fundingAccount?.accountNumber || '').trim();
  const dedicatedAccountId = wallet.fundingAccount?.dedicatedAccountId || null;
  let customerId = wallet.paystackCustomerId || null;
  let customerCode = String(wallet.paystackCustomerCode || '').trim() || null;
  const seen = new Set();
  const rows = [];

  const addRows = (list) => {
    for (const row of Array.isArray(list) ? list : []) {
      const reference = String(row?.reference || '').trim();
      if (!reference || seen.has(reference)) {
        continue;
      }
      if (row?.status && !isSuccessStatus(row.status)) {
        continue;
      }
      if (Number(row?.amount || 0) <= 0) {
        continue;
      }
      if (
        accountNumber &&
        receiverAccountNumber(row) &&
        receiverAccountNumber(row) !== accountNumber
      ) {
        continue;
      }
      seen.add(reference);
      rows.push(row);
    }
  };

  const applyDva = (dva) => {
    if (!dva) return;
    if (dva.customer?.id) {
      customerId = dva.customer.id;
    }
    if (dva.customer?.customer_code) {
      customerCode = dva.customer.customer_code;
    }
    addRows(dva.transactions);
    addRows(dva.assignment?.transactions);
  };

  if (dedicatedAccountId) {
    try {
      const dedicated = await fetchDedicatedAccountById(dedicatedAccountId);
      applyDva(dedicated.data);
    } catch (error) {
      console.warn('fetch dedicated account failed', error.message || error);
    }
  }

  try {
    const dvas = await fetchDedicatedAccounts({
      accountNumber: accountNumber || undefined,
    });
    const dvaRows = Array.isArray(dvas.data)
      ? dvas.data
      : dvas.data
        ? [dvas.data]
        : [];
    const dva =
      dvaRows.find((row) => String(row?.account_number || '') === accountNumber) ||
      dvaRows[0];
    applyDva(dva);
  } catch (error) {
    console.warn('fetch dedicated accounts failed', error.message || error);
  }

  if (!customerId && customerCode) {
    try {
      const customer = await fetchCustomer(customerCode);
      customerId = customer.data?.id || customerId;
      customerCode = customer.data?.customer_code || customerCode;
    } catch (error) {
      console.warn('fetch Paystack customer failed', error.message || error);
    }
  }

  const from = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
  const queries = [];
  if (customerId) {
    queries.push(
      listPaystackTransactions({
        customer: customerId,
        status: 'success',
        perPage: 50,
        from,
      }),
    );
  }
  if (customerCode) {
    queries.push(
      listPaystackTransactions({
        customer: customerCode,
        status: 'success',
        perPage: 50,
        from,
      }),
    );
  }

  const results = await Promise.all(
    queries.map((request) => request.catch((error) => {
      console.warn('list Paystack transactions failed', error.message || error);
      return { data: [] };
    })),
  );
  for (const result of results) {
    addRows(result.data);
  }

  return { rows, customerId, customerCode };
}

function preferredProviderSlug(bankName) {
  const name = String(bankName || '').toLowerCase();
  if (name.includes('test')) return 'test-bank';
  if (name.includes('wema')) return 'wema-bank';
  if (name.includes('titan')) return 'titan-paystack';
  return isPaystackTestMode() ? 'test-bank' : '';
}

function storedFundingMode(funding) {
  const explicit = String(funding?.paystackMode || '').toLowerCase();
  if (explicit === 'live' || explicit === 'test') {
    return explicit;
  }
  const slug = String(funding?.bankSlug || '').toLowerCase();
  const name = String(funding?.bankName || '').toLowerCase();
  if (slug === 'test-bank' || name.includes('test')) {
    return 'test';
  }
  return null;
}

function fundingAccountNeedsAssignment(wallet) {
  const funding = wallet.fundingAccount;
  if (!funding?.accountNumber) {
    return true;
  }
  const stored = storedFundingMode(funding);
  return Boolean(stored && stored !== paystackMode());
}

function isTestLedgerTxn(data) {
  return (
    data?.testEra === true ||
    data?.metadata?.simulated === true ||
    data?.metadata?.channel === 'test_credit' ||
    String(data?.providerReference || '').startsWith('test_') ||
    String(data?.title || '').toLowerCase().includes('test wallet')
  );
}

function txnCreatedMs(data) {
  return data?.createdAt?.toMillis?.() || 0;
}

/**
 * Test Paystack credits live on the same Firestore ledger as live money.
 * After rotating to sk_live, drop leftover test balance (and hide test-era
 * history) so the wallet only shows real Naira.
 */
async function alignWalletLedgerMode(ref, snap) {
  const current = paystackMode();
  const data = snap.data() || {};
  if (data.paystackLedgerMode === current) {
    return snap;
  }

  const db = getFirestore();
  const userId = snap.id;
  const now = new Date();
  const assignedMs = Date.parse(data.fundingAccount?.assignedAt || '') || 0;
  const liveFunding = storedFundingMode(data.fundingAccount) === 'live';

  const txnSnap = await db
    .collection(TXNS)
    .where('userId', '==', userId)
    .get();

  let liveNetKobo = 0;
  const staleRefs = [];
  for (const doc of txnSnap.docs) {
    const row = doc.data() || {};
    const created = txnCreatedMs(row);
    const liveEra =
      liveFunding &&
      assignedMs > 0 &&
      created >= assignedMs &&
      !isTestLedgerTxn(row);
    if (liveEra) {
      liveNetKobo += Number(row.amountKobo || 0);
      continue;
    }
    if (!row.testEra) {
      staleRefs.push(doc.ref);
    }
  }

  const currentAvailable = Number(data.availableBalanceKobo || 0);
  let nextBalanceKobo = currentAvailable;
  if (current === 'live') {
    if (liveNetKobo > 0) {
      nextBalanceKobo = liveNetKobo;
    } else if (staleRefs.length > 0) {
      nextBalanceKobo = 0;
    }
  }

  await ref.set(
    {
      availableBalanceKobo: current === 'live' ? nextBalanceKobo : currentAvailable,
      pendingBalanceKobo: current === 'live' ? 0 : data.pendingBalanceKobo || 0,
      paystackLedgerMode: current,
      updatedAt: now,
    },
    { merge: true },
  );

  for (let i = 0; i < staleRefs.length; i += 400) {
    const batch = db.batch();
    for (const txnRef of staleRefs.slice(i, i + 400)) {
      batch.set(txnRef, { testEra: true, updatedAt: now }, { merge: true });
    }
    await batch.commit();
  }

  return ref.get();
}

/**
 * Test-key only: credit the ledger without a real bank transfer.
 * Use this when Paystack demo-bank funding is inconvenient.
 */
export async function simulateTestDeposit(userId, amountNaira = 1000) {
  if (!isPaystackTestMode()) {
    throw new Error('Test deposits are only available with a Paystack test secret key.');
  }

  const amountKobo = toKobo(amountNaira);
  if (!Number.isFinite(amountKobo) || amountKobo < 10000) {
    throw new Error('Minimum test deposit is ₦100');
  }

  await getOrCreateWallet(userId);
  const reference = newReference('test_dep');
  await creditWalletTx({
    userId,
    amountKobo,
    reference,
    providerReference: `test_${Date.now()}`,
    title: 'Test Wallet Top Up',
    metadata: { simulated: true, channel: 'test_credit' },
  });

  return getOrCreateWallet(userId);
}

export async function getOrCreateWallet(
  userId,
  { email, fullName, phone, walletType } = {},
) {
  const db = getFirestore();
  const ref = db.collection(WALLETS).doc(userId);
  const snap = await ref.get();
  if (snap.exists) {
    const aligned = await alignWalletLedgerMode(ref, snap);
    return serializeWallet(aligned);
  }

  const now = new Date();
  const payload = {
    userId,
    walletType: ['driver', 'platform'].includes(walletType)
      ? walletType
      : 'rider',
    availableBalanceKobo: 0,
    pendingBalanceKobo: 0,
    currency: 'NGN',
    status: 'active',
    email: (email || '').trim().toLowerCase() || null,
    fullName: fullName || null,
    phone: phone || null,
    fundingAccount: null,
    paystackCustomerCode: null,
    paystackLedgerMode: paystackMode(),
    createdAt: now,
    updatedAt: now,
  };
  await ref.set(payload);
  return serializeWallet({ id: userId, data: () => payload });
}

export async function ensureFundingAccount(userId, profile = {}) {
  const db = getFirestore();
  const ref = db.collection(WALLETS).doc(userId);
  let wallet = await getOrCreateWallet(userId, profile);
  if (!fundingAccountNeedsAssignment(wallet)) {
    return wallet;
  }

  const email = (profile.email || wallet.email || '').trim().toLowerCase();
  if (!email) {
    throw new Error('Email is required to create a funding account');
  }

  const { firstName, lastName } = splitName(
    profile.fullName || wallet.fullName || email.split('@')[0],
  );
  const phone = profile.phone || wallet.phone || undefined;

  const customer = await ensureCustomer({
    email,
    firstName,
    lastName,
    phone,
  });
  const customerCode = customer.customer_code || customer.id;
  const dva = await assignDedicatedVirtualAccount({
    customerCode,
    firstName,
    lastName,
    phone,
  });

  const account = dva.data || {};
  const fundingAccount = {
    accountName: account.account_name || null,
    accountNumber: account.account_number || null,
    bankName: account.bank?.name || null,
    bankSlug: account.bank?.slug || null,
    currency: account.currency || 'NGN',
    provider: 'paystack',
    paystackMode: paystackMode(),
    dedicatedAccountId: account.id || null,
    assignedAt: new Date().toISOString(),
  };

  const switchingToLive =
    paystackMode() === 'live' && storedFundingMode(wallet.fundingAccount) !== 'live';

  await ref.set(
    {
      email,
      fullName: profile.fullName || `${firstName} ${lastName}`.trim(),
      phone: phone || null,
      paystackCustomerCode: customerCode,
      paystackCustomerId: customer.id || null,
      fundingAccount,
      ...(switchingToLive
        ? {
            availableBalanceKobo: 0,
            pendingBalanceKobo: 0,
            paystackLedgerMode: 'live',
          }
        : { paystackLedgerMode: paystackMode() }),
      updatedAt: new Date(),
    },
    { merge: true },
  );

  const refreshed = await ref.get();
  const aligned = await alignWalletLedgerMode(ref, refreshed);
  return serializeWallet(aligned);
}

export async function listTransactions(userId, { limit = 30 } = {}) {
  const db = getFirestore();
  const snap = await db
    .collection(TXNS)
    .where('userId', '==', userId)
    .limit(Math.min(Math.max(limit, 1) * 3, 150))
    .get();

  const hideTestEra = paystackMode() === 'live';

  return snap.docs
    .map((doc) => {
      const data = doc.data() || {};
      return {
        id: doc.id,
        reference: data.reference,
        type: data.type,
        amount: fromKobo(data.amountKobo || 0),
        balanceAfter: fromKobo(data.balanceAfterKobo || 0),
        status: data.status,
        title: data.title || data.type,
        provider: data.provider || null,
        providerReference: data.providerReference || null,
        metadata: data.metadata || {},
        createdAt: data.createdAt?.toDate?.()?.toISOString?.() || null,
        _sort: data.createdAt?.toMillis?.() || 0,
        _hide: hideTestEra && isTestLedgerTxn(data),
      };
    })
    .filter((row) => !row._hide)
    .sort((a, b) => b._sort - a._sort)
    .slice(0, Math.min(limit, 100))
    .map(({ _sort, _hide, ...rest }) => rest);
}

async function creditWalletTx({
  userId,
  amountKobo,
  reference,
  providerReference,
  title,
  metadata,
}) {
  const db = getFirestore();
  const walletRef = db.collection(WALLETS).doc(userId);
  const txnRef = db.collection(TXNS).doc(reference);
  const eventRef = db.collection(PROCESSED).doc(`credit_${reference}`);

  await db.runTransaction(async (tx) => {
    const eventSnap = await tx.get(eventRef);
    if (eventSnap.exists) {
      return;
    }
    const txnSnap = await tx.get(txnRef);
    if (txnSnap.exists) {
      return;
    }

    const walletSnap = await tx.get(walletRef);
    if (!walletSnap.exists) {
      throw new Error('Wallet not found for credit');
    }
    const wallet = walletSnap.data() || {};
    const before = Number(wallet.availableBalanceKobo || 0);
    const after = before + amountKobo;
    const now = new Date();

    tx.set(walletRef, {
      availableBalanceKobo: after,
      updatedAt: now,
    }, { merge: true });

    tx.set(txnRef, {
      walletId: userId,
      userId,
      reference,
      type: 'top_up',
      title: title || 'Wallet Top Up',
      amountKobo,
      balanceBeforeKobo: before,
      balanceAfterKobo: after,
      status: 'successful',
      provider: 'paystack',
      providerReference: providerReference || null,
      metadata: metadata || {},
      createdAt: now,
      updatedAt: now,
    });

    tx.set(eventRef, {
      reference,
      userId,
      amountKobo,
      createdAt: now,
    });
  });
}

export async function handleChargeSuccess(eventData, { userId: knownUserId } = {}) {
  const data = eventData?.data || eventData || {};
  const reference = String(data.reference || '').trim();
  const amountKobo = Number(data.amount || 0);
  const status = String(data.status || 'success').toLowerCase();

  if (!reference || amountKobo <= 0 || !isSuccessStatus(status)) {
    return { ok: false, reason: 'ignored' };
  }

  let verifiedData = data;
  try {
    const verified = await verifyTransaction(reference);
    verifiedData = verified.data || data;
    if (!isSuccessStatus(verifiedData.status)) {
      return { ok: false, reason: 'unverified' };
    }
  } catch (error) {
    if (!knownUserId) {
      return { ok: false, reason: 'unverified' };
    }
    console.warn('Paystack verify skipped for known wallet top-up', reference, error.message || error);
  }

  const channel = String(
    verifiedData.authorization?.channel ||
      verifiedData.channel ||
      data.authorization?.channel ||
      data.channel ||
      '',
  );
  const customerCode =
    verifiedData.customer?.customer_code ||
    data.customer?.customer_code ||
    null;
  const customerId = verifiedData.customer?.id || data.customer?.id || null;
  const email = (
    verifiedData.customer?.email ||
    data.customer?.email ||
    ''
  )
    .trim()
    .toLowerCase();

  const db = getFirestore();
  let userId = knownUserId || null;

  if (!userId && customerCode) {
    const match = await db
      .collection(WALLETS)
      .where('paystackCustomerCode', '==', customerCode)
      .limit(1)
      .get();
    if (!match.empty) {
      userId = match.docs[0].id;
    }
  }

  if (!userId && customerId) {
    const match = await db
      .collection(WALLETS)
      .where('paystackCustomerId', '==', customerId)
      .limit(1)
      .get();
    if (!match.empty) {
      userId = match.docs[0].id;
    }
  }

  if (!userId && email) {
    const match = await db
      .collection(WALLETS)
      .where('email', '==', email)
      .limit(1)
      .get();
    if (!match.empty) {
      userId = match.docs[0].id;
    }
  }

  // Dedicated account number fallback.
  const accountNumber =
    receiverAccountNumber(verifiedData) || receiverAccountNumber(data) || null;
  if (!userId && accountNumber) {
    const match = await db
      .collection(WALLETS)
      .where('fundingAccount.accountNumber', '==', String(accountNumber))
      .limit(1)
      .get();
    if (!match.empty) {
      userId = match.docs[0].id;
    }
  }

  if (!userId) {
    console.warn('charge.success unmatched wallet', {
      reference,
      customerCode,
      email,
      accountNumber,
      channel,
    });
    return { ok: false, reason: 'wallet_not_found' };
  }

  await creditWalletTx({
    userId,
    amountKobo: Number(verifiedData.amount || amountKobo),
    reference,
    providerReference: String(verifiedData.id || data.id || ''),
    title: 'Wallet Top Up',
    metadata: {
      channel,
      paidAt: verifiedData.paid_at || data.paid_at || null,
      authorization: data.authorization || null,
    },
  });

  return { ok: true, userId, reference };
}

export async function requestWithdrawal({
  userId,
  amountNaira,
  bankCode,
  bankName,
  accountNumber,
  accountName,
}) {
  const amountKobo = toKobo(amountNaira);
  if (!Number.isFinite(amountKobo) || amountKobo < 10000) {
    throw new Error('Minimum withdrawal is ₦100');
  }

  const resolved = await resolveAccountNumber({
    accountNumber,
    bankCode,
  });
  const resolvedName =
    resolved.data?.account_name || accountName || 'CitiRide Rider';

  const recipient = await createTransferRecipient({
    name: resolvedName,
    accountNumber,
    bankCode,
  });
  const recipientCode = recipient.data?.recipient_code;
  if (!recipientCode) {
    throw new Error('Unable to create transfer recipient');
  }

  const reference = newReference('wd');
  const db = getFirestore();
  const walletRef = db.collection(WALLETS).doc(userId);
  const txnRef = db.collection(TXNS).doc(reference);
  const withdrawalRef = db.collection(WITHDRAWALS).doc(reference);

  await db.runTransaction(async (tx) => {
    const walletSnap = await tx.get(walletRef);
    if (!walletSnap.exists) {
      throw new Error('Wallet not found');
    }
    const wallet = walletSnap.data() || {};
    const available = Number(wallet.availableBalanceKobo || 0);
    if (available < amountKobo) {
      throw new Error('Insufficient wallet balance');
    }
    const after = available - amountKobo;
    const now = new Date();

    tx.set(
      walletRef,
      {
        availableBalanceKobo: after,
        pendingBalanceKobo: Number(wallet.pendingBalanceKobo || 0) + amountKobo,
        updatedAt: now,
      },
      { merge: true },
    );

    tx.set(txnRef, {
      walletId: userId,
      userId,
      reference,
      type: 'withdrawal',
      title: 'Withdrawal to Bank',
      amountKobo,
      balanceBeforeKobo: available,
      balanceAfterKobo: after,
      status: 'pending',
      provider: 'paystack',
      metadata: {
        bankCode,
        bankName: bankName || null,
        accountNumber,
        accountName: resolvedName,
      },
      createdAt: now,
      updatedAt: now,
    });

    tx.set(withdrawalRef, {
      userId,
      walletId: userId,
      reference,
      amountKobo,
      feeKobo: 0,
      bankCode,
      bankName: bankName || null,
      accountNumber,
      accountName: resolvedName,
      paystackRecipientCode: recipientCode,
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    });
  });

  try {
    const transfer = await initiateTransfer({
      amountKobo,
      recipientCode,
      reference,
      reason: 'CitiRide rider wallet withdrawal',
    });

    await withdrawalRef.set(
      {
        status: 'processing',
        paystackTransferCode: transfer.data?.transfer_code || null,
        paystackTransferId: transfer.data?.id || null,
        updatedAt: new Date(),
      },
      { merge: true },
    );

    return {
      reference,
      status: 'processing',
      amount: fromKobo(amountKobo),
      accountName: resolvedName,
    };
  } catch (error) {
    // Restore funds if Paystack transfer could not be started.
    await db.runTransaction(async (tx) => {
      const walletSnap = await tx.get(walletRef);
      const wallet = walletSnap.data() || {};
      const now = new Date();
      tx.set(
        walletRef,
        {
          availableBalanceKobo:
            Number(wallet.availableBalanceKobo || 0) + amountKobo,
          pendingBalanceKobo: Math.max(
            0,
            Number(wallet.pendingBalanceKobo || 0) - amountKobo,
          ),
          updatedAt: now,
        },
        { merge: true },
      );
      tx.set(
        txnRef,
        {
          status: 'failed',
          failureReason: error.message,
          updatedAt: now,
        },
        { merge: true },
      );
      tx.set(
        withdrawalRef,
        {
          status: 'failed',
          failureReason: error.message,
          updatedAt: now,
        },
        { merge: true },
      );
    });
    throw error;
  }
}

export async function handleTransferEvent(eventName, eventData) {
  const data = eventData?.data || eventData || {};
  const reference = String(data.reference || '').trim();
  if (!reference) {
    return { ok: false, reason: 'no_reference' };
  }

  const db = getFirestore();
  const withdrawalRef = db.collection(WITHDRAWALS).doc(reference);
  const txnRef = db.collection(TXNS).doc(reference);
  const eventRef = db.collection(PROCESSED).doc(`transfer_${eventName}_${reference}`);

  const success =
    eventName === 'transfer.success' ||
    String(data.status || '').toLowerCase() === 'success';
  const failed =
    eventName === 'transfer.failed' ||
    eventName === 'transfer.reversed' ||
    ['failed', 'reversed', 'otp'].includes(
      String(data.status || '').toLowerCase(),
    );

  await db.runTransaction(async (tx) => {
    const processed = await tx.get(eventRef);
    if (processed.exists) return;

    const withdrawalSnap = await tx.get(withdrawalRef);
    if (!withdrawalSnap.exists) {
      tx.set(eventRef, { ignored: true, createdAt: new Date() });
      return;
    }

    const withdrawal = withdrawalSnap.data() || {};
    const amountKobo = Number(withdrawal.amountKobo || 0);
    const userId = withdrawal.userId;
    const walletRef = db.collection(WALLETS).doc(userId);
    const walletSnap = await tx.get(walletRef);
    const wallet = walletSnap.data() || {};
    const now = new Date();

    if (success) {
      tx.set(
        withdrawalRef,
        {
          status: 'successful',
          paystackTransferCode: data.transfer_code || withdrawal.paystackTransferCode,
          updatedAt: now,
        },
        { merge: true },
      );
      tx.set(
        txnRef,
        { status: 'successful', updatedAt: now },
        { merge: true },
      );
      tx.set(
        walletRef,
        {
          pendingBalanceKobo: Math.max(
            0,
            Number(wallet.pendingBalanceKobo || 0) - amountKobo,
          ),
          updatedAt: now,
        },
        { merge: true },
      );
    } else if (failed) {
      tx.set(
        withdrawalRef,
        {
          status: eventName === 'transfer.reversed' ? 'reversed' : 'failed',
          failureReason: data.reason || data.failures?.message || null,
          updatedAt: now,
        },
        { merge: true },
      );
      tx.set(
        txnRef,
        {
          status: eventName === 'transfer.reversed' ? 'reversed' : 'failed',
          updatedAt: now,
        },
        { merge: true },
      );
      tx.set(
        walletRef,
        {
          availableBalanceKobo:
            Number(wallet.availableBalanceKobo || 0) + amountKobo,
          pendingBalanceKobo: Math.max(
            0,
            Number(wallet.pendingBalanceKobo || 0) - amountKobo,
          ),
          updatedAt: now,
        },
        { merge: true },
      );
    }

    tx.set(eventRef, {
      eventName,
      reference,
      createdAt: now,
    });
  });

  return { ok: true, reference, success, failed };
}

function assertRidePayable(ride, riderId) {
  if (String(ride.riderId || '') !== String(riderId)) {
    const error = new Error('This ride does not belong to you');
    error.code = 'forbidden';
    throw error;
  }
  const driverId = String(ride.driverId || '').trim();
  if (!driverId) {
    throw new Error('Driver is not assigned yet');
  }
  const status = String(ride.status || '');
  if (status !== 'confirm_fare' && status !== 'in_progress') {
    throw new Error('This trip is not ready for payment');
  }
  return driverId;
}

function rideFareNaira(ride) {
  return Number(ride.fare?.final ?? ride.fare?.estimated ?? 0);
}

function fareSplitForRide(ride) {
  return splitFareKobo(toKobo(rideFareNaira(ride)));
}

function ridePayoutStamp({
  amountNaira,
  percent,
  commissionNaira,
  driverNaira,
}) {
  return {
    paymentAmount: amountNaira,
    'fare.final': amountNaira,
    commissionPercent: percent,
    commissionAmount: commissionNaira,
    driverPayout: driverNaira,
  };
}

function ridePayResult(ride, extras = {}) {
  const split = fareSplitForRide(ride);
  return {
    amount: Number(ride.paymentAmount ?? fromKobo(split.fareKobo)),
    commission: Number(ride.commissionAmount ?? fromKobo(split.commissionKobo)),
    driverPayout: Number(ride.driverPayout ?? fromKobo(split.driverKobo)),
    commissionPercent: Number(ride.commissionPercent ?? split.percent),
    ...extras,
  };
}

/**
 * Debit the rider the full trip fare, credit the driver the net after
 * CitiRide commission, and credit the platform wallet the commission.
 * Idempotent once `rides/{rideId}.paymentStatus === 'paid'`.
 */
export async function payRideFare({ riderId, rideId }) {
  const db = getFirestore();
  const rideRef = db.collection('rides').doc(String(rideId));
  const rideSnap = await rideRef.get();
  if (!rideSnap.exists) {
    const error = new Error('Ride not found');
    error.code = 'not_found';
    throw error;
  }

  const ride = rideSnap.data() || {};
  const driverId = assertRidePayable(ride, riderId);

  if (String(ride.paymentStatus || '') === 'paid') {
    const wallet = await getOrCreateWallet(riderId);
    return ridePayResult(ride, { alreadyPaid: true, wallet });
  }

  const { fareKobo, commissionKobo, driverKobo, percent } = fareSplitForRide(ride);
  const amountNaira = fromKobo(fareKobo);
  const commissionNaira = fromKobo(commissionKobo);
  const driverNaira = fromKobo(driverKobo);
  if (!Number.isFinite(fareKobo) || fareKobo < 100) {
    throw new Error('Invalid fare amount');
  }

  const platformId = platformWalletId();
  await getOrCreateWallet(riderId);
  await getOrCreateWallet(driverId, { walletType: 'driver' });
  if (commissionKobo > 0) {
    await getOrCreateWallet(platformId, { walletType: 'platform' });
  }

  const debitRefId = `ride_pay_${rideId}_out`;
  const creditRefId = `ride_pay_${rideId}_in`;
  const commissionRefId = `ride_pay_${rideId}_commission`;
  const eventRef = db.collection(PROCESSED).doc(`ride_pay_${rideId}`);

  await db.runTransaction(async (tx) => {
    const eventSnap = await tx.get(eventRef);
    const rideNow = await tx.get(rideRef);
    const riderWalletRef = db.collection(WALLETS).doc(riderId);
    const driverWalletRef = db.collection(WALLETS).doc(driverId);
    const platformWalletRef = db.collection(WALLETS).doc(platformId);
    const riderWalletSnap = await tx.get(riderWalletRef);
    const driverWalletSnap = await tx.get(driverWalletRef);
    const platformWalletSnap =
      commissionKobo > 0 ? await tx.get(platformWalletRef) : null;

    const rideData = rideNow.data() || {};
    if (eventSnap.exists || String(rideData.paymentStatus || '') === 'paid') {
      return;
    }
    if (!riderWalletSnap.exists) {
      throw new Error('Rider wallet not found');
    }
    if (!driverWalletSnap.exists) {
      throw new Error('Driver wallet not found');
    }
    if (commissionKobo > 0 && !platformWalletSnap?.exists) {
      throw new Error('Platform wallet not found');
    }

    const riderWallet = riderWalletSnap.data() || {};
    const driverWallet = driverWalletSnap.data() || {};
    const riderBefore = Number(riderWallet.availableBalanceKobo || 0);
    if (riderBefore < fareKobo) {
      const error = new Error(
        'Insufficient wallet balance. Add money and try again.',
      );
      error.code = 'insufficient_funds';
      throw error;
    }

    const driverBefore = Number(driverWallet.availableBalanceKobo || 0);
    const platformBefore = Number(
      platformWalletSnap?.data()?.availableBalanceKobo || 0,
    );
    const now = new Date();
    const splitMeta = {
      rideId,
      fareKobo,
      commissionKobo,
      driverKobo,
      commissionPercent: percent,
    };

    tx.set(
      riderWalletRef,
      {
        availableBalanceKobo: riderBefore - fareKobo,
        updatedAt: now,
      },
      { merge: true },
    );
    tx.set(
      driverWalletRef,
      {
        availableBalanceKobo: driverBefore + driverKobo,
        updatedAt: now,
      },
      { merge: true },
    );

    tx.set(db.collection(TXNS).doc(debitRefId), {
      walletId: riderId,
      userId: riderId,
      reference: debitRefId,
      type: 'ride_payment',
      title: 'Ride payment',
      amountKobo: -fareKobo,
      balanceBeforeKobo: riderBefore,
      balanceAfterKobo: riderBefore - fareKobo,
      status: 'successful',
      provider: 'citiride',
      metadata: { ...splitMeta, counterpartyId: driverId },
      createdAt: now,
      updatedAt: now,
    });

    tx.set(db.collection(TXNS).doc(creditRefId), {
      walletId: driverId,
      userId: driverId,
      reference: creditRefId,
      type: 'ride_earning',
      title: 'Ride earning',
      amountKobo: driverKobo,
      balanceBeforeKobo: driverBefore,
      balanceAfterKobo: driverBefore + driverKobo,
      status: 'successful',
      provider: 'citiride',
      metadata: { ...splitMeta, counterpartyId: riderId },
      createdAt: now,
      updatedAt: now,
    });

    if (commissionKobo > 0 && platformWalletSnap) {
      tx.set(
        platformWalletRef,
        {
          availableBalanceKobo: platformBefore + commissionKobo,
          updatedAt: now,
        },
        { merge: true },
      );
      tx.set(db.collection(TXNS).doc(commissionRefId), {
        walletId: platformId,
        userId: platformId,
        reference: commissionRefId,
        type: 'ride_commission',
        title: 'Ride commission',
        amountKobo: commissionKobo,
        balanceBeforeKobo: platformBefore,
        balanceAfterKobo: platformBefore + commissionKobo,
        status: 'successful',
        provider: 'citiride',
        metadata: { ...splitMeta, riderId, driverId },
        createdAt: now,
        updatedAt: now,
      });
    }

    tx.set(
      rideRef,
      {
        paymentStatus: 'paid',
        paymentChannel: 'wallet',
        paidAt: now,
        paymentReference: debitRefId,
        ...ridePayoutStamp({
          amountNaira,
          percent,
          commissionNaira,
          driverNaira,
        }),
        updatedAt: now,
      },
      { merge: true },
    );

    tx.set(eventRef, {
      rideId,
      riderId,
      driverId,
      amountKobo: fareKobo,
      commissionKobo,
      driverKobo,
      commissionPercent: percent,
      createdAt: now,
    });
  });

  const wallet = await getOrCreateWallet(riderId);
  return ridePayResult(
    {
      paymentAmount: amountNaira,
      commissionAmount: commissionNaira,
      driverPayout: driverNaira,
      commissionPercent: percent,
      fare: { final: amountNaira },
    },
    { alreadyPaid: false, wallet },
  );
}

/**
 * Cash trips: rider confirms they paid the driver without moving ledger funds.
 */
export async function confirmRideCashPayment({ riderId, rideId }) {
  const db = getFirestore();
  const rideRef = db.collection('rides').doc(String(rideId));
  const rideSnap = await rideRef.get();
  if (!rideSnap.exists) {
    const error = new Error('Ride not found');
    error.code = 'not_found';
    throw error;
  }

  const ride = rideSnap.data() || {};
  assertRidePayable(ride, riderId);

  const method = String(ride.paymentMethod || 'cash').toLowerCase();
  if (method !== 'cash') {
    throw new Error('This trip is set to wallet. Pay from your CitiRide wallet.');
  }

  if (String(ride.paymentStatus || '') === 'paid') {
    return ridePayResult(ride, { alreadyPaid: true });
  }

  const { fareKobo, commissionKobo, driverKobo, percent } = fareSplitForRide(ride);
  const amountNaira = fromKobo(fareKobo);
  const commissionNaira = fromKobo(commissionKobo);
  const driverNaira = fromKobo(driverKobo);
  const now = new Date();
  const eventRef = db.collection(PROCESSED).doc(`ride_cash_${rideId}`);

  await db.runTransaction(async (tx) => {
    const eventSnap = await tx.get(eventRef);
    const rideNow = await tx.get(rideRef);
    const rideData = rideNow.data() || {};
    if (eventSnap.exists || String(rideData.paymentStatus || '') === 'paid') {
      return;
    }

    tx.set(
      rideRef,
      {
        paymentStatus: 'paid',
        paymentChannel: 'cash',
        paidAt: now,
        ...ridePayoutStamp({
          amountNaira,
          percent,
          commissionNaira,
          driverNaira,
        }),
        updatedAt: now,
      },
      { merge: true },
    );
    tx.set(eventRef, {
      rideId,
      riderId,
      channel: 'cash',
      amountKobo: fareKobo,
      commissionKobo,
      driverKobo,
      commissionPercent: percent,
      createdAt: now,
    });
  });

  return ridePayResult(
    {
      paymentAmount: amountNaira,
      commissionAmount: commissionNaira,
      driverPayout: driverNaira,
      commissionPercent: percent,
      fare: { final: amountNaira },
    },
    { alreadyPaid: false },
  );
}
