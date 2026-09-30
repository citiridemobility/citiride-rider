export const brand = {
  black: '#161616',
  yellow: '#F5E700',
  muted: '#5C5C5C',
  soft: '#8A8A8A',
  white: '#FFFFFF',
  page: '#EEEEEA',
  card: '#FFFFFF',
  border: '#E6E6E0',
  codeBox: '#161616',
  font: "Arial, Helvetica, sans-serif",
};

export function publicLogoUrl() {
  const raw = (
    process.env.PUBLIC_BASE_URL ||
    process.env.RAILWAY_PUBLIC_DOMAIN ||
    'https://otp-api-production-db79.up.railway.app'
  ).trim();

  const base = raw.replace(/\/+$/, '');
  const withProtocol = /^https?:\/\//i.test(base) ? base : `https://${base}`;
  return `${withProtocol}/assets/citiride-logo.png`;
}

export function otpEmailCopy(purpose) {
  switch (purpose) {
    case 'login':
      return {
        subject: 'Your CitiRide login code',
        title: 'Log in to CitiRide',
        label: 'login',
        intro:
          'Use this one-time password to log in to your CitiRide rider account. Do not share it with anyone.',
      };
    case 'driver_login':
      return {
        subject: 'Your CitiRide driver login code',
        title: 'Log in to CitiRide',
        label: 'driver login',
        intro:
          'Use this one-time password to log in to your CitiRide driver account. Do not share it with anyone.',
      };
    case 'signup':
      return {
        subject: 'Your CitiRide sign-up code',
        title: 'Finish signing up',
        label: 'sign-up',
        intro:
          'Use this one-time password to create your CitiRide rider account. Do not share it with anyone.',
      };
    case 'driver_signup':
      return {
        subject: 'Your CitiRide driver sign-up code',
        title: 'Finish signing up',
        label: 'driver sign-up',
        intro:
          'Use this one-time password to create your CitiRide driver account. Do not share it with anyone.',
      };
    case 'wallet':
      return {
        subject: 'Your CitiRide wallet code',
        title: 'Your one-time password',
        label: 'wallet setup',
        intro:
          'Use this one-time password (OTP) to continue your CitiRide wallet setup. Do not share it with anyone.',
      };
    case 'reset_pin':
      return {
        subject: 'Your CitiRide PIN reset code',
        title: 'Your one-time password',
        label: 'PIN reset',
        intro:
          'Use this one-time password (OTP) to continue your CitiRide PIN reset. Do not share it with anyone.',
      };
    case 'withdraw':
      return {
        subject: 'Your CitiRide withdrawal code',
        title: 'Your one-time password',
        label: 'wallet withdrawal',
        intro:
          'Use this one-time password (OTP) to continue your CitiRide wallet withdrawal. Do not share it with anyone.',
      };
    default:
      return {
        subject: 'Your CitiRide sign-up code',
        title: 'Finish signing up',
        label: 'sign-up',
        intro:
          'Use this one-time password to create your CitiRide account. Do not share it with anyone.',
      };
  }
}

export function otpEmailHtml({ code, purpose, ttlMinutes }) {
  const copy = otpEmailCopy(purpose);
  const safeCode = escapeHtml(code);

  return emailShell({
    preheader: `${copy.subject} is ${code}`,
    title: copy.title,
    bodyHtml: `
      <p style="margin:0 0 24px;color:${brand.muted};font-size:15px;line-height:1.6;font-family:${brand.font};">
        ${escapeHtml(copy.intro)}
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 24px;border-collapse:collapse;">
        <tr>
          <td align="center" bgcolor="${brand.codeBox}" style="padding:24px 16px;border-radius:16px;background-color:${brand.codeBox};">
            <p style="margin:0 0 10px;color:#B0B0B0;font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;font-family:${brand.font};">
              One-time password
            </p>
            <p style="margin:0;color:${brand.yellow};font-size:34px;font-weight:700;letter-spacing:0.28em;line-height:1.2;font-family:${brand.font};">
              ${safeCode}
            </p>
          </td>
        </tr>
      </table>
      <p style="margin:0;color:${brand.soft};font-size:13px;line-height:1.55;font-family:${brand.font};">
        Expires in ${escapeHtml(String(ttlMinutes))} minutes. If you didn’t request this, ignore this email.
      </p>
    `,
  });
}

export function otpEmailText({ code, purpose, ttlMinutes }) {
  const copy = otpEmailCopy(purpose);

  return [
    'CitiRide',
    '',
    copy.intro,
    '',
    `Your one-time password (OTP) for ${copy.label}: ${code}`,
    `Expires in ${ttlMinutes} minutes.`,
    'Do not share this code with anyone.',
    '',
    'If you did not request this, ignore this email.',
  ].join('\n');
}

