// The 90-class pack: ten roles x nine elements, each with its own name,
// ability names, stats and icon. Authors the classes in Astra Ability Creator
// through its local API, exports each one (as Astra saved it) to
// data/classes/<id>.astra.json and writes its icon to assets/icons/<id>.svg.
// Run with Astra open (Start Astra.cmd):
//   & "E:\Astra-Ability Creator\runtime\node.exe" tools/astra_class_pack.mjs
// Re-running replaces the pack in Astra instead of duplicating it.
//
// Numbers come from each role's template (sized against the built-in jobs);
// the element adjusts stats a little and adds its effect to the key abilities.
//
// Measured 2026-09-23 with tests/balance.gd (8 seeded games per class, three
// elements per role), as the average health margin against the reference team
// -- 0 would mean "as good as the Black Mage it replaces":
//   ranger +47  assassin +34  brawler -26  spellblade -25  cleric -40
//   summoner -43  minstrel -43  guardian -48  hexer -50  sorcerer -66
// So the pack as a whole is weaker than the built-in six, physical damage far
// outweighs magic, and the roles that hold a line or keep a team going are
// well behind. A pass of +-1 to +-3 Power and +-4 HP was tried and measured
// worse: the response isn't monotonic (one Power off a Ranger *raised* its
// margin by 21), because a stat crossing a threshold changes what the AI does
// with it. Whatever is tried next wants to be a large, deliberate change --
// ability Power, not class Power -- measured by margin, one role at a time.
import {newAbility, parameter, effect, validateAbility} from 'file:///E:/Astra-Ability%20Creator/app/model.mjs';
import {writeFile, mkdir} from 'node:fs/promises';

const API = 'http://127.0.0.1:47261/api/library';
const CLASS_DIR = new URL('../data/classes/', import.meta.url);
const ICON_DIR = new URL('../assets/icons/', import.meta.url);
const PACK_TAG = 'pack:roles-x-elements';

// --- Elements ------------------------------------------------------------
// hue/sat/light: class color. perk: what the element adds to an ability that
// hits enemies. ally: what it adds to buffs. regen: heals also give Regen.
const ELEMENTS = {
  fire: {adj: 'Flame', burst: 'Fireburst', ult: 'Inferno', beast: 'Salamander', hue: 16, sat: 80, light: 55,
    perk: {status: 'burn', turns: 2}, ally: {buff_power: 5}, curse: {buff_attdef: -6}, stats: {magdef: -1}, fx: 'fire', bigfx: 'meteor'},
  ice: {adj: 'Frost', burst: 'Hailstorm', ult: 'Absolute Zero', beast: 'Yeti', hue: 195, sat: 70, light: 62,
    perk: {status: 'slow', turns: 2}, ally: {buff_magdef: 6}, curse: {buff_speed: -3}, stats: {magdef: 2, speed: -1}, fx: 'blizzard', bigfx: 'blizzard'},
  lightning: {adj: 'Thunder', burst: 'Chain Lightning', ult: 'Tempest', beast: 'Thunderbird', hue: 52, sat: 90, light: 58,
    perk: {status: 'stun', turns: 1}, ally: {buff_speed: 2}, curse: {buff_magdef: -6}, stats: {speed: 1, hp: -2}, fx: 'holy_blade', bigfx: 'holy_blade'},
  earth: {adj: 'Stone', burst: 'Rockslide', ult: 'Cataclysm', beast: 'Golem', hue: 30, sat: 40, light: 48,
    perk: {status: 'stun', turns: 1}, ally: {buff_attdef: 6}, curse: {buff_move: -2}, stats: {hp: 8, attdef: 2, move: -1}, fx: 'earth_slash', bigfx: 'earth_slash'},
  wind: {adj: 'Gale', burst: 'Cyclone', ult: 'Hurricane', beast: 'Roc', hue: 150, sat: 55, light: 58,
    perk: {tg: -25}, ally: {tg_change: 20}, curse: {buff_speed: -3}, stats: {move: 1, speed: 1, hp: -2}, fx: 'haste', bigfx: 'blizzard'},
  water: {adj: 'Tide', burst: 'Riptide', ult: 'Tsunami', beast: 'Leviathan', hue: 212, sat: 75, light: 55,
    perk: {status: 'slow', turns: 2}, ally: {buff_magdef: 5}, curse: {buff_power: -6}, stats: {hp: 10, magdef: 1}, fx: 'blizzard', bigfx: 'blizzard', regen: true},
  holy: {adj: 'Holy', burst: 'Radiance', ult: 'Divine Wrath', beast: 'Seraph', hue: 46, sat: 85, light: 72,
    perk: {power: 1.1}, ally: {buff_attdef: 4, buff_magdef: 4}, curse: {buff_power: -6}, stats: {magdef: 2, hp: 2}, fx: 'holy_blade', bigfx: 'holy_blade', regen: true},
  shadow: {adj: 'Shadow', burst: 'Umbral Burst', ult: 'Eclipse', beast: 'Lich', hue: 272, sat: 45, light: 50,
    perk: {buffs: {buff_magdef: -6, buff_attdef: -3}}, ally: {buff_power: 4}, curse: {buff_attdef: -5, buff_magdef: -5}, stats: {crit: 2, meva: 3, attdef: -1}, fx: 'pin_shot', bigfx: 'meteor'},
  nature: {adj: 'Thorn', burst: 'Bramble Burst', ult: 'Wild Growth', beast: 'Treant', hue: 105, sat: 55, light: 50,
    perk: {status: 'burn', turns: 2}, ally: {buff_attdef: 3, buff_magdef: 3}, curse: {buff_attdef: -6}, stats: {hp: 6, patience: 1}, fx: 'throw_stone', bigfx: 'chakra', regen: true},
};

