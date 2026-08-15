import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const logoPath = path.join(__dirname, '../../public/citiride-logo.png');

export const brand = {
  black: '#161616',
  yellow: '#F5E700',
  muted: '#8F8F8F',
  white: '#FFFFFF',
  card: '#1C1C1C',
  font: "'Poppins', Arial, Helvetica, sans-serif",
};

export function logoAttachment() {
  if (!fs.existsSync(logoPath)) {
    return null;
  }

  return {
    filename: 'citiride-logo.png',
    content: fs.readFileSync(logoPath),
    contentId: 'citiride-logo',
  };
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
    title: 'Verify your email',
    bodyHtml: `
      <p style="margin:0 0 18px;color:${brand.muted};font-size:15px;line-height:1.55;font-family:${brand.font};">
        Use this code to continue your CitiRide ${purposeLabel}.
      </p>
      <div style="margin:0 0 22px;padding:18px 16px;border-radius:16px;background:${brand.black};border:1px solid rgba(245,231,0,0.28);text-align:center;">
        <p style="margin:0 0 8px;color:${brand.muted};font-size:12px;letter-spacing:0.08em;text-transform:uppercase;font-family:${brand.font};">
          Verification code
        </p>
        <p style="margin:0;color:${brand.yellow};font-size:34px;font-weight:800;letter-spacing:0.28em;font-family:${brand.font};">
          ${code}
        </p>
      </div>
      <p style="margin:0;color:${brand.muted};font-size:13px;line-height:1.5;font-family:${brand.font};">
        This code expires in <strong style="color:${brand.white};">${ttlMinutes} minutes</strong>.
        If you did not request it, you can ignore this email.
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
    'CitiRide verification',
    '',
    `Your code for ${purposeLabel}: ${code}`,
    `Expires in ${ttlMinutes} minutes.`,
    '',
    'If you did not request this, ignore this email.',
  ].join('\n');
}

export function riderWelcomeEmailHtml({ email }) {
  const firstName = guessFirstName(email);

  return emailShell({
    preheader: 'Welcome to CitiRide — rides made simple.',
    title: `Welcome aboard${firstName ? `, ${firstName}` : ''}!`,
    bodyHtml: `
      <p style="margin:0 0 14px;color:${brand.muted};font-size:15px;line-height:1.55;font-family:${brand.font};">
        You are all set as a <strong style="color:${brand.white};">CitiRide rider</strong>.
        Book reliable trips, track your ride live, and pay your way — all in one place.
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 20px;">
        <tr>
          <td style="padding:12px 14px;border-radius:14px;background:${brand.black};border:1px solid rgba(255,255,255,0.08);">
            <p style="margin:0 0 6px;color:${brand.yellow};font-size:13px;font-weight:700;font-family:${brand.font};">
              What you can do next
            </p>
            <p style="margin:0;color:${brand.muted};font-size:14px;line-height:1.55;font-family:${brand.font};">
              Set your pickup, choose a ride, and head out. Your profile and wallet stay ready whenever you need them.
            </p>
          </td>
        </tr>
      </table>
      <p style="margin:0;color:${brand.muted};font-size:13px;line-height:1.5;font-family:${brand.font};">
        Ride safe,<br/>
        <strong style="color:${brand.white};">The CitiRide team</strong>
      </p>
    `,
  });
}

export function riderWelcomeEmailText({ email }) {
  const firstName = guessFirstName(email);
  return [
    `Welcome aboard${firstName ? `, ${firstName}` : ''}!`,
    '',
    'You are all set as a CitiRide rider.',
    'Book reliable trips, track your ride live, and pay your way — all in one place.',
    '',
    'Ride safe,',
    'The CitiRide team',
  ].join('\n');
}

function emailShell({ preheader, title, bodyHtml }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="dark" />
  <meta name="supported-color-schemes" content="dark" />
  <title>${escapeHtml(title)}</title>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800&display=swap');
    body, table, td, p, a { font-family: ${brand.font}; }
  </style>
</head>
<body style="margin:0;padding:0;background:${brand.black};">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
    ${escapeHtml(preheader)}
  </div>
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:${brand.black};padding:28px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:560px;background:${brand.card};border-radius:24px;border:1px solid rgba(245,231,0,0.18);overflow:hidden;">
          <tr>
            <td style="padding:28px 28px 8px;text-align:center;background:linear-gradient(180deg, #222200 0%, ${brand.card} 100%);">
              <img
                src="cid:citiride-logo"
                width="88"
                height="88"
                alt="CitiRide"
                style="display:block;margin:0 auto 14px;border:0;outline:none;width:88px;height:88px;"
              />
              <p style="margin:0;color:${brand.yellow};font-size:22px;font-weight:800;letter-spacing:0.02em;font-family:${brand.font};">
                CitiRide
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 28px 28px;">
              <h1 style="margin:0 0 14px;color:${brand.white};font-size:24px;font-weight:700;line-height:1.25;font-family:${brand.font};">
                ${escapeHtml(title)}
              </h1>
              ${bodyHtml}
            </td>
          </tr>
          <tr>
            <td style="padding:16px 28px 24px;border-top:1px solid rgba(255,255,255,0.08);">
              <p style="margin:0;color:${brand.muted};font-size:12px;line-height:1.45;text-align:center;font-family:${brand.font};">
                © ${new Date().getFullYear()} CitiRide Mobility. All rights reserved.
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