export function riderWelcomeEmailHtml({ email }) {
  const firstName = guessFirstName(email);

  return emailShell({
    preheader: 'Welcome to CitiRide. Your rider account is ready.',
    title: firstName ? `Welcome, ${firstName}` : 'Welcome to CitiRide',
    bodyHtml: `
      <p style="margin:0 0 22px;color:${brand.muted};font-size:15px;line-height:1.65;font-family:${brand.font};">
        Your rider account is ready. Move through the city with clear pricing, live tracking, and a wallet that stays with you.
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 24px;border-collapse:collapse;">
        <tr>
          <td style="padding:0 0 14px;">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Set your pickup
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Choose where you’re headed and confirm your ride.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:14px 0;border-top:1px solid ${brand.border};">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Track in real time
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Follow your driver from pickup to drop-off.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:14px 0 0;border-top:1px solid ${brand.border};">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Pay your way
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Cash or wallet — whichever is easiest for you.
            </p>
          </td>
        </tr>
      </table>
      <p style="margin:0;color:${brand.soft};font-size:13px;line-height:1.55;font-family:${brand.font};">
        Open the app and take your first ride.<br/><br/>
        — CitiRide
      </p>
    `,
  });
}

export function riderWelcomeEmailText({ email }) {
  const firstName = guessFirstName(email);
  return [
    firstName ? `Welcome, ${firstName}` : 'Welcome to CitiRide',
    '',
    'Your rider account is ready. Move through the city with clear pricing, live tracking, and a wallet that stays with you.',
    '',
    'Open the app and take your first ride.',
    '',
    '— CitiRide',
  ].join('\n');
}

export function driverWelcomeEmailHtml({ email }) {
  const firstName = guessFirstName(email);

  return emailShell({
    preheader: 'Welcome to CitiRide Driver. Your driver account is ready.',
    title: firstName ? `Welcome, ${firstName}` : 'Welcome to CitiRide Driver',
    bodyHtml: `
      <p style="margin:0 0 22px;color:${brand.muted};font-size:15px;line-height:1.65;font-family:${brand.font};">
        Your driver account is ready. Complete your vehicle registration, go online when you’re ready, and start accepting ride requests.
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 24px;border-collapse:collapse;">
        <tr>
          <td style="padding:0 0 14px;">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Finish registration
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Add your vehicle details and documents so you can start driving.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:14px 0;border-top:1px solid ${brand.border};">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Go online
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Toggle availability on the home screen to receive nearby ride requests.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:14px 0 0;border-top:1px solid ${brand.border};">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Track earnings
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              View completed trips and wallet activity from the app.
            </p>
          </td>
        </tr>
      </table>
      <p style="margin:0;color:${brand.soft};font-size:13px;line-height:1.55;font-family:${brand.font};">
        Open the CitiRide Driver app to get started.<br/><br/>
        — CitiRide
      </p>
    `,
  });
}

export function driverWelcomeEmailText({ email }) {
  const firstName = guessFirstName(email);
  return [
    firstName ? `Welcome, ${firstName}` : 'Welcome to CitiRide Driver',
    '',
    'Your driver account is ready. Complete your vehicle registration, go online when you’re ready, and start accepting ride requests.',
    '',
    'Open the CitiRide Driver app to get started.',
    '',
    '— CitiRide',
  ].join('\n');
}

export function riderWalletCreatedEmailHtml({ email }) {
  const firstName = guessFirstName(email);

  return emailShell({
    preheader: 'Congratulations! Your CitiRide wallet is ready.',
    title: firstName
      ? `Congratulations, ${firstName}`
      : 'Your wallet is ready',
    bodyHtml: `
      <p style="margin:0 0 22px;color:${brand.muted};font-size:15px;line-height:1.65;font-family:${brand.font};">
        Your CitiRide wallet is set up. Use it to pay for rides quickly, keep your balance in one place, and withdraw when you need to.
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 24px;border-collapse:collapse;">
        <tr>
          <td style="padding:0 0 14px;">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Pay for rides
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Choose wallet at checkout for a faster payment experience.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:14px 0;border-top:1px solid ${brand.border};">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Add money anytime
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Top up your balance from the wallet tab whenever you need more funds.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:14px 0 0;border-top:1px solid ${brand.border};">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Stay secure
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Your passcode unlocks the wallet — never share it with anyone.
            </p>
          </td>
        </tr>
      </table>
      <p style="margin:0;color:${brand.soft};font-size:13px;line-height:1.55;font-family:${brand.font};">
        Open the CitiRide app to start using your wallet.<br/><br/>
        — CitiRide
      </p>
    `,
  });
}

export function riderWalletCreatedEmailText({ email }) {
  const firstName = guessFirstName(email);
  return [
    firstName
      ? `Congratulations, ${firstName}`
      : 'Your CitiRide wallet is ready',
    '',
    'Your CitiRide wallet is set up. Use it to pay for rides quickly, keep your balance in one place, and withdraw when you need to.',
    '',
    'Open the CitiRide app to start using your wallet.',
    '',
    '— CitiRide',
  ].join('\n');
}

