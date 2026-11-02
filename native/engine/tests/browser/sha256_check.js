const fs = require('fs'); const crypto = require('crypto');
const src = fs.readFileSync(process.argv[2], 'utf8');
const start = src.indexOf('const K = new Uint32Array'); const end = src.indexOf('// ------------------------------------------------------------- helpers');
const Sha256 = new Function(src.slice(start, end) + '; return Sha256;')();
let fails = 0;
for (const len of [0, 1, 55, 56, 63, 64, 65, 119, 120, 1000, 100000, 3_000_001]) {
  const buf = crypto.randomBytes(len);
  const h = new Sha256(); let i = 0;
  while (i < len) { const n = Math.min(len - i, 1 + Math.floor(Math.random() * 70000)); h.update(buf.subarray(i, i + n)); i += n; }
  const got = h.hex(), want = crypto.createHash('sha256').update(buf).digest('hex');
  if (got !== want) { fails++; console.log('FAIL', len, got, want); }
}
const big = crypto.randomBytes(64 * 1024 * 1024); const t = Date.now(); const h = new Sha256(); h.update(big); h.hex();
console.log(fails ? 'FAILED' : 'all sha256 vectors OK', `(${Math.round(64 / ((Date.now() - t) / 1000))} MB/s)`);
