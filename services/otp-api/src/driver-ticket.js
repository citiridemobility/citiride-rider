import {
  fromKobo,
  getFirestore,
  newReference,
  platformWalletId,
  toKobo,
} from './wallet/util.js';
import { getOrCreateWallet } from './wallet/ledger.js';

const DRIVERS = 'drivers';
const WALLETS = 'wallets';
const TXNS = 'wallet_transactions';
const SETTINGS = 'platform_settings';
const DRIVER_TICKET_SETTING_ID = 'driver_ticket';
const PAID_TICKET_DURATION_MS = 24 * 60 * 60 * 1000;
const PAYMENT_GRACE_PERIOD_MS = 3 * 60 * 60 * 1000;

function asMillis(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

function readTicketConfig(data = {}) {
  const feeKobo = Math.round(Number(data.ticketFeeKobo));
  return {
    // Disabled by default while ticket payments are being tested. Set this to
    // true in platform_settings/driver_ticket to enforce ticket payments.
    enabled: data.ticketFeeEnabled === true,
    configured: Number.isFinite(feeKobo) && feeKobo > 0,
    feeKobo: Number.isFinite(feeKobo) && feeKobo > 0 ? feeKobo : 0,
    validForHours: 24,
    paymentGracePeriodHours: 3,
  };
}

function serializedTicketStatus({ config, driver = {}, now = Date.now() }) {
  const expiresAtMs = asMillis(driver.ticketExpiresAt);
  const paidAtMs = asMillis(driver.ticketPaidAt);
  const graceStartedAtMs = asMillis(driver.ticketPaymentGraceStartedAt);
  const graceExpiresAtMs = asMillis(driver.ticketPaymentGraceExpiresAt);
  const hasPaidTicket = config.configured && expiresAtMs > now;
  const graceActive =
    config.enabled &&
    config.configured &&
    !hasPaidTicket &&
    graceExpiresAtMs > now;
  const paidTicketExpired =
    config.enabled && config.configured && !hasPaidTicket && expiresAtMs > 0;
  const graceExpired =
    config.enabled &&
    config.configured &&
    !hasPaidTicket &&
    graceStartedAtMs > 0 &&
    graceExpiresAtMs <= now;
  const requiresPayment = paidTicketExpired || graceExpired;
  const canGoOnline =
    !config.enabled ||
    hasPaidTicket ||
    graceActive ||
    (config.configured && !requiresPayment && !graceStartedAtMs);
  const canReceiveRequests = !config.enabled || hasPaidTicket || graceActive;
  const active = !config.enabled || hasPaidTicket;
  const status = !config.enabled
    ? 'disabled'
    : hasPaidTicket
      ? 'active'
      : graceActive
        ? 'grace_period'
        : paidTicketExpired
          ? 'expired'
          : graceExpired
            ? 'payment_required'
            : 'required';

  return {
    enabled: config.enabled,
    configured: config.configured,
    fee: fromKobo(config.feeKobo),
    currency: 'NGN',
    validForHours: config.validForHours,
    paymentGracePeriodHours: config.paymentGracePeriodHours,
    active,
    canGoOnline,
    canReceiveRequests,
    requiresPayment,
    graceActive,
    status,
    paidAt: paidAtMs ? new Date(paidAtMs).toISOString() : null,
    expiresAt: expiresAtMs ? new Date(expiresAtMs).toISOString() : null,
    paymentGraceStartedAt: graceStartedAtMs
      ? new Date(graceStartedAtMs).toISOString()
      : null,
    paymentDueAt: graceExpiresAtMs
      ? new Date(graceExpiresAtMs).toISOString()
      : null,
    driverStatus:
      driver.status === 'online' && canReceiveRequests ? 'online' : 'offline',
  };
}

function ticketRequiredError(message = 'Pay the driver ticket fee to go online.') {
  const error = new Error(message);
  error.code = 'ticket_required';
  return error;
}

function requireDriverRecord(driverSnap) {
  if (driverSnap?.exists) return;
  const error = new Error('A verified driver profile is required to use driver availability.');
  error.code = 'driver_profile_required';
  throw error;
}

/**
 * Reads the current fee from Firestore and forces an expired online driver
 * offline. Keeping this in the API makes expiry effective even between
 * scheduler runs or after an app resumes from the background.
 */
export async function getDriverTicketStatus(driverId) {
  const db = getFirestore();
  const driverRef = db.collection(DRIVERS).doc(driverId);
  const configRef = db.collection(SETTINGS).doc(DRIVER_TICKET_SETTING_ID);

  return db.runTransaction(async (tx) => {
    const [driverSnap, configSnap] = await Promise.all([
      tx.get(driverRef),
      tx.get(configRef),
    ]);
    const driver = driverSnap.exists ? driverSnap.data() || {} : {};
    const config = readTicketConfig(configSnap.exists ? configSnap.data() : {});
    const status = serializedTicketStatus({ config, driver });

    if (status.requiresPayment && driver.status === 'online') {
      tx.set(
        driverRef,
        {
          status: 'offline',
          ticketStatus: status.status,
          ticketExpiredAt: new Date(),
          updatedAt: new Date(),
        },
        { merge: true },
      );
    }

    return status;
  });
}

/**
 * Debits the driver's CitiRide wallet and creates a 24-hour ticket. The fee
 * is read inside the transaction so an admin fee change can never result in a
 * stale price being charged. A driver can pay during their three-hour online
 * grace window without being taken offline.
 */
export async function purchaseDriverTicket(driverId) {
  const db = getFirestore();
  const platformId = platformWalletId();

  await Promise.all([
    getOrCreateWallet(driverId, { walletType: 'driver' }),
    getOrCreateWallet(platformId, { walletType: 'platform' }),
  ]);

  const driverRef = db.collection(DRIVERS).doc(driverId);
  const configRef = db.collection(SETTINGS).doc(DRIVER_TICKET_SETTING_ID);
  const driverWalletRef = db.collection(WALLETS).doc(driverId);
  const platformWalletRef = db.collection(WALLETS).doc(platformId);
  const reference = newReference('driver_ticket');
  const driverTxnRef = db.collection(TXNS).doc(`${reference}_driver`);
  const platformTxnRef = db.collection(TXNS).doc(`${reference}_platform`);

  const ticket = await db.runTransaction(async (tx) => {
    const [configSnap, driverSnap, driverWalletSnap, platformWalletSnap] =
      await Promise.all([
        tx.get(configRef),
        tx.get(driverRef),
        tx.get(driverWalletRef),
        tx.get(platformWalletRef),
      ]);

    const config = readTicketConfig(configSnap.exists ? configSnap.data() : {});
    if (!config.enabled) {
      const error = new Error('Driver ticket fees are temporarily disabled.');
      error.code = 'ticket_disabled';
      throw error;
    }
    if (!config.configured) {
      const error = new Error('The driver ticket fee has not been configured yet.');
      error.code = 'ticket_not_configured';
      throw error;
    }

    const now = new Date();
    const driver = driverSnap.exists ? driverSnap.data() || {} : {};
    requireDriverRecord(driverSnap);
    const current = serializedTicketStatus({ config, driver, now: now.getTime() });
    if (current.active) {
      const error = new Error('Your current driver ticket is still active.');
      error.code = 'ticket_already_active';
      throw error;
    }

    if (!driverWalletSnap.exists) {
      throw new Error('Driver wallet is not available. Set up your wallet first.');
    }
    if (!platformWalletSnap.exists) {
      throw new Error('Platform wallet is not available. Please try again.');
    }

    const driverWallet = driverWalletSnap.data() || {};
    const platformWallet = platformWalletSnap.data() || {};
    const driverBefore = Number(driverWallet.availableBalanceKobo || 0);
    const platformBefore = Number(platformWallet.availableBalanceKobo || 0);

    if (driverBefore < config.feeKobo) {
      const error = new Error(
        `Insufficient wallet balance. Add ${fromKobo(config.feeKobo).toLocaleString('en-NG', {
          style: 'currency',
          currency: 'NGN',
          maximumFractionDigits: 0,
        })} to pay your driver ticket.`,
      );
      error.code = 'insufficient_funds';
      throw error;
    }

    const expiresAt = new Date(now.getTime() + PAID_TICKET_DURATION_MS);
    const keepDriverOnline = driver.status === 'online';
    const ticketMetadata = {
      ticketReference: reference,
      ticketFeeKobo: config.feeKobo,
      validForHours: config.validForHours,
      expiresAt,
    };

    tx.set(
      driverWalletRef,
      {
        availableBalanceKobo: driverBefore - config.feeKobo,
        updatedAt: now,
      },
      { merge: true },
    );
    tx.set(
      platformWalletRef,
      {
        availableBalanceKobo: platformBefore + config.feeKobo,
        updatedAt: now,
      },
      { merge: true },
    );
    tx.set(driverTxnRef, {
      walletId: driverId,
      userId: driverId,
      reference,
      type: 'driver_ticket_fee',
      title: '24-hour driver ticket',
      amountKobo: -config.feeKobo,
      balanceBeforeKobo: driverBefore,
      balanceAfterKobo: driverBefore - config.feeKobo,
      status: 'successful',
      provider: 'citiride',
      metadata: ticketMetadata,
      createdAt: now,
      updatedAt: now,
    });
    tx.set(platformTxnRef, {
      walletId: platformId,
      userId: platformId,
      reference,
      type: 'driver_ticket_fee',
      title: 'Driver ticket fee',
      amountKobo: config.feeKobo,
      balanceBeforeKobo: platformBefore,
      balanceAfterKobo: platformBefore + config.feeKobo,
      status: 'successful',
      provider: 'citiride',
      metadata: { ...ticketMetadata, driverId },
      createdAt: now,
      updatedAt: now,
    });
    tx.set(
      driverRef,
      {
        status: keepDriverOnline ? 'online' : 'offline',
        ticketStatus: 'active',
        ticketReference: reference,
        ticketFeeKobo: config.feeKobo,
        ticketPaidAt: now,
        ticketExpiresAt: expiresAt,
        ticketExpiredAt: null,
        ticketPaymentGraceStartedAt: null,
        ticketPaymentGraceExpiresAt: null,
        updatedAt: now,
      },
      { merge: true },
    );

    return serializedTicketStatus({
      config,
      driver: {
        ...driver,
        status: keepDriverOnline ? 'online' : 'offline',
        ticketPaidAt: now,
        ticketExpiresAt: expiresAt,
        ticketPaymentGraceStartedAt: null,
        ticketPaymentGraceExpiresAt: null,
      },
      now: now.getTime(),
    });
  });

  return { ticket, reference };
}

/**
 * The only API that can take a driver online. The first unpaid online session
 * starts a non-resettable three-hour payment window. Once it passes, the
 * driver must pay before going online again.
 */
export async function setDriverAvailability(driverId, online) {
  const db = getFirestore();
  const driverRef = db.collection(DRIVERS).doc(driverId);
  const configRef = db.collection(SETTINGS).doc(DRIVER_TICKET_SETTING_ID);

  return db.runTransaction(async (tx) => {
    const [driverSnap, configSnap] = await Promise.all([
      tx.get(driverRef),
      tx.get(configRef),
    ]);
    const driver = driverSnap.exists ? driverSnap.data() || {} : {};
    requireDriverRecord(driverSnap);
    const config = readTicketConfig(configSnap.exists ? configSnap.data() : {});
    const now = new Date();
    const ticket = serializedTicketStatus({
      config,
      driver,
      now: now.getTime(),
    });

    if (online && config.enabled && !config.configured) {
      tx.set(
        driverRef,
        {
          status: 'offline',
          ticketStatus: 'required',
          updatedAt: now,
        },
        { merge: true },
      );
      throw ticketRequiredError(
        'The driver ticket fee has not been configured yet.',
      );
    }

    if (online && ticket.requiresPayment) {
      tx.set(
        driverRef,
        {
          status: 'offline',
          ticketStatus: ticket.status,
          ticketExpiredAt: now,
          updatedAt: now,
        },
        { merge: true },
      );
      throw ticketRequiredError(
        ticket.status === 'expired'
          ? 'Your 24-hour driver ticket has expired. Pay the ticket fee to go online.'
          : 'Your 3-hour ticket payment window has ended. Pay the ticket fee to go online.',
      );
    }

    let nextDriver = {
      ...driver,
      status: online ? 'online' : 'offline',
    };
    const availabilityUpdate = {
      status: nextDriver.status,
      updatedAt: now,
    };

    if (online && config.enabled && !ticket.active && !ticket.graceActive) {
      const paymentGraceStartedAt = now;
      const paymentGraceExpiresAt = new Date(
        now.getTime() + PAYMENT_GRACE_PERIOD_MS,
      );
      nextDriver = {
        ...nextDriver,
        ticketPaymentGraceStartedAt: paymentGraceStartedAt,
        ticketPaymentGraceExpiresAt: paymentGraceExpiresAt,
      };
      availabilityUpdate.ticketPaymentGraceStartedAt = paymentGraceStartedAt;
      availabilityUpdate.ticketPaymentGraceExpiresAt = paymentGraceExpiresAt;
    }

    const nextTicket = serializedTicketStatus({
      config,
      driver: nextDriver,
      now: now.getTime(),
    });
    availabilityUpdate.ticketStatus = nextTicket.status;

    tx.set(
      driverRef,
      availabilityUpdate,
      { merge: true },
    );

    return nextTicket;
  });
}

export function ticketConfigDocument() {
  return {
    collection: SETTINGS,
    id: DRIVER_TICKET_SETTING_ID,
  };
}

export function parseTicketFeeNaira(value) {
  const feeKobo = toKobo(value);
  if (!Number.isFinite(feeKobo) || feeKobo <= 0) return null;
  return feeKobo;
}