// --- Roles -----------------------------------------------------------------
// Each role: its category (role), character model (look), class names per element,
// a blurb for the class description, and its base stats.
const ROLES = {
  brawler: {role: 'damage', look: 'monk', physical: true, names: ['Ember Pugilist', 'Frost Brawler', 'Thunder Fist', 'Stone Fist', 'Gale Dancer', 'Tide Brawler', 'Temple Fist', 'Shade Brawler', 'Thorn Brawler'],
    blurb: 'Fast melee fighter', stats: {hp: 92, power: 17, aeva: 18, meva: 8, crit: 12, attdef: 8, magdef: 6, speed: 10, move: 8, patience: 5, sight: 9}},
  guardian: {role: 'tank/support', look: 'knight', physical: true, names: ['Flame Warden', 'Glacier Guard', 'Storm Bulwark', 'Mountain Sentinel', 'Sky Warden', 'Reef Guardian', 'Templar', 'Dread Knight', 'Oakheart'],
    blurb: 'Tank who shields allies', stats: {hp: 108, power: 14, aeva: 6, meva: 8, crit: 5, attdef: 13, magdef: 9, speed: 7, move: 6, patience: 8, sight: 8}},
  assassin: {role: 'damage', look: 'squire', physical: true, names: ['Cinder Blade', 'Frost Stalker', 'Volt Striker', 'Sand Viper', 'Wind Dancer', 'Tidecutter', 'Inquisitor', 'Shadow Stalker', 'Venom Fang'],
    blurb: 'Quick melee killer', stats: {hp: 84, power: 16, aeva: 24, meva: 10, crit: 20, attdef: 8, magdef: 7, speed: 11, move: 8, patience: 5, sight: 10}},
  ranger: {role: 'damage', look: 'archer', physical: true, names: ['Flame Archer', 'Frost Ranger', 'Storm Archer', 'Stone Slinger', 'Wind Archer', 'Harpooner', 'Sun Archer', 'Night Hunter', 'Beast Hunter'],
    blurb: 'Long-range physical damage', stats: {hp: 72, power: 15, aeva: 15, meva: 8, crit: 18, attdef: 6, magdef: 7, speed: 10, move: 7, patience: 6, sight: 13}},
  sorcerer: {role: 'damage', look: 'black_mage', physical: false, names: ['Pyromancer', 'Cryomancer', 'Stormcaller', 'Terramancer', 'Aeromancer', 'Hydromancer', 'Lumimancer', 'Necromancer', 'Druid'],
    blurb: 'Area magic damage', stats: {hp: 64, power: 18, aeva: 5, meva: 14, crit: 12, attdef: 4, magdef: 12, speed: 8, move: 6, patience: 8, sight: 10}},
  cleric: {role: 'support', look: 'white_mage', physical: false, names: ['Phoenix Priest', 'Frost Mender', 'Spark Medic', 'Earthmother', 'Wind Shaman', 'Tide Priest', 'Saint', 'Blood Cleric', 'Herbalist'],
    blurb: 'Healer who revives', stats: {hp: 66, power: 15, aeva: 5, meva: 16, crit: 5, attdef: 5, magdef: 13, speed: 8, move: 6, patience: 8, sight: 10}},
  minstrel: {role: 'support', look: 'squire', physical: false, names: ['War Drummer', 'Winter Skald', 'Thunder Herald', 'Stone Chanter', 'Piper', 'Siren', 'Cantor', 'Dirge Singer', 'Sylvan Muse'],
    blurb: 'Speeds up and buffs allies', stats: {hp: 74, power: 13, aeva: 10, meva: 12, crit: 8, attdef: 6, magdef: 10, speed: 10, move: 6, patience: 7, sight: 11}},
  hexer: {role: 'special', look: 'black_mage', physical: false, names: ['Ash Witch', 'Frost Witch', 'Arc Warlock', 'Dust Hexer', 'Tempest Hexer', 'Sea Witch', 'Exorcist', 'Warlock', 'Plague Doctor'],
    blurb: 'Weakens and puts enemies to sleep', stats: {hp: 72, power: 17, aeva: 6, meva: 18, crit: 10, attdef: 5, magdef: 13, speed: 9, move: 6, patience: 9, sight: 11}},
  summoner: {role: 'damage/support', look: 'black_mage', physical: false, names: ['Salamander Caller', 'Yeti Caller', 'Thunderbird Caller', 'Golem Master', 'Roc Caller', 'Leviathan Caller', 'Seraph Caller', 'Lich Caller', 'Treant Caller'],
    blurb: 'Slow caster of huge summons', stats: {hp: 62, power: 19, aeva: 5, meva: 14, crit: 10, attdef: 4, magdef: 12, speed: 7, move: 6, patience: 9, sight: 10}},
  spellblade: {role: 'tank/damage', look: 'knight', physical: false, names: ['Blazeblade', 'Frostblade', 'Stormblade', 'Earthshaker', 'Windblade', 'Tideblade', 'Crusader', 'Hexblade', 'Thornblade'],
    blurb: 'Melee fighter with blade magic', stats: {hp: 95, power: 13, aeva: 10, meva: 10, crit: 12, attdef: 10, magdef: 9, speed: 9, move: 7, patience: 6, sight: 9}},
};
const ELEMENT_ORDER = ['fire', 'ice', 'lightning', 'earth', 'wind', 'water', 'holy', 'shadow', 'nature'];

