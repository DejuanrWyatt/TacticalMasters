// Authors ten classes in Astra Ability Creator through its local API, then
// exports each class (as Astra saved it) to data/classes/<id>.astra.json.
// Run with Astra open (Start Astra.cmd):
//   & "E:\Astra-Ability Creator\runtime\node.exe" tools/astra_classes.mjs
// Re-running replaces these classes in Astra instead of duplicating them.
// The class format is described in scripts/core/astra_import.gd.
import {newAbility, parameter, effect, validateAbility} from 'file:///E:/Astra-Ability%20Creator/app/model.mjs';
import {writeFile, mkdir} from 'node:fs/promises';

const API = 'http://127.0.0.1:47261/api/library';
const OUT_DIR = new URL('../data/classes/', import.meta.url);

// Parameter names (their formula keys are what the game reads).
const NAMES = {power: 'Power', min_range: 'Min range', cast_range: 'Cast range', radius: 'Radius', cast_time: 'Cast time',
  cooldown_turns: 'Cooldown turns', tg_change: 'TG change', buff_turns: 'Buff turns', cone_angle: 'Cone angle', channel_turns: 'Channel turns', status_duration: 'Status turns',
  buff_power: 'Buff Power', buff_aeva: 'Buff A-Eva', buff_meva: 'Buff M-Eva', buff_crit: 'Buff Crit', buff_attdef: 'Buff AttDef', buff_magdef: 'Buff MagDef', buff_speed: 'Buff Speed',
  hp: 'HP', power: 'Power', aeva: 'A-Eva', meva: 'M-Eva', crit: 'Crit', attdef: 'AttDef', magdef: 'MagDef', speed: 'Speed', move: 'Move', patience: 'Patience', sight: 'Sight'};
const UNITS = {min_range: 'm', cast_range: 'm', radius: 'm', cast_time: 's', status_duration: 'turns', cooldown_turns: 'turns', cone_angle: 'degrees', channel_turns: 'turns',
  tg_change: '%', power: 'x stat', move: 'm', sight: 'm', buff_turns: 'turns'};

function params(values) {
  return Object.entries(values).map(([key, v]) => {
    // Power grows a little per rank in Astra (the game uses rank 1).
    const growth = key === 'power' ? 0.1 : 0;
    return parameter(NAMES[key], v, growth, UNITS[key] ?? '', growth ? 'Flat increase' : 'Static', {key, floorZero: false});
  });
}

// Speed differences are pronounced: each class's Speed is spread twice as far
// from 8.5 (limited to 4-16), and a faster class trades 5 HP per Speed gained
// (a slower one gains them), so turns and toughness balance out.
function spreadSpeed(stats) {
  const speed = Math.min(16, Math.max(4, Math.round(8.5 + (stats.speed - 8.5) * 2)));
  return {...stats, speed, hp: stats.hp - (speed - stats.speed) * 5};
}

const E = (type, fields = {}) => ({...effect(type), damageType: 'None', amount: '0', ...fields});
const damage = (kind = 'Magic') => E('Damage', {amount: 'power', damageType: kind});
const heal = () => E('Heal', {amount: 'power', target: 'Allies'});
const status = type => E(type, {timing: 'Static', duration: 'status_duration'});
const periodic = type => E(type, {timing: 'Periodic', amount: 'power', duration: 'status_duration', tick: '1'});
const buff = (team = 'Allies') => E('Buff', {amount: '0', target: team, notes: 'Stat changes from the buff_ parameters.'});
const debuff = () => E('Debuff', {amount: '0', target: 'Enemies', notes: 'Stat changes from the buff_ parameters.'});

// One class: its profile plus four abilities (slot 4 is the ultimate).
function cls(id, name, color, look, icon, role, description, stats, abilities, palette, motif) {
  const tag = `class:${id}`;
  const entry = (fields, ps, effects, tags) => {
    const a = newAbility(fields.name);
    Object.assign(a, {color, icon: 'orb', status: 'Ready', resource: 'None', levels: fields.kind === 'Passive' ? 1 : 3, hotkey: ''},
      fields, {parameters: ps, effects, tags: [tag, ...tags]});
    a.visuals = {...a.visuals, palette, motif};
    a.implementation = {engine: 'Godot 4', notes: 'Imported by Tactical Masters (scripts/core/astra_import.gd).'};
    return a;
  };
  const list = [entry({name, kind: 'Passive', targeting: 'Self', targetTeam: 'Self', damageType: 'None', element: 'None', description},
    params(spreadSpeed(stats)), [E('Buff', {name: 'Class stats', trigger: 'Always', target: 'Self', notes: 'Profile only.'})],
    ['profile', `look:${look}`, `icon:${icon}`, `role:${role}`])];
  abilities.forEach((ab, i) => {
    const {p, effects, tags = [], ...fields} = ab;
    list.push(entry({kind: 'Active', element: 'None', targeting: 'Unit target', targetTeam: 'Enemies', damageType: 'None', ...fields},
      params(p), effects, [`slot:${i + 1}`, ...(i === 3 ? ['Ultimate'] : []), ...tags]));
  });
  return {id, entries: list};
}

