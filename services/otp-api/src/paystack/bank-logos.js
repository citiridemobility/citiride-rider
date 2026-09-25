/**
 * Paystack List Banks does not include logo URLs.
 * nigerianbanks.xyz hosts PNGs keyed by the same slugs Paystack returns.
 */
export function bankLogoUrl(slug) {
  const clean = String(slug || '')
    .trim()
    .toLowerCase();
  if (!clean) return '';
  return `https://nigerianbanks.xyz/logo/${encodeURIComponent(clean)}.png`;
}

export function mapPaystackBank(bank) {
  const code = String(bank?.code || '').trim();
  const slug = String(bank?.slug || '').trim();
  return {
    name: String(bank?.name || '').trim() || 'Bank',
    code,
    slug,
    active: bank?.active !== false,
    logo: bankLogoUrl(slug),
  };
}

export function isTransferBank(bank) {
  if (!bank || bank.active === false || bank.is_deleted === true) return false;
  if (!String(bank.code || '').trim()) return false;
  if (bank.supports_transfer === false) return false;
  const type = String(bank.type || '').toLowerCase();
  if (type === 'mobile_money') return false;
  return true;
}