// Each role's four abilities (slot 4 is the ultimate). `atype` is Astra's
// ability type (Active, Toggle, Channeled, Aura, ...) and `shape` its
// targeting (Line, Cone, Vector, Global, ...); both reach the game.
// kind: 'dmg' (hits
// enemies; perk: true adds the element's effect), 'heal', 'revive', 'buff'
// (allies; the element's buff), 'debuff' (enemy stats), 'status' (enemy
// status only). phys: AttPwr instead of MagPwr.
const KITS = {
  brawler: e => [
    {name: `${e.adj} Jab`, kind: 'dmg', phys: true, text: 'Punch an adjacent enemy', p: {power: 15}, fx: 'punch'},
    {name: `${e.adj} Uppercut`, kind: 'dmg', phys: true, perk: true, text: 'A rising blow on an adjacent enemy', p: {power: 27, cooldown_turns: 2}, fx: 'wave_fist'},
    {name: `${e.adj} Stance`, kind: 'buff', self: true, atype: 'Toggle', text: 'Take a fighting stance', p: {buff_turns: 2}, fx: 'focus'},
    {name: `${e.adj} Fury`, kind: 'dmg', phys: true, perk: true, text: 'A flurry hitting every enemy within 2.5 m of you', p: {power: 32, radius: 2.5}, around: true, fx: 'earth_slash'},
  ],
  guardian: e => [
    {name: `${e.adj} Mace`, kind: 'dmg', phys: true, text: 'Strike an adjacent enemy', p: {power: 17}, fx: 'attack'},
    {name: `${e.adj} Bash`, kind: 'dmg', phys: true, perk: true, text: 'Shield-bash an adjacent enemy', p: {power: 15, cooldown_turns: 2}, fx: 'shield_bash'},
    {name: `${e.adj} Ward`, kind: 'buff', atype: 'Aura', around: true, text: 'Every ally within 4 m is shielded', p: {radius: 4, buff_turns: 2, buff_attdef: 5}, fx: 'guard'},
    {name: `${e.adj} Bastion`, kind: 'dmg', phys: true, perk: true, text: 'Slam the ground, hitting every enemy within 3 m of you', p: {power: 24, radius: 3, cast_time: 1}, around: true, fx: 'holy_blade'},
  ],
  assassin: e => [
    {name: `${e.adj} Dagger`, kind: 'dmg', phys: true, text: 'Stab an adjacent enemy', p: {power: 21}, fx: 'attack'},
    {name: `${e.adj} Kunai`, kind: 'dmg', phys: true, perk: true, text: 'Throw a blade at an enemy 2-8 m away', p: {power: 13, min_range: 2, cast_range: 8, cooldown_turns: 1}, fx: 'throw_stone'},
    {name: `${e.adj} Veil`, kind: 'status', status: 'slow', turns: 2, text: 'Slow every enemy within 2 m of a point 1-5 m away', p: {min_range: 1, cast_range: 5, radius: 2, cooldown_turns: 3}, fx: 'haste'},
    {name: `${e.adj} Execution`, kind: 'dmg', phys: true, perk: true, text: 'A killing blow on an adjacent enemy', p: {power: 54}, fx: 'brave_slash'},
  ],
  ranger: e => [
    {name: `${e.adj} Arrow`, kind: 'dmg', phys: true, text: 'Shoot an enemy 2-10 m away', p: {power: 11, min_range: 2, cast_range: 10}, fx: 'bow_shot'},
    {name: `${e.adj} Snipe`, kind: 'dmg', phys: true, shape: 'Line', text: 'A shot that pierces everyone in a line up to 13 m', p: {power: 23, min_range: 3, cast_range: 13, radius: 0.7, cast_time: 1, cooldown_turns: 1}, fx: 'aimed_shot'},
    {name: `${e.adj} Barb`, kind: 'dmg', phys: true, perk: true, text: 'A barbed arrow at an enemy 2-10 m away', p: {power: 9, min_range: 2, cast_range: 10, cooldown_turns: 2}, fx: 'pin_shot'},
    {name: `${e.burst} Volley`, kind: 'dmg', phys: true, perk: true, text: 'Arrows fall on every enemy within 2.5 m of a point 4-13 m away', p: {power: 21, min_range: 4, cast_range: 13, radius: 2.5, cast_time: 2}, fx: 'arrow_rain'},
  ],
  sorcerer: e => [
    {name: `${e.adj} Bolt`, kind: 'dmg', text: 'A bolt at an enemy 2-8 m away', p: {power: 29, min_range: 2, cast_range: 8, cast_time: 1}, fx: e.fx},
    {name: e.burst, kind: 'dmg', perk: true, text: 'Every enemy within 2 m of a point 2-8 m away', p: {power: 18, min_range: 2, cast_range: 8, radius: 2, cast_time: 2, cooldown_turns: 2}, fx: e.fx},
    {name: `${e.adj} Staff`, kind: 'dmg', phys: true, text: 'Strike an adjacent enemy', p: {power: 11}, fx: 'attack'},
    {name: e.ult, kind: 'dmg', perk: true, atype: 'Channeled', channel: 2, text: 'Every enemy within 3.5 m of a point 4-11 m away', p: {power: 22, min_range: 4, cast_range: 11, radius: 3.5, cast_time: 1}, fx: e.bigfx},
  ],
  cleric: e => [
    {name: `${e.adj} Rod`, kind: 'dmg', phys: true, text: 'Strike an adjacent enemy', p: {power: 9}, fx: 'attack'},
    {name: `${e.adj} Mend`, kind: 'heal', text: 'Heal an ally up to 6 m away', p: {power: 7, cast_range: 6, cast_time: 1}, fx: 'cure'},
    {name: `${e.adj} Rebirth`, kind: 'revive', text: 'Revive a knocked-out ally up to 5 m away with 30% HP', p: {power: 0.3, cast_range: 5, cast_time: 2, cooldown_turns: 4}, fx: 'raise'},
    {name: `${e.adj} Sanctuary`, kind: 'heal', regen: true, text: 'Heal every ally within 3.5 m of a point up to 8 m away', p: {power: 12, cast_range: 8, radius: 3.5, cast_time: 3}, fx: 'sanctuary'},
  ],
  minstrel: e => [
    {name: `${e.adj} Chord`, kind: 'dmg', text: 'A sharp chord at an enemy 1-7 m away', p: {power: 12, min_range: 1, cast_range: 7}, fx: 'pin_shot'},
    {name: `${e.adj} Anthem`, kind: 'tg', text: 'Every ally within 3 m of a point up to 6 m away gains 25% TG', p: {cast_range: 6, radius: 3, cast_time: 1.5, cooldown_turns: 3, tg_change: 25}, fx: 'haste'},
    {name: `${e.adj} Ballad`, kind: 'buff', atype: 'Aura', around: true, text: 'Every ally within 4 m is inspired', p: {radius: 4, buff_turns: 2}, fx: 'haste'},
    {name: `${e.adj} Finale`, kind: 'heal', regen: true, text: 'Heal every ally within 4 m of you', p: {power: 5, radius: 4, cast_time: 2}, around: true, fx: 'sanctuary'},
  ],
  hexer: e => [
    {name: `${e.adj} Hex`, kind: 'dmg', text: 'A curse-bolt at an enemy 1-7 m away', p: {power: 20, min_range: 1, cast_range: 7}, fx: 'pin_shot'},
    {name: `${e.adj} Curse`, kind: 'debuff', text: 'Weaken an enemy 2-8 m away for 2 turns', p: {min_range: 2, cast_range: 8, cast_time: 1, cooldown_turns: 3, buff_turns: 2}, fx: 'pin_shot'},
    {name: `${e.adj} Slumber`, kind: 'status', status: 'stun', turns: 1, text: 'Put an enemy 2-7 m away to sleep', p: {min_range: 2, cast_range: 7, cast_time: 2, cooldown_turns: 3}, fx: 'haste'},
    {name: `${e.adj} Doom`, kind: 'dmg', perk: true, text: 'Every enemy within 3.5 m of a point 3-10 m away', p: {power: 29, min_range: 3, cast_range: 10, radius: 3.5, cast_time: 2.5}, fx: e.bigfx},
  ],
  summoner: e => [
    {name: `${e.adj} Rod`, kind: 'dmg', phys: true, text: 'Strike an adjacent enemy', p: {power: 15}, fx: 'attack'},
    {name: `Summon ${e.beast}`, kind: 'dmg', perk: true, text: `The ${e.beast} strikes every enemy within 2 m of a point 3-9 m away`, p: {power: 27, min_range: 3, cast_range: 9, radius: 2, cast_time: 2, cooldown_turns: 2}, fx: e.fx},
    {name: `${e.beast} Pact`, kind: 'buff', text: 'Bless every ally within 3 m of a point up to 6 m away', p: {cast_range: 6, radius: 3, cast_time: 1, cooldown_turns: 3, buff_turns: 2}, fx: 'haste'},
    {name: `${e.beast} Ascendant`, kind: 'dmg', perk: true, text: 'Every enemy within 4 m of a point 4-11 m away', p: {power: 42, min_range: 4, cast_range: 11, radius: 4, cast_time: 4}, fx: e.bigfx},
  ],
  spellblade: e => [
    {name: `${e.adj} Slash`, kind: 'dmg', phys: true, text: 'Cut an adjacent enemy', p: {power: 18}, fx: 'attack'},
    {name: `${e.adj} Edge`, kind: 'dmg', perk: true, text: 'A spell-charged cut on an adjacent enemy', p: {power: 25, cooldown_turns: 2}, fx: 'holy_blade'},
    {name: `${e.adj} Lance`, kind: 'dmg', shape: 'Line', text: 'A spear of magic through everyone in a line up to 7 m', p: {power: 13, min_range: 2, cast_range: 7, radius: 0.7, cast_time: 1}, fx: e.fx},
    {name: `${e.adj} Maelstrom`, kind: 'dmg', perk: true, text: 'Blade magic hits every enemy within 2.5 m of you', p: {power: 29, radius: 2.5, cast_time: 1}, around: true, fx: e.bigfx},
  ],
};