const CLASSES = [
  cls('dragoon', 'Dragoon', '#4f7fd9', 'knight', 'dragoon', 'damage', 'Lance fighter who leaps onto distant targets.',
    {hp: 95, power: 17, aeva: 12, meva: 6, crit: 12, attdef: 11, magdef: 5, speed: 8, move: 7, patience: 6, sight: 9}, [
      {name: 'Lance', description: 'Thrust at an enemy up to 2.2 m away.', damageType: 'Physical',
        p: {power: 17, cast_range: 2.2}, effects: [damage('Physical')], tags: ['fx:attack']},
      {name: 'Jump', description: 'Leap onto an enemy 3-7 m away, landing there and hitting everyone on the way.', targeting: 'Vector', damageType: 'Physical',
        p: {power: 37, min_range: 3, cast_range: 7, radius: 0.8, cooldown_turns: 2}, effects: [damage('Physical')], tags: ['fx:brave_slash']},
      {name: 'Dragon Spirit', description: 'Raise your AttPwr by 5 for 2 turns.', targeting: 'Self', targetTeam: 'Self',
        p: {buff_power: 5, buff_turns: 2, cooldown_turns: 3}, effects: [buff('Self')], tags: ['fx:focus']},
      {name: 'Highwind', description: 'Dive onto every enemy within 2.5 m of a point 2-8 m away.', targeting: 'Circle', damageType: 'Physical',
        p: {power: 31, min_range: 2, cast_range: 8, radius: 2.5, cast_time: 2}, effects: [damage('Physical')], tags: ['fx:earth_slash']},
    ], 'Cobalt, steel, sky blue', 'Dragon-crested lance, wind trails'),

  cls('ninja', 'Ninja', '#8a90b8', 'squire', 'ninja', 'damage', 'Fast, fragile assassin who strikes before anyone else.',
    {hp: 95, power: 16, aeva: 26, meva: 10, crit: 22, attdef: 10, magdef: 7, speed: 11, move: 8, patience: 5, sight: 10}, [
      {name: 'Twin Strike', description: 'Two quick blades on an adjacent enemy.', damageType: 'Physical',
        p: {power: 24}, effects: [damage('Physical')], tags: ['fx:attack']},
      {name: 'Shuriken', description: 'Throw a star at an enemy 2-8 m away.', damageType: 'Physical',
        p: {power: 13, min_range: 2, cast_range: 8}, effects: [damage('Physical')], tags: ['fx:throw_stone']},
      {name: 'Smoke Bomb', description: 'Slow every enemy within 2 m of a point 1-5 m away for 4 s.', targeting: 'Circle',
        p: {min_range: 1, cast_range: 5, radius: 2, cooldown_turns: 3, status_duration: 2}, effects: [status('Slow')], tags: ['fx:haste']},
      {name: 'Assassinate', description: 'A killing blow on an adjacent enemy.', damageType: 'Physical',
        p: {power: 58}, effects: [damage('Physical')], tags: ['fx:brave_slash']},
    ], 'Charcoal, crimson, silver', 'Shadows, smoke, thrown stars'),

  cls('summoner', 'Summoner', '#d98a3b', 'black_mage', 'summoner', 'damage', 'Slow caster who calls enormous beasts.',
    {hp: 58, power: 19, aeva: 5, meva: 14, crit: 10, attdef: 4, magdef: 12, speed: 7, move: 6, patience: 9, sight: 10}, [
      {name: 'Rod', description: 'Strike an adjacent enemy.', damageType: 'Physical',
        p: {power: 15}, effects: [damage('Physical')], tags: ['fx:attack']},
      {name: 'Ifrit', description: 'Hellfire on every enemy within 2 m of a point 3-9 m away; Burns for 5 s.', targeting: 'Circle', damageType: 'Magic',
        p: {power: 23, min_range: 3, cast_range: 9, radius: 2, cast_time: 2, cooldown_turns: 2, status_duration: 2},
        effects: [damage(), periodic('Damage')], tags: ['fx:fire']},
      {name: 'Carbuncle', description: 'Raise MagDef by 6 for every ally within 3 m of a point up to 6 m away, 2 turns.', targeting: 'Circle', targetTeam: 'Allies',
        p: {cast_range: 6, radius: 3, cast_time: 1, cooldown_turns: 3, buff_magdef: 6, buff_turns: 2}, effects: [buff()], tags: ['fx:haste']},
      {name: 'Bahamut', description: 'Megaflare on every enemy within 4 m of a point 4-11 m away (4 s).', targeting: 'Circle', damageType: 'Magic',
        p: {power: 42, min_range: 4, cast_range: 11, radius: 4, cast_time: 4}, effects: [damage()], tags: ['fx:meteor']},
    ], 'Amber, flame orange, gold', 'Summoning circles, beast silhouettes'),

  cls('paladin', 'Paladin', '#f0d27a', 'knight', 'paladin', 'tank/support', 'Holy knight: sturdy, heals and shields allies.',
    {hp: 105, power: 14, aeva: 6, meva: 10, crit: 5, attdef: 13, magdef: 9, speed: 8, move: 6, patience: 8, sight: 8}, [
      {name: 'Holy Strike', description: 'Strike an adjacent enemy.', damageType: 'Physical',
        p: {power: 17}, effects: [damage('Physical')], tags: ['fx:attack']},
      {name: 'Aegis', description: "Raise an ally's AttDef by 8 for 2 turns (up to 5 m).", targetTeam: 'Allies',
        p: {cast_range: 5, cooldown_turns: 3, buff_attdef: 8, buff_turns: 2}, effects: [buff()], tags: ['fx:guard']},
      {name: 'Lay on Hands', description: 'Heal an ally up to 3 m away (1 s).', targetTeam: 'Allies', damageType: 'Magic',
        p: {power: 8, cast_range: 3, cast_time: 1, cooldown_turns: 2}, effects: [heal()], tags: ['fx:cure']},
      {name: 'Judgment', description: 'Holy light on every enemy within 3 m of you (1.5 s).', targeting: 'Self', damageType: 'Magic',
        p: {power: 22, radius: 3, cast_time: 1.5}, effects: [damage()], tags: ['fx:holy_blade']},
    ], 'White, gold, sky', 'Radiant halos, winged shields'),

  cls('bard', 'Bard', '#6fcf97', 'archer', 'bard', 'support', 'Support who speeds allies up and lulls enemies.',
    {hp: 70, power: 13, aeva: 10, meva: 12, crit: 8, attdef: 6, magdef: 10, speed: 10, move: 6, patience: 7, sight: 11}, [
      {name: 'Dissonance', description: 'A jarring chord at an enemy 1-7 m away.', damageType: 'Magic',
        p: {power: 8, min_range: 1, cast_range: 7}, effects: [damage()], tags: ['fx:pin_shot']},
      {name: 'Song of Haste', description: 'Every ally within 3 m of a point up to 6 m away gains 25% TG (1.5 s).', targeting: 'Circle', targetTeam: 'Allies',
        p: {cast_range: 6, radius: 3, cast_time: 1.5, cooldown_turns: 3, tg_change: 25}, effects: [buff()], tags: ['fx:haste']},
      {name: 'Lullaby', description: 'Slow every enemy within 2.5 m of a point 2-8 m away for 5 s (1.5 s).', targeting: 'Circle',
        p: {min_range: 2, cast_range: 8, radius: 2.5, cast_time: 1.5, cooldown_turns: 3, status_duration: 2}, effects: [status('Slow')], tags: ['fx:blizzard']},
      {name: 'Hymn of Life', description: 'Heal every ally within 4 m of you, with Regen for 8 s (2 s).', targeting: 'Self', targetTeam: 'Allies', damageType: 'Magic',
        p: {power: 18, radius: 4, cast_time: 2, status_duration: 3}, effects: [periodic('Heal')], tags: ['fx:sanctuary']},
    ], 'Emerald, cream, gold', 'Music notes, lute strings'),

  cls('berserker', 'Berserker', '#c0392b', 'monk', 'berserker', 'damage', 'Huge HP and damage, poor defenses.',
    {hp: 115, power: 19, aeva: 8, meva: 5, crit: 18, attdef: 7, magdef: 4, speed: 8, move: 7, patience: 4, sight: 8}, [
      {name: 'Cleave', description: 'Axe sweep through everyone in a 90° arc up to 3 m away.', targeting: 'Cone', damageType: 'Physical',
        p: {power: 15, cast_range: 3, cone_angle: 90}, effects: [damage('Physical')], tags: ['fx:brave_slash']},
      {name: 'Rage', description: 'Switched on: AttPwr +8 but AttDef -4 while it lasts.', kind: 'Toggle', targeting: 'Self', targetTeam: 'Self',
        p: {buff_power: 5, buff_attdef: -4, buff_turns: 2}, effects: [buff('Self')], tags: ['fx:focus']},
      {name: 'Leap Smash', description: 'Smash every enemy within 1.5 m of a point 2-5 m away, Stunning for 1 s (1 s).', targeting: 'Circle', damageType: 'Physical',
        p: {power: 27, min_range: 2, cast_range: 5, radius: 1.5, cast_time: 1, cooldown_turns: 3, status_duration: 1},
        effects: [damage('Physical'), status('Stun')], tags: ['fx:earth_slash']},
      {name: 'Rampage', description: 'Spin through every enemy within 2.5 m of you.', targeting: 'Self', damageType: 'Physical',
        p: {power: 46, radius: 2.5}, effects: [damage('Physical')], tags: ['fx:earth_slash']},
    ], 'Blood red, iron, bone', 'Twin axes, war paint'),

  cls('chemist', 'Chemist', '#8e7cc3', 'squire', 'chemist', 'support', 'Item expert: bombs, potions and Phoenix Downs.',
    {hp: 75, power: 12, aeva: 10, meva: 10, crit: 8, attdef: 7, magdef: 8, speed: 9, move: 6, patience: 7, sight: 9}, [
      {name: 'Fire Bomb', description: 'Throw a bomb hitting enemies within 1.2 m of a point 2-6 m away; Burns for 4 s.', targeting: 'Circle', damageType: 'Physical',
        p: {power: 7, min_range: 2, cast_range: 6, radius: 1.2, status_duration: 2}, effects: [damage('Physical'), periodic('Damage')], tags: ['fx:throw_stone']},
      {name: 'Potion', description: 'Heal an ally up to 4 m away.', targetTeam: 'Allies', damageType: 'Magic',
        p: {power: 5, cast_range: 4, cooldown_turns: 1}, effects: [heal()], tags: ['fx:cure']},
      {name: 'Phoenix Down', description: 'Revive a knocked-out ally up to 4 m away with 40% HP (1 s).', targetTeam: 'Allies',
        p: {power: 0.4, cast_range: 4, cast_time: 1, cooldown_turns: 4}, effects: [heal()], tags: ['revive', 'fx:raise']},
      {name: 'Elixir Mist', description: 'Heal every ally within 3.5 m of a point up to 6 m away.', targeting: 'Circle', targetTeam: 'Allies', damageType: 'Magic',
        p: {power: 2.2, cast_range: 6, radius: 3.5}, effects: [heal()], tags: ['fx:sanctuary']},
    ], 'Violet, glass, copper', 'Flasks, bubbling potions'),

  cls('geomancer', 'Geomancer', '#8d6e3f', 'black_mage', 'geomancer', 'damage/support', 'Earth caster who shakes the ground and hardens allies.',
    {hp: 78, power: 15, aeva: 8, meva: 12, crit: 8, attdef: 9, magdef: 10, speed: 8, move: 6, patience: 7, sight: 9}, [
      {name: 'Rock Toss', description: 'Hurl a stone at an enemy 1-6 m away.', damageType: 'Magic',
        p: {power: 12, min_range: 1, cast_range: 6}, effects: [damage()], tags: ['fx:throw_stone']},
      {name: 'Quake', description: 'Shake every enemy within 3 m of a point 2-7 m away, Stunning for 1 s (2 s).', targeting: 'Circle', damageType: 'Magic',
        p: {power: 12, min_range: 2, cast_range: 7, radius: 3, cast_time: 2, cooldown_turns: 3, status_duration: 1},
        effects: [damage(), status('Stun')], tags: ['fx:earth_slash']},
      {name: 'Stone Skin', description: "Raise an ally's AttDef by 8 for 2 turns (up to 5 m, 1 s).", targetTeam: 'Allies',
        p: {cast_range: 5, cast_time: 1, cooldown_turns: 3, buff_attdef: 8, buff_turns: 2}, effects: [buff()], tags: ['fx:guard']},
      {name: 'Tectonic Rift', description: 'Split the earth under every enemy within 3.5 m of a point 3-10 m away; Slows for 6 s (3 s).', targeting: 'Circle', damageType: 'Magic',
        p: {power: 30, min_range: 3, cast_range: 10, radius: 3.5, cast_time: 3, status_duration: 2},
        effects: [damage(), status('Slow')], tags: ['fx:earth_slash']},
    ], 'Umber, moss, slate', 'Floating rocks, fissures'),

  cls('oracle', 'Oracle', '#b55db3', 'white_mage', 'oracle', 'special', 'Hexer who weakens and puts enemies to sleep.',
    {hp: 70, power: 17, aeva: 6, meva: 20, crit: 8, attdef: 5, magdef: 14, speed: 9, move: 6, patience: 9, sight: 11}, [
      {name: 'Hex', description: 'Dark bolt at an enemy 1-7 m away.', damageType: 'Magic',
        p: {power: 19, min_range: 1, cast_range: 7}, effects: [damage()], tags: ['fx:pin_shot']},
      {name: 'Curse', description: 'Lower an enemy\'s AttDef and MagDef by 6 for 2 turns (2-8 m, 1 s).',
        p: {min_range: 2, cast_range: 8, cast_time: 1, cooldown_turns: 3, buff_attdef: -6, buff_magdef: -6, buff_turns: 2}, effects: [debuff()], tags: ['fx:pin_shot']},
      {name: 'Sleep', description: 'Put an enemy 2-7 m away to sleep (Stun) for 3 s (2 s).',
        p: {min_range: 2, cast_range: 7, cast_time: 2, cooldown_turns: 3, status_duration: 1}, effects: [status('Stun')], tags: ['fx:haste']},
      {name: 'Divination', description: 'Every enemy on the field takes damage and is Slowed (2.5 s).', targeting: 'Global', damageType: 'Magic',
        p: {power: 10, cast_range: 20, cast_time: 2.5, status_duration: 3},
        effects: [damage(), status('Slow')], tags: ['fx:blizzard']},
    ], 'Plum, silver, starlight', 'All-seeing eyes, tarot cards'),

  cls('samurai', 'Samurai', '#e25b4a', 'knight', 'samurai', 'damage/support', 'Swordmaster with a spirit blade that hits all around.',
    {hp: 90, power: 16, aeva: 14, meva: 10, crit: 16, attdef: 9, magdef: 8, speed: 9, move: 7, patience: 6, sight: 9}, [
      {name: 'Iaido Slash', description: 'Quick-draw strike on an adjacent enemy.', damageType: 'Physical',
        p: {power: 21}, effects: [damage('Physical')], tags: ['fx:attack']},
      {name: 'Draw Out', description: 'Spirit blade hits every enemy within 2 m of you (1 s).', targeting: 'Self', damageType: 'Physical',
        p: {power: 16, radius: 2, cast_time: 1, cooldown_turns: 2}, effects: [damage('Physical')], tags: ['fx:holy_blade']},
      {name: 'Meditate', description: 'AttPwr +6 and MagDef +4 for 2 turns.', targeting: 'Self', targetTeam: 'Self',
        p: {cooldown_turns: 3, buff_power: 5, buff_magdef: 4, buff_turns: 2}, effects: [buff('Self')], tags: ['fx:focus']},
      {name: 'Masamune', description: 'Every ally within 4 m of you heals and gains Regen for 8 s.', targeting: 'Self', targetTeam: 'Allies', damageType: 'Magic',
        p: {power: 10, radius: 4, status_duration: 3}, effects: [periodic('Heal')], tags: ['fx:sanctuary']},
    ], 'Vermilion, black lacquer, steel', 'Katana arcs, cherry blossoms'),
];

