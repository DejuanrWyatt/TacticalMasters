// Authors the Time Mage class in Astra Ability Creator through its local API,
// then writes the saved library's Time Mage entries to a Tactical Masters class file.
import {newAbility, parameter, effect, validateAbility} from 'file:///E:/Astra-Ability%20Creator/app/model.mjs';
import {writeFile, mkdir} from 'node:fs/promises';

const API = 'http://127.0.0.1:47261/api/library';
const OUT = 'D:/ProgramsByMe/TacticalMasters/data/classes/time_mage.astra.json';
const CLASS = 'class:time_mage';
const P = (name, base, step = 0, unit = '', mode = 'Static', extra = {}) => parameter(name, base, step, unit, mode, extra);
const E = (type, fields) => ({...effect(type), ...fields});

function make(fields, params, effects, tags) {
  const a = newAbility(fields.name);
  Object.assign(a, fields, {parameters: params, effects, tags: [CLASS, ...tags], status: 'Ready', resource: 'None'});
  a.visuals = {...a.visuals, palette: 'Indigo, pale gold, clockwork brass', motif: 'Clock faces, sand, frozen motes of light'};
  a.implementation = {engine: 'Godot 4', notes: 'Imported by Tactical Masters (scripts/core/astra_import.gd).'};
  return a;
}