// --- Building the Astra entries ----------------------------------------------
const NAMES = {power: 'Power', min_range: 'Min range', cast_range: 'Cast range', radius: 'Radius', cast_time: 'Cast time',
  cooldown_turns: 'Cooldown turns', tg_change: 'TG change', buff_turns: 'Buff turns', cone_angle: 'Cone angle', channel_turns: 'Channel turns', status_duration: 'Status turns',
  buff_power: 'Buff Power', buff_aeva: 'Buff A-Eva', buff_meva: 'Buff M-Eva', buff_crit: 'Buff Crit', buff_attdef: 'Buff AttDef', buff_magdef: 'Buff MagDef', buff_speed: 'Buff Speed', buff_move: 'Buff Move',
  hp: 'HP', power: 'Power', aeva: 'A-Eva', meva: 'M-Eva', crit: 'Crit', attdef: 'AttDef', magdef: 'MagDef', speed: 'Speed', move: 'Move', patience: 'Patience', sight: 'Sight'};
const UNITS = {min_range: 'm', cast_range: 'm', radius: 'm', cast_time: 's', status_duration: 'turns', cooldown_turns: 'turns', cone_angle: 'degrees', channel_turns: 'turns', tg_change: '%', move: 'm', sight: 'm', buff_turns: 'turns'};
const STAT_LABELS = {buff_power: 'Power', buff_aeva: 'A-Eva', buff_meva: 'M-Eva', buff_crit: 'Crit', buff_attdef: 'AttDef', buff_magdef: 'MagDef', buff_speed: 'Speed', buff_move: 'Move'};
const STATUS_EFFECT = {burn: 'Damage', slow: 'Slow', stun: 'Stun'};
const STATUS_WORD = {burn: 'Burns', slow: 'Slows', stun: 'Stuns'};

