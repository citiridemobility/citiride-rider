export const brand = {
  black: '#161616',
  yellow: '#F5E700',
  muted: '#A3A3A3',
  soft: '#6B6B6B',
  white: '#FFFFFF',
  card: '#1A1A1A',
  font: "'Poppins', Arial, Helvetica, sans-serif",
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

export function otpEmailHtml({ code, purpose, ttlMinutes }) {
  const purposeLabel =
    purpose === 'wallet'
      ? 'wallet setup'
      : purpose === 'reset_pin'
        ? 'PIN reset'
        : 'sign-in';

  return emailShell({
    preheader: `Your CitiRide code is ${code}`,
    title: 'Your verification code',
    bodyHtml: `
      <p style="margin:0 0 28px;color:${brand.muted};font-size:15px;line-height:1.6;font-family:${brand.font};">
        Enter this code to continue your CitiRide ${purposeLabel}.
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 28px;">
        <tr>
          <td align="center" style="padding:22px 16px;border-radius:18px;background:${brand.black};">
            <p style="margin:0 0 10px;color:${brand.soft};font-size:11px;font-weight:600;letter-spacing:0.16em;text-transform:uppercase;font-family:${brand.font};">
              Code
            </p>
            <p style="margin:0;color:${brand.yellow};font-size:36px;font-weight:700;letter-spacing:0.34em;line-height:1;font-family:${brand.font};">
              ${code}
            </p>
          </td>
        </tr>
      </table>
      <p style="margin:0;color:${brand.soft};font-size:13px;line-height:1.55;font-family:${brand.font};">
        Expires in ${ttlMinutes} minutes. If you didn’t request this, ignore this email.
      </p>
    `,
  });
}

export function otpEmailText({ code, purpose, ttlMinutes }) {
  const purposeLabel =
    purpose === 'wallet'
      ? 'wallet setup'
      : purpose === 'reset_pin'
        ? 'PIN reset'
        : 'sign-in';

  return [
    'CitiRide',
    '',
    `Your verification code for ${purposeLabel}: ${code}`,
    `Expires in ${ttlMinutes} minutes.`,
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
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 28px;">
        <tr>
          <td style="padding:0 0 12px;">
            <p style="margin:0;color:${brand.white};font-size:14px;font-weight:600;line-height:1.5;font-family:${brand.font};">
              Set your pickup
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Choose where you’re headed and confirm your ride.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:12px 0;border-top:1px solid rgba(255,255,255,0.06);">
            <p style="margin:0;color:${brand.white};font-size:14px;font-weight:600;line-height:1.5;font-family:${brand.font};">
              Track in real time
            </p>
            <p style="margin:4px 0 0;color:${brand.soft};font-size:13px;line-height:1.5;font-family:${brand.font};">
              Follow your driver from pickup to drop-off.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:12px 0 0;border-top:1px solid rgba(255,255,255,0.06);">
            <p style="margin:0;color:${brand.white};font-size:14px;font-weight:600;line-height:1.5;font-family:${brand.font};">
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

function emailShell({ preheader, title, bodyHtml }) {
  const logoUrl = publicLogoUrl();

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="dark light" />
  <title>${escapeHtml(title)}</title>
  <!--[if !mso]><!-->
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap" rel="stylesheet" />
  <!--<![endif]-->
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap');
  </style>
</head>
<body style="margin:0;padding:0;background:#0E0E0E;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;mso-hide:all;">
    ${escapeHtml(preheader)}
  </div>
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0E0E0E;margin:0;padding:0;">
    <tr>
      <td align="center" style="padding:40px 20px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:480px;background:${brand.card};border-radius:28px;overflow:hidden;">
          <tr>
            <td align="center" style="padding:36px 32px 8px;">
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
            <td style="padding:20px 32px 36px;">
              <h1 style="margin:0 0 12px;color:${brand.white};font-size:26px;font-weight:600;line-height:1.25;letter-spacing:-0.02em;font-family:${brand.font};">
                ${escapeHtml(title)}
              </h1>
              ${bodyHtml}
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 28px;">
              <p style="margin:0;padding-top:20px;border-top:1px solid rgba(255,255,255,0.06);color:${brand.soft};font-size:11px;line-height:1.5;text-align:center;font-family:${brand.font};">
                © ${new Date().getFullYear()} CitiRide Mobility
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
