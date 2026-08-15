import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const svgPath = path.join(root, 'assets/images/citiridelogo.svg');
const outDir = path.join(root, 'services/otp-api/public');
const outPath = path.join(outDir, 'citiride-logo.png');

const svg = fs.readFileSync(svgPath, 'utf8');
const match = svg.match(/xlink:href="data:image\/png;base64,([^"]+)"/);
if (!match) {
  console.error('Could not find embedded PNG in citiridelogo.svg');
  process.exit(1);
}

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(outPath, Buffer.from(match[1], 'base64'));
console.log(`Wrote ${outPath} (${fs.statSync(outPath).size} bytes)`);