const round2 = v => Math.round(v * 100) / 100;
const params = values => Object.entries(values).map(([key, v]) => {
  const growth = key === 'power' ? 0.1 : 0;
  return parameter(NAMES[key], v, growth, UNITS[key] ?? '', growth ? 'Flat increase' : 'Static', {key, floorZero: false});
});
const E = (type, fields = {}) => ({...effect(type), damageType: 'None', amount: '0', ...fields});
const buffText = b => Object.entries(b).filter(([k]) => STAT_LABELS[k]).map(([k, v]) => `${STAT_LABELS[k]} ${v > 0 ? '+' : ''}${v}`).join(', ');

// One ability: its Astra fields, parameters, effects and tags, plus the game
// description (worked out from the numbers).
function buildAbility(ab, e, slot) {
  const p = {...ab.p};
  const effects = [];
  const extras = [];
  let damageType = 'None', targetTeam = 'Enemies', targeting = p.radius ? 'Circle' : 'Unit target';
  if (ab.around || ab.self) targeting = 'Self';
  if (ab.shape) targeting = ab.shape;
  const tags = [`fx:${ab.fx}`];
  if (ab.kind === 'dmg') {
    damageType = ab.phys ? 'Physical' : 'Magic';
    if (ab.perk && e.perk.power) p.power = round2(p.power * e.perk.power);
    effects.push(E('Damage', {amount: 'power', damageType}));
    if (ab.perk && e.perk.status) {
      p.status_duration = e.perk.turns;
      effects.push(E(STATUS_EFFECT[e.perk.status], e.perk.status === 'burn'
        ? {timing: 'Periodic', amount: 'power', duration: 'status_duration', tick: '1'}
        : {timing: 'Static', duration: 'status_duration'}));
      extras.push(`${STATUS_WORD[e.perk.status]} for ${e.perk.turns} turn${e.perk.turns === 1 ? '' : 's'}`);
    }
    if (ab.perk && e.perk.tg) {
      p.tg_change = e.perk.tg;
      effects.push(E('Debuff', {name: 'Knock back TG', amount: 'tg_change', target: 'Enemies'}));
      extras.push(`TG ${e.perk.tg}%`);
    }
    if (ab.perk && e.perk.buffs) {
      Object.assign(p, e.perk.buffs, {buff_turns: 2});
      effects.push(E('Debuff', {amount: '0', target: 'Enemies'}));
      extras.push(`${buffText(e.perk.buffs)} for 2 turns`);
    }
  } else if (ab.kind === 'heal') {
    targetTeam = 'Allies';
    damageType = 'Magic';
    if (ab.regen || e.regen) {
      p.status_duration = ab.regen ? 3 : 2;
      effects.push(E('Heal', {timing: 'Periodic', amount: 'power', duration: 'status_duration', tick: '1', target: 'Allies'}));
      extras.push(`Regen for ${p.status_duration} turns`);
    } else {
      effects.push(E('Heal', {amount: 'power', target: 'Allies'}));
    }
  } else if (ab.kind === 'revive') {
    targetTeam = 'Allies';
    tags.push('revive');
    effects.push(E('Heal', {amount: 'power', target: 'Allies'}));
  } else if (ab.kind === 'buff') {
    targetTeam = ab.self ? 'Self' : 'Allies';
    const perk = {...e.ally};
    for (const [k, v] of Object.entries(perk)) p[k] = (p[k] ?? 0) + v;
    effects.push(E('Buff', {amount: '0', target: targetTeam, notes: 'Stat changes from the buff_ parameters.'}));
    const stats = buffText(p);
    if (stats) extras.push(`${stats} for ${p.buff_turns} turns`);
    if (p.tg_change) extras.push(`TG +${p.tg_change}%`);
  } else if (ab.kind === 'tg') {
    targetTeam = 'Allies';
    effects.push(E('Buff', {name: 'Speed up', amount: 'tg_change', target: 'Allies'}));
  } else if (ab.kind === 'debuff') {
    Object.assign(p, e.curse);
    effects.push(E('Debuff', {amount: '0', target: 'Enemies'}));
    extras.push(buffText(e.curse));
  } else if (ab.kind === 'status') {
    p.status_duration = ab.turns;
    effects.push(E(STATUS_EFFECT[ab.status], {timing: 'Static', duration: 'status_duration'}));
    extras.push(`${STATUS_WORD[ab.status]} for ${ab.turns} turn${ab.turns === 1 ? '' : 's'}`);
  }
  const cast = p.cast_time ? ` (${p.cast_time} s)` : '';
  const type = ab.atype ?? 'Active';
  if (type === 'Channeled') p.channel_turns = ab.channel ?? 2;
  if (targeting === 'Cone') p.cone_angle = ab.angle ?? 70;
  const note = {Toggle: ' Switched on and off.', Aura: ' Always on, for allies nearby.',
    Channeled: ` Repeats for ${p.channel_turns} turns; the unit can't act meanwhile.`, Passive: ' Always on.'}[type] ?? '';
  const description = `${ab.text}${extras.length ? '; ' + extras.join(', ') : ''}.${cast}${note}`;
  return {fields: {name: ab.name, description, kind: type, targeting, targetTeam, damageType, element: e.adj}, p, effects, tags};
}

