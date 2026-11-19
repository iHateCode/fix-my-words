// Generates the app-icon SVGs into this folder: node docs/images/icon/gen-icon.mjs
//   app-icon.svg     the master, used for 128 px and up
//   app-icon-32.svg  simplified for 32 px (and 64 px, its @2x)
//   app-icon-16.svg  simplest, for 16 px (and 32 px, its @2x)
// Edit this file, not the SVGs. render-icon.sh turns the SVGs into PNGs.
import { writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

// macOS icon grid: 1024 canvas, 824 px tile centred (100 px margin), superellipse corners.
function squircle(cx = 512, cy = 512, a = 412, n = 4.6, steps = 360) {
  const pts = [];
  for (let i = 0; i < steps; i++) {
    const t = (i / steps) * 2 * Math.PI;
    const c = Math.cos(t), s = Math.sin(t);
    const x = cx + a * Math.sign(c) * Math.abs(c) ** (2 / n);
    const y = cy + a * Math.sign(s) * Math.abs(s) ** (2 / n);
    pts.push(`${x.toFixed(1)},${y.toFixed(1)}`);
  }
  return `M${pts.join('L')}Z`;
}
const TILE = squircle();

// The swap badge: a violet disc with two opposing arrows, scaled from its centre and radius.
function badge(cx, cy, r, { rim = true } = {}) {
  const k = r / 120; // the master badge has radius 120
  const w = 30 * k, dx = 60 * k, dy = 46 * k, head = 28 * k, back = 36 * k;
  const p = (x, y) => `${(cx + x).toFixed(1)},${(cy + y).toFixed(1)}`;
  const line = `fill="none" stroke="#fff" stroke-width="${w.toFixed(1)}" stroke-linecap="round" stroke-linejoin="round"`;
  return `<g filter="url(#soft)">
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="url(#badge)"/>
    ${rim ? `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#fff" stroke-opacity="0.35" stroke-width="${(4 * k).toFixed(1)}"/>` : ''}
    <path d="M${p(-dx, -dy)} L${p(dx - 6 * k, -dy)}" ${line}/>
    <path d="M${p(dx - back, -dy - head)} L${p(dx, -dy)} L${p(dx - back, -dy + head)}" ${line}/>
    <path d="M${p(dx, dy)} L${p(-dx + 6 * k, dy)}" ${line}/>
    <path d="M${p(-dx + back, dy - head)} L${p(-dx, dy)} L${p(-dx + back, dy + head)}" ${line}/>
  </g>`;
}

function icon(body, { rim = 3, shadow = 14 } = {}) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
  <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2FD6C0"/><stop offset="1" stop-color="#0B7A70"/>
  </linearGradient>
  <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.22"/>
    <stop offset="0.5" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="badge" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#8B6CFF"/><stop offset="1" stop-color="#5B34E0"/>
  </linearGradient>
  <filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="12" stdDeviation="${shadow}" flood-color="#000" flood-opacity="0.30"/>
  </filter>
  <filter id="soft" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
    <feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.28"/>
  </filter>
  <clipPath id="clip"><path d="${TILE}"/></clipPath>
</defs>
<path d="${TILE}" fill="url(#tile)" filter="url(#tileShadow)"/>
<g clip-path="url(#clip)">
  <path d="${TILE}" fill="url(#gloss)"/>
  ${body}
</g>
<path d="${TILE}" fill="none" stroke="#fff" stroke-opacity="0.28" stroke-width="${rim}"/>
</svg>
`;
}

// Master: a tilted page, one highlighted word, and the swap badge.
const master = icon(`
  <g transform="translate(-28 0)">
  <g transform="rotate(-6 492 504)" filter="url(#soft)">
    <rect x="262" y="214" width="460" height="580" rx="64" fill="#FFFFFF"/>
    <rect x="330" y="300" width="324" height="44" rx="22" fill="#C9D3DE"/>
    <rect x="316" y="392" width="352" height="96" rx="30" fill="#FFD84A"/>
    <rect x="356" y="420" width="272" height="40" rx="20" fill="#3A3F47"/>
    <rect x="330" y="536" width="290" height="44" rx="22" fill="#C9D3DE"/>
    <rect x="330" y="628" width="210" height="44" rx="22" fill="#C9D3DE"/>
  </g>
  ${badge(700, 696, 120)}
  </g>`);

// 32 px: two grey lines instead of four, a taller highlight, a bigger badge.
const s32 = icon(`
  <g transform="rotate(-6 470 490)" filter="url(#soft)">
    <rect x="236" y="196" width="468" height="600" rx="72" fill="#FFFFFF"/>
    <rect x="304" y="290" width="300" height="72" rx="36" fill="#C9D3DE"/>
    <rect x="290" y="414" width="360" height="150" rx="44" fill="#FFD84A"/>
    <rect x="334" y="456" width="272" height="66" rx="33" fill="#3A3F47"/>
    <rect x="304" y="616" width="200" height="72" rx="36" fill="#C9D3DE"/>
  </g>
  ${badge(704, 704, 160)}`, { rim: 6 });

// 16 px: no grey lines; the page, a big yellow highlight with its word, and a big badge.
const s16 = icon(`
  <g transform="rotate(-6 460 480)" filter="url(#soft)">
    <rect x="220" y="190" width="480" height="600" rx="80" fill="#FFFFFF"/>
    <rect x="276" y="330" width="368" height="220" rx="56" fill="#FFD84A"/>
    <rect x="330" y="398" width="260" height="84" rx="42" fill="#3A3F47"/>
  </g>
  ${badge(704, 704, 190, { rim: false })}`, { rim: 10, shadow: 10 });

writeFileSync(`${here}/app-icon.svg`, master);
writeFileSync(`${here}/app-icon-32.svg`, s32);
writeFileSync(`${here}/app-icon-16.svg`, s16);
