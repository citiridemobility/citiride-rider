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
const TICKET_DURATION_MS = 24 * 60 * 60 * 1000;

function asMillis(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

function readTicketConfig(data = {}) {
  const feeKobo = Math.round(Number(data.ticketFeeKobo));
  return {
    configured: Number.isFinite(feeKobo) && feeKobo > 0,
    feeKobo: Number.isFinite(feeKobo) && feeKobo > 0 ? feeKobo : 0,
    validForHours: 24,
  };
}

function serializedTicketStatus({ config, driver = {}, now = Date.now() }) {
  const expiresAtMs = asMillis(driver.ticketExpiresAt);
  const paidAtMs = asMillis(driver.ticketPaidAt);
  const active = config.configured && expiresAtMs > now;

  return {
    configured: config.configured,
    fee: fromKobo(config.feeKobo),
    currency: 'NGN',
    validForHours: config.validForHours,
    active,
    status: active ? 'active' : expiresAtMs ? 'expired' : 'required',
    paidAt: paidAtMs ? new Date(paidAtMs).toISOString() : null,
    expiresAt: expiresAtMs ? new Date(expiresAtMs).toISOString() : null,
    driverStatus: active ? String(driver.status || 'offline') : 'offline',
  };
}

function ticketRequiredError(message = 'Pay the 24-hour driver ticket to go online.') {
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

    if (!status.active && driver.status === 'online') {
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
 * Debits the driver's CitiRide wallet and creates one non-renewable 24-hour
 * ticket. The fee is read inside the transaction so an admin fee change can
 * never result in a stale price being charged.
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

    const expiresAt = new Date(now.getTime() + TICKET_DURATION_MS);
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
        status: 'offline',
        ticketStatus: 'active',
        ticketReference: reference,
        ticketFeeKobo: config.feeKobo,
        ticketPaidAt: now,
        ticketExpiresAt: expiresAt,
        ticketExpiredAt: null,
        updatedAt: now,
      },
      { merge: true },
    );

    return serializedTicketStatus({
      config,
      driver: {
        ...driver,
        status: 'offline',
        ticketPaidAt: now,
        ticketExpiresAt: expiresAt,
      },
      now: now.getTime(),
    });
  });

  return { ticket, reference };
}

/**
 * The only API that can take a driver online. A ticket is checked inside a
 * Firestore transaction so a stale client cannot become eligible for dispatch.
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
    const ticket = serializedTicketStatus({ config, driver });

    if (online && !ticket.active) {
      tx.set(
        driverRef,
        {
          status: 'offline',
          ticketStatus: ticket.status,
          ticketExpiredAt: ticket.status === 'expired' ? new Date() : null,
          updatedAt: new Date(),
        },
        { merge: true },
      );
      throw ticketRequiredError(
        ticket.configured
          ? 'Your 24-hour driver ticket has expired. Pay the ticket fee to go online.'
          : 'The driver ticket fee has not been configured yet.',
      );
    }

    const now = new Date();
    tx.set(
      driverRef,
      {
        status: online ? 'online' : 'offline',
        ...(online ? { ticketStatus: 'active' } : {}),
        updatedAt: now,
      },
      { merge: true },
    );

    return {
      ...ticket,
      driverStatus: online ? 'online' : 'offline',
    };
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