// Speed differences are pronounced: each class's Speed is spread twice as far
// from 8.5 (limited to 4-16), and a faster class trades 5 HP per Speed gained
// (a slower one gains them), so turns and toughness balance out.
function spreadSpeed(stats) {
  const speed = Math.min(16, Math.max(4, Math.round(8.5 + (stats.speed - 8.5) * 2)));
  return {...stats, speed, hp: stats.hp - (speed - stats.speed) * 5};
}

function hsl(h, s, l) {
  s /= 100; l /= 100;
  const k = n => (n + h / 30) % 12, a = s * Math.min(l, 1 - l);
  const f = n => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return '#' + [f(0), f(8), f(4)].map(x => Math.round(x * 255).toString(16).padStart(2, '0')).join('');
}
const slug = s => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

function buildClass(roleId, elementId, index) {
  const role = ROLES[roleId], e = ELEMENTS[elementId];
  const name = role.names[ELEMENT_ORDER.indexOf(elementId)];
  const id = slug(name);
  const tag = `class:${id}`;
  const roleIndex = Object.keys(ROLES).indexOf(roleId);
  const color = hsl(e.hue + (roleIndex % 3 - 1) * 8, e.sat, Math.min(80, e.light + (roleIndex % 4 - 1.5) * 5));
  // Stats: the role's, adjusted by the element.
  let stats = {...role.stats};
  for (const [k, v] of Object.entries(e.stats)) {
    stats[k] += v;
  }
  stats = spreadSpeed(stats);
  const entry = (fields, ps, effects, tags) => {
    const a = newAbility(fields.name);
    Object.assign(a, {color, icon: 'orb', status: 'Ready', resource: 'None', levels: fields.kind === 'Passive' ? 1 : 3, hotkey: ''},
      fields, {parameters: ps, effects, tags: [tag, PACK_TAG, ...tags]});
    a.visuals = {...a.visuals, palette: `${e.adj} tones`, motif: `${e.adj} ${roleId}`};
    a.implementation = {engine: 'Godot 4', notes: 'Imported by Tactical Masters (scripts/core/astra_import.gd).'};
    return a;
  };
  const description = `${role.blurb}, ${elementId} element.`;
  const entries = [entry({name, kind: 'Passive', targeting: 'Self', targetTeam: 'Self', damageType: 'None', element: e.adj, description},
    params(stats), [E('Buff', {name: 'Class stats', trigger: 'Always', target: 'Self', notes: 'Profile only.'})],
    ['profile', `look:${role.look}`, `role:${role.role}`])];
  KITS[roleId](e).forEach((ab, slot) => {
    const built = buildAbility(ab, e, slot);
    entries.push(entry(built.fields, params(built.p), built.effects, [`slot:${slot + 1}`, ...(slot === 3 ? ['Ultimate'] : []), ...built.tags]));
  });
  return {id, name, roleId, elementId, color, entries};
}

