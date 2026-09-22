// Draws an icon for every ability, into assets/icons/abilities/<id>.svg.
// Run with Astra open (the imported classes come from its library):
//   & "E:\Astra-Ability Creator\runtime\node.exe" tools/ability_icons.mjs
//
// Each icon is: a round backing in the ability's colour, the glyph of what it
// does (damage, heal, revive, buff, debuff, status) and a small corner mark
// for its target shape (circle, line, cone, self, global, vector).
// The built-in jobs' abilities (scripts/core/jobs.gd) are listed at the end.
import {readFile, writeFile, mkdir} from 'node:fs/promises';

const API = 'http://127.0.0.1:47261/api/library';
const OUT = new URL('../assets/icons/abilities/', import.meta.url);
const slug = s => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

const GLYPHS = {
  damage: c => `<path d="M32 10 L38 28 L56 32 L38 36 L32 54 L26 36 L8 32 L26 28 Z" fill="${c}"/>`,
  heal: c => `<rect x="27" y="14" width="10" height="36" rx="3" fill="${c}"/><rect x="14" y="27" width="36" height="10" rx="3" fill="${c}"/>`,
  revive: c => `<circle cx="32" cy="22" r="9" fill="none" stroke="${c}" stroke-width="5"/><rect x="28" y="30" width="8" height="22" rx="3" fill="${c}"/><rect x="18" y="36" width="28" height="7" rx="3" fill="${c}"/>`,
  buff: c => `<path d="M32 10 L48 30 L38 30 L38 52 L26 52 L26 30 L16 30 Z" fill="${c}"/>`,
  debuff: c => `<path d="M32 54 L16 34 L26 34 L26 12 L38 12 L38 34 L48 34 Z" fill="${c}"/>`,
  status: c => `<circle cx="32" cy="32" r="16" fill="none" stroke="${c}" stroke-width="5"/><circle cx="32" cy="32" r="5" fill="${c}"/>`,
};
const MARKS = {
  circle: c => `<circle cx="50" cy="50" r="9" fill="none" stroke="${c}" stroke-width="3"/>`,
  line: c => `<rect x="40" y="48" width="20" height="4" rx="2" fill="${c}"/>`,
  cone: c => `<path d="M40 58 L58 44 L58 58 Z" fill="${c}"/>`,
  self: c => `<circle cx="50" cy="50" r="5" fill="${c}"/><circle cx="50" cy="50" r="10" fill="none" stroke="${c}" stroke-width="2"/>`,
  global: c => `<circle cx="50" cy="50" r="9" fill="none" stroke="${c}" stroke-width="2"/><path d="M41 50 H59 M50 41 V59" stroke="${c}" stroke-width="2"/>`,
  vector: c => `<path d="M39 57 L57 43 M57 43 L48 43 M57 43 L57 52" fill="none" stroke="${c}" stroke-width="3" stroke-linecap="round"/>`,
  unit: c => `<circle cx="50" cy="50" r="6" fill="${c}"/>`,
  point: c => `<circle cx="50" cy="50" r="6" fill="none" stroke="${c}" stroke-width="3"/>`,
};

function shade(hex, mix, towards) {
  const n = parseInt(hex.slice(1), 16);
  const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(v => Math.round(v + (towards - v) * mix));
  return '#' + c.map(v => v.toString(16).padStart(2, '0')).join('');
}

function icon({color = '#9b83ff', glyph = 'damage', shape = 'unit'}) {
  const light = shade(color, 0.55, 255);
  const dark = shade(color, 0.72, 0);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="32" r="30" fill="${dark}" stroke="${light}" stroke-width="2"/>
${GLYPHS[glyph](light)}
${MARKS[shape] ? MARKS[shape](color === light ? '#e9edf6' : light) : ''}
</svg>
`;
}

// What an Astra ability does, as a glyph name.
function glyphFor(a) {
  const types = a.effects.map(e => e.type);
  if (a.tags.includes('revive')) return 'revive';
  if (types.includes('Damage')) return 'damage';
  if (types.includes('Heal')) return 'heal';
  if (types.includes('Debuff') || types.includes('Slow') || types.includes('Stun')) return 'debuff';
  if (types.includes('Buff')) return 'buff';
  return 'status';
}
const SHAPES = {'Unit target': 'unit', 'Point target': 'point', 'Self': 'self', 'Circle': 'circle',
  'Line': 'line', 'Cone': 'cone', 'Global': 'global', 'Vector': 'vector'};

await mkdir(OUT, {recursive: true});
const lib = await (await fetch(API)).json();
let written = 0;
for (const a of lib.abilities) {
  const classTag = a.tags.find(t => t.startsWith('class:'));
  if (!classTag || a.tags.includes('profile')) continue;
  const id = `${classTag.slice(6)}_${slug(a.name)}`;
  await writeFile(new URL(`${id}.svg`, OUT), icon({color: a.color, glyph: glyphFor(a), shape: SHAPES[a.targeting] ?? 'unit'}), 'utf8');
  written++;
}

// The built-in jobs' abilities: id, colour, glyph, shape.
const BUILT_IN = [
  ['attack', '#c9ced9', 'damage', 'unit'], ['throw_stone', '#c9a06a', 'damage', 'unit'],
  ['focus', '#ffd166', 'buff', 'self'], ['brave_slash', '#e0625a', 'damage', 'unit'],
  ['shield_bash', '#9fb4d8', 'damage', 'unit'], ['guard', '#7fb2e8', 'buff', 'self'],
  ['holy_blade', '#f4e2a0', 'damage', 'circle'], ['bow_shot', '#7fc97f', 'damage', 'unit'],
  ['aimed_shot', '#ffd166', 'damage', 'unit'], ['pin_shot', '#b98adf', 'debuff', 'unit'],
  ['arrow_rain', '#7fc97f', 'damage', 'circle'], ['punch', '#e8a33d', 'damage', 'unit'],
  ['wave_fist', '#e8a33d', 'damage', 'unit'], ['chakra', '#77dba0', 'heal', 'self'],
  ['earth_slash', '#a98a5f', 'damage', 'self'], ['staff', '#b6b6c8', 'damage', 'unit'],
  ['fire', '#ef7a4a', 'damage', 'unit'], ['blizzard', '#7fd4ef', 'damage', 'circle'],
  ['meteor', '#ff9a3c', 'damage', 'circle'], ['raise', '#f4e2a0', 'revive', 'unit'],
  ['cure', '#77dba0', 'heal', 'unit'], ['haste', '#7fb2e8', 'buff', 'unit'],
  ['sanctuary', '#a8e6c0', 'heal', 'circle'],
];
for (const [id, color, glyph, shape] of BUILT_IN) {
  await writeFile(new URL(`${id}.svg`, OUT), icon({color, glyph, shape}), 'utf8');
  written++;
}
// Fallbacks, by what an ability does.
for (const glyph of Object.keys(GLYPHS)) {
  await writeFile(new URL(`any_${glyph}.svg`, OUT), icon({color: '#9aa3b5', glyph, shape: 'unit'}), 'utf8');
  written++;
}
console.log(`Wrote ${written} ability icons to assets/icons/abilities/`);