for (const c of CLASSES) for (const a of c.entries) {
  const issues = validateAbility(a);
  if (issues.length) throw new Error(`${c.id} / ${a.name}: ${issues.join('; ')}`);
}

const lib = await (await fetch(API)).json();
const ours = new Set(CLASSES.map(c => `class:${c.id}`));
const others = lib.abilities.filter(a => !a.tags.some(t => ours.has(t)));
const next = {...lib, abilities: [...others, ...CLASSES.flatMap(c => c.entries)]};
const put = await fetch(API, {method: 'PUT', headers: {'content-type': 'application/json', 'x-astra-client': 'studio'}, body: JSON.stringify(next)});
const body = await put.json();
if (!put.ok) throw new Error(`Astra refused the save: ${body.error}`);
console.log(`Saved ${CLASSES.length} classes to Astra (revision ${body.revision}).`);

// Export exactly what Astra saved, one file per class.
const saved = await (await fetch(API)).json();
await mkdir(OUT_DIR, {recursive: true});
for (const c of CLASSES) {
  const exported = {...saved, abilities: saved.abilities.filter(a => a.tags.includes(`class:${c.id}`))};
  await writeFile(new URL(`${c.id}.astra.json`, OUT_DIR), JSON.stringify(exported, null, 2), 'utf8');
  console.log(`Exported ${c.id} (${exported.abilities.length} entries)`);
}