const timeMage = [
  make({name: 'Time Mage', kind: 'Passive', targeting: 'Self', targetTeam: 'Self', damageType: 'None', element: 'Arcane',
    color: '#8a6cff', icon: 'orb', levels: 1, hotkey: '',
    description: 'Class profile: a fragile caster who bends the Turn Gauge. Stats are this entry\'s parameters.',
    notes: 'Tactical Masters class profile. hp, att, mag, attdef, magdef, wits, move, patience, sight.'},
    [P('HP', 65, 0, '', 'Static', {key: 'hp'}), P('AttPwr', 5, 0, '', 'Static', {key: 'att'}), P('MagPwr', 16, 0, '', 'Static', {key: 'mag'}),
     P('AttDef', 5, 0, '', 'Static', {key: 'attdef'}), P('MagDef', 11, 0, '', 'Static', {key: 'magdef'}),
     P('Wits', 12, 0, '', 'Static', {key: 'wits'}), P('Move', 6, 0, 'm', 'Static', {key: 'move'}),
     P('Patience', 7, 0, '', 'Static', {key: 'patience'}), P('Sight', 10, 0, 'm', 'Static', {key: 'sight'})],
    [E('Buff', {name: 'Class stats', trigger: 'Always', timing: 'Instant', amount: '0', damageType: 'None', target: 'Self', notes: 'Profile only.'})],
    ['profile', 'look:white_mage']),

  make({name: 'Chrono Bolt', kind: 'Active', targeting: 'Unit target', targetTeam: 'Enemies', damageType: 'Magic', element: 'Arcane',
    color: '#7f8cff', icon: 'orb', levels: 3, hotkey: 'Q',
    description: 'Instant bolt of stolen time at an enemy 1-7 m away; knocks its Turn Gauge back 10%.'},
    [P('Power', 1.0, 0, 'x MagPwr', 'Static', {overrides: {'1': '0.6 + 0.4 * rank', '2': '0.6 + 0.4 * rank', '3': '0.6 + 0.4 * rank'}}),
     P('Min range', 1, 0, 'm'), P('Cast range', 7, 0, 'm'), P('Cast time', 0, 0, 's'), P('Cooldown turns', 0, 0, 'turns'),
     P('TG change', -10, 0, '%', 'Static', {floorZero: false})],
    [E('Damage', {amount: 'power', notes: 'MagPwr x power, reduced by MagDef.'}),
     E('Debuff', {name: 'Rewind', amount: 'tg_change', notes: 'Turn Gauge change in percent.'})],
    ['slot:1', 'fx:pin_shot']),

  make({name: 'Slowga', kind: 'Active', targeting: 'Circle', targetTeam: 'Enemies', damageType: 'None', element: 'Arcane',
    color: '#5aa0ff', icon: 'orb', levels: 3, hotkey: 'W',
    description: 'Every enemy within 2.5 m of a point 2-8 m away is Slowed (Turn Gauge fills at half speed).'},
    [P('Min range', 2, 0, 'm'), P('Cast range', 8, 0, 'm'), P('Radius', 2.5, 0, 'm'), P('Cast time', 1.5, 0, 's'),
     P('Cooldown turns', 3, 0, 'turns'), P('Slow duration', 6, 1, 's', 'Time increase')],
    [E('Slow', {timing: 'Static', amount: '50', duration: 'slow_duration', damageType: 'None', notes: 'Turn Gauge fills at half speed.'})],
    ['slot:2', 'Crowd control', 'Area of effect', 'fx:haste']),

  make({name: 'Quicken', kind: 'Active', targeting: 'Unit target', targetTeam: 'Allies', damageType: 'None', element: 'Arcane',
    color: '#ffd166', icon: 'orb', levels: 3, hotkey: 'E',
    description: 'Push an ally\'s Turn Gauge forward by 40% (range 6 m) so it acts sooner.'},
    [P('Cast range', 6, 0, 'm'), P('Cast time', 1, 0, 's'), P('Cooldown turns', 3, 0, 'turns'), P('TG change', 40, 5, '%')],
    [E('Buff', {amount: 'tg_change', target: 'Allies', damageType: 'None', notes: 'Turn Gauge change in percent.'})],
    ['slot:3', 'Utility']),

  make({name: 'Time Stop', kind: 'Active', targeting: 'Circle', targetTeam: 'Enemies', damageType: 'Magic', element: 'Arcane',
    color: '#c9b8ff', icon: 'orb', levels: 3, hotkey: 'R',
    description: 'Freeze time around a point 3-9 m away: every enemy within 3 m takes damage and is Stunned for 2 s.'},
    [P('Power', 1.1, 0.1, 'x MagPwr', 'Flat increase'), P('Min range', 3, 0, 'm'), P('Cast range', 9, 0, 'm'), P('Radius', 3, 0, 'm'),
     P('Cast time', 2.5, 0, 's'), P('Cooldown turns', 0, 0, 'turns'), P('Stun duration', 2, 0.25, 's', 'Time increase')],
    [E('Damage', {amount: 'power'}),
     E('Stun', {timing: 'Static', amount: '0', duration: 'stun_duration', damageType: 'None'})],
    ['slot:4', 'Ultimate', 'Crowd control', 'fx:meteor']),
];

for (const a of timeMage) {
  const issues = validateAbility(a);
  if (issues.length) throw new Error(`${a.name}: ${issues.join('; ')}`);
}

const lib = await (await fetch(API)).json();
// Replace an earlier Time Mage (re-running this script) instead of duplicating it.
const others = lib.abilities.filter(a => !a.tags.includes(CLASS));
const next = {...lib, abilities: [...others, ...timeMage]};
const put = await fetch(API, {method: 'PUT', headers: {'content-type': 'application/json', 'x-astra-client': 'studio'}, body: JSON.stringify(next)});
const body = await put.json();
if (!put.ok) throw new Error(`Astra refused the save: ${body.error}`);
console.log(`Saved to Astra (revision ${body.revision}).`);

// Export exactly what Astra saved: the library, trimmed to the Time Mage.
const saved = await (await fetch(API)).json();
const exported = {...saved, abilities: saved.abilities.filter(a => a.tags.includes(CLASS))};
await mkdir('D:/ProgramsByMe/TacticalMasters/data/classes', {recursive: true});
await writeFile(OUT, JSON.stringify(exported, null, 2), 'utf8');
console.log(`Exported ${exported.abilities.length} entries to ${OUT}`);