// --- Icons: the role's emblem in the class color, with an element badge ----
const GLYPHS = {
  brawler: c => `<rect x="17" y="20" width="32" height="30" rx="8" fill="${c}"/><rect x="17" y="10" width="8.5" height="19" rx="4.2" fill="${c}" stroke="#1b2130" stroke-width="1.5"/><rect x="25" y="8" width="8.5" height="21" rx="4.2" fill="${c}" stroke="#1b2130" stroke-width="1.5"/><rect x="33" y="9" width="8.5" height="20" rx="4.2" fill="${c}" stroke="#1b2130" stroke-width="1.5"/><rect x="41" y="12" width="8" height="17" rx="4" fill="${c}" stroke="#1b2130" stroke-width="1.5"/><rect x="9" y="28" width="20" height="10" rx="5" fill="${c}" stroke="#1b2130" stroke-width="1.5"/><rect x="23" y="48" width="20" height="10" rx="2" fill="${c}"/>`,
  guardian: c => `<path d="M32 4 L55 10 V29 C55 44 45 55 32 61 C19 55 9 44 9 29 V10 Z" fill="${c}"/><path d="M32 12 L47 16 V29 C47 40 40 48 32 53 C24 48 17 40 17 29 V16 Z" fill="none" stroke="#1b2130" stroke-width="3"/>`,
  assassin: c => `<g transform="rotate(40 32 32)"><path d="M32 2 L38 12 L36 40 L28 40 L26 12 Z" fill="${c}"/><rect x="18" y="40" width="28" height="5" rx="2" fill="${c}"/><rect x="29.5" y="45" width="5" height="12" fill="#1b2130"/><circle cx="32" cy="59" r="3.5" fill="${c}"/></g>`,
  ranger: c => `<path d="M20 4 C47 14 47 50 20 60" fill="none" stroke="${c}" stroke-width="5" stroke-linecap="round"/><line x1="20" y1="5" x2="20" y2="59" stroke="${c}" stroke-width="1.5"/><line x1="6" y1="32" x2="50" y2="32" stroke="${c}" stroke-width="3.5"/><polygon points="49,25 61,32 49,39" fill="${c}"/>`,
  sorcerer: c => `<path d="M14 44 L36 4 L46 44 Z" fill="${c}"/><ellipse cx="32" cy="45" rx="28" ry="7" fill="${c}"/><rect x="18" y="36" width="30" height="5" fill="#1b2130"/>`,
  cleric: c => `<circle cx="32" cy="14" r="10" fill="none" stroke="${c}" stroke-width="4"/><rect x="28" y="22" width="8" height="38" rx="2" fill="${c}"/><rect x="14" y="30" width="36" height="8" rx="2" fill="${c}"/>`,
  minstrel: c => `<path d="M18 6 C8 20 10 44 22 54 L42 54 C54 44 56 20 46 6 C44 18 40 22 32 22 C24 22 20 18 18 6 Z" fill="none" stroke="${c}" stroke-width="5" stroke-linejoin="round"/><line x1="26" y1="24" x2="26" y2="52" stroke="${c}" stroke-width="2"/><line x1="32" y1="24" x2="32" y2="52" stroke="${c}" stroke-width="2"/><line x1="38" y1="24" x2="38" y2="52" stroke="${c}" stroke-width="2"/><rect x="18" y="52" width="28" height="7" rx="2" fill="${c}"/>`,
  hexer: c => `<path d="M8 28 L56 28 C56 46 46 58 32 58 C18 58 8 46 8 28 Z" fill="${c}"/><rect x="5" y="24" width="54" height="7" rx="3" fill="${c}"/><circle cx="24" cy="16" r="5" fill="none" stroke="${c}" stroke-width="3"/><circle cx="38" cy="10" r="4" fill="none" stroke="${c}" stroke-width="3"/><circle cx="33" cy="20" r="2.5" fill="${c}"/>`,
  summoner: c => `<circle cx="32" cy="32" r="27" fill="none" stroke="${c}" stroke-width="4"/><circle cx="32" cy="32" r="18" fill="none" stroke="${c}" stroke-width="2" stroke-dasharray="4 3"/><polygon points="32,12 49,42 15,42" fill="none" stroke="${c}" stroke-width="3" stroke-linejoin="round"/>`,
  spellblade: c => `<path d="M32 2 L37 10 L37 42 L27 42 L27 10 Z" fill="${c}"/><rect x="17" y="42" width="30" height="6" rx="2" fill="${c}"/><rect x="29" y="48" width="6" height="11" fill="#1b2130"/><circle cx="32" cy="61" r="3" fill="${c}"/><path d="M32 16 L36 24 L32 32 L28 24 Z" fill="#1b2130"/>`,
};
const BADGES = {
  fire: c => `<path d="M53 42 C57 48 60 51 58 56 C57 60 49 60 48 56 C46 51 51 49 50 45 C53 49 53 51 53 54 C55 52 55 48 53 42 Z" fill="${c}"/>`,
  ice: c => `<g stroke="${c}" stroke-width="2.2" stroke-linecap="round"><line x1="53" y1="43" x2="53" y2="59"/><line x1="46" y1="47" x2="60" y2="55"/><line x1="46" y1="55" x2="60" y2="47"/></g>`,
  lightning: c => `<polygon points="55,42 47,52 52,52 49,60 58,49 53,49 57,42" fill="${c}"/>`,
  earth: c => `<polygon points="44,59 51,46 55,52 58,48 62,59" fill="${c}"/>`,
  wind: c => `<g fill="none" stroke="${c}" stroke-width="2.2" stroke-linecap="round"><path d="M45 48 H56 C60 48 60 43 56 43"/><path d="M45 53 H59"/><path d="M45 58 H54 C58 58 58 62 55 62"/></g>`,
  water: c => `<path d="M53 42 C57 49 60 52 60 55 C60 59 56 61 53 61 C50 61 46 59 46 55 C46 52 49 49 53 42 Z" fill="${c}"/>`,
  holy: c => `<circle cx="53" cy="52" r="4" fill="${c}"/><g stroke="${c}" stroke-width="2" stroke-linecap="round"><line x1="53" y1="42" x2="53" y2="45"/><line x1="53" y1="59" x2="53" y2="62"/><line x1="43" y1="52" x2="46" y2="52"/><line x1="60" y1="52" x2="63" y2="52"/></g>`,
  shadow: c => `<path d="M56 43 C49 44 46 49 46 53 C46 58 51 62 57 60 C52 58 50 55 50 52 C50 48 52 45 56 43 Z" fill="${c}"/>`,
  nature: c => `<path d="M46 60 C46 50 52 44 61 43 C61 53 55 59 46 60 Z" fill="${c}"/><line x1="46" y1="60" x2="56" y2="49" stroke="#1b2130" stroke-width="1.5"/>`,
};
function iconSvg(c) {
  const light = hsl(ELEMENTS[c.elementId].hue, ELEMENTS[c.elementId].sat, 78);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<g transform="scale(0.86)">${GLYPHS[c.roleId](light)}</g>
<circle cx="53" cy="52" r="11" fill="#1b2130" stroke="${light}" stroke-width="1.5"/>
${BADGES[c.elementId](c.color)}
</svg>
`;
}

// --- Author, save, export --------------------------------------------------------
const CLASSES = [];
for (const roleId of Object.keys(ROLES)) for (const elementId of ELEMENT_ORDER) CLASSES.push(buildClass(roleId, elementId));
const ids = new Set(CLASSES.map(c => c.id));
if (ids.size !== 90) throw new Error(`Expected 90 unique class ids, got ${ids.size}`);
for (const c of CLASSES) for (const a of c.entries) {
  const issues = validateAbility(a);
  if (issues.length) throw new Error(`${c.id} / ${a.name}: ${issues.join('; ')}`);
}

const lib = await (await fetch(API)).json();
const others = lib.abilities.filter(a => !a.tags.includes(PACK_TAG));
const next = {...lib, abilities: [...others, ...CLASSES.flatMap(c => c.entries)]};
const put = await fetch(API, {method: 'PUT', headers: {'content-type': 'application/json', 'x-astra-client': 'studio'}, body: JSON.stringify(next)});
const body = await put.json();
if (!put.ok) throw new Error(`Astra refused the save: ${body.error}`);
console.log(`Saved ${CLASSES.length} classes (${CLASSES.length * 5} entries) to Astra (revision ${body.revision}).`);

const saved = await (await fetch(API)).json();
await mkdir(CLASS_DIR, {recursive: true});
await mkdir(ICON_DIR, {recursive: true});
for (const c of CLASSES) {
  const exported = {...saved, abilities: saved.abilities.filter(a => a.tags.includes(`class:${c.id}`))};
  if (exported.abilities.length !== 5) throw new Error(`${c.id}: expected 5 saved entries, found ${exported.abilities.length}`);
  await writeFile(new URL(`${c.id}.astra.json`, CLASS_DIR), JSON.stringify(exported, null, 2), 'utf8');
  await writeFile(new URL(`${c.id}.svg`, ICON_DIR), iconSvg(c), 'utf8');
}
console.log(`Exported ${CLASSES.length} class files and icons.`);