export function driverWalletCreatedEmailHtml({ email }) {
  const firstName = guessFirstName(email);

  return emailShell({
    preheader: 'Congratulations! Your CitiRide driver wallet is ready.',
    title: firstName
      ? `Congratulations, ${firstName}`
      : 'Your driver wallet is ready',
    bodyHtml: `
      <p style="margin:0 0 22px;color:${brand.muted};font-size:15px;line-height:1.65;font-family:${brand.font};">
        Your CitiRide driver wallet is set up. Receive ride earnings, track payouts, and withdraw funds securely from the app.
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 24px;border-collapse:collapse;">
        <tr>
          <td style="padding:0 0 14px;">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Collect earnings
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Completed trips can settle into your wallet so payouts stay organized.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:14px 0;border-top:1px solid ${brand.border};">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Withdraw when ready
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Move funds to your bank account from the wallet withdraw flow.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:14px 0 0;border-top:1px solid ${brand.border};">
            <p style="margin:0;color:${brand.black};font-size:14px;font-weight:700;line-height:1.5;font-family:${brand.font};">
              Protect your passcode
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Your wallet passcode keeps earnings safe — keep it private.
            </p>
          </td>
        </tr>
      </table>
      <p style="margin:0;color:${brand.soft};font-size:13px;line-height:1.55;font-family:${brand.font};">
        Open the CitiRide Driver app to manage your wallet.<br/><br/>
        — CitiRide
      </p>
    `,
  });
}

export function driverWalletCreatedEmailText({ email }) {
  const firstName = guessFirstName(email);
  return [
    firstName
      ? `Congratulations, ${firstName}`
      : 'Your CitiRide driver wallet is ready',
    '',
    'Your CitiRide driver wallet is set up. Receive ride earnings, track payouts, and withdraw funds securely from the app.',
    '',
    'Open the CitiRide Driver app to manage your wallet.',
    '',
    '— CitiRide',
  ].join('\n');
}

function emailShell({ preheader, title, bodyHtml }) {
  const logoUrl = publicLogoUrl();
  const year = new Date().getFullYear();

  // Light card layout: survives Gmail/Outlook dark-mode inversion better than
  // dark-on-dark templates (which often leave only the yellow OTP visible).
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="light only" />
  <meta name="supported-color-schemes" content="light only" />
  <title>${escapeHtml(title)}</title>
  <style>
    :root { color-scheme: light only; supported-color-schemes: light only; }
    body, table, td, p, a, li, blockquote { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
    table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
    img { -ms-interpolation-mode: bicubic; border: 0; outline: none; text-decoration: none; }
  </style>
</head>
<body style="margin:0;padding:0;background-color:${brand.page};background:${brand.page};">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;mso-hide:all;font-size:1px;line-height:1px;">
    ${escapeHtml(preheader)}
  </div>
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" bgcolor="${brand.page}" style="background-color:${brand.page};margin:0;padding:0;border-collapse:collapse;">
    <tr>
      <td align="center" style="padding:36px 16px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" bgcolor="${brand.card}" style="max-width:480px;background-color:${brand.card};border:1px solid ${brand.border};border-radius:24px;overflow:hidden;border-collapse:separate;">
          <tr>
            <td align="center" bgcolor="${brand.card}" style="padding:32px 28px 8px;background-color:${brand.card};">
              <img
                src="${logoUrl}"
                width="72"
                height="72"
                alt="CitiRide"
                style="display:block;margin:0 auto;border:0;outline:none;text-decoration:none;width:72px;height:72px;"
              />
            </td>
          </tr>
          <tr>
            <td bgcolor="${brand.yellow}" style="height:4px;line-height:4px;font-size:0;background-color:${brand.yellow};">&nbsp;</td>
          </tr>
          <tr>
            <td bgcolor="${brand.card}" style="padding:24px 28px 32px;background-color:${brand.card};">
              <h1 style="margin:0 0 14px;color:${brand.black};font-size:24px;font-weight:700;line-height:1.25;letter-spacing:-0.02em;font-family:${brand.font};">
                ${escapeHtml(title)}
              </h1>
              ${bodyHtml}
            </td>
          </tr>
          <tr>
            <td bgcolor="${brand.card}" style="padding:0 28px 26px;background-color:${brand.card};">
              <p style="margin:0;padding-top:18px;border-top:1px solid ${brand.border};color:${brand.soft};font-size:11px;line-height:1.5;text-align:center;font-family:${brand.font};">
                © ${year} CitiRide Mobility
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function guessFirstName(email) {
  const local = String(email || '').split('@')[0] || '';
  const token = local.split(/[._+-]/).find(Boolean) || '';
  if (!token || token.length < 2) {
    return '';
  }
  return token.charAt(0).toUpperCase() + token.slice(1).toLowerCase();
}

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}
