# Tactical Masters

A real-time-with-countdowns 3D tactics game inspired by Final Fantasy Tactics (jobs, Turn Gauge)
and Baldur's Gate 3 (free movement, ranges in meters). Built with **Godot 4.3+** (GDScript).

## Running it

1. Open Godot (installed at `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe`).
2. Choose **Import** and select `project.godot` in this folder.
3. Press **F5** (Run Project).

### Building a Windows .exe

The Godot 4.7.2 export templates are installed, and `export_presets.cfg` has a "Windows Desktop" preset. Build with:

```
godot --headless --export-release "Windows Desktop" build/TacticalMasters.exe
```

(or **Project → Export** in the editor). The result is a single ~115 MB `build/TacticalMasters.exe` with everything
embedded; copy it anywhere and double-click to play. Add `-- autostart` on the command line to jump straight into a
battle vs the computer. Its log is in `%APPDATA%\Godot\app_userdata\Tactical Masters\logs\godot.log`.

## Controls

| Action | Keys / mouse |
|---|---|
| Select one of your READY units | Click it, click its chip in the turn order bar, or press Tab |
| Move | Space (on by default), then click inside the blue area. Dots show the path. |
| Sprint | Shift, then click: walks 125% of the unit's Move, but counts as its action, so no ability that turn. |
| Use ability 1-4 | 1-4, then click a unit **or the ground**. Orange rings show the range, the red circle shows the area hit. Clicking something **out of range** walks the unit as far as it needs to and uses the ability on arrival, at the spot the target was standing on: if it has moved on by then, the blow misses. |
| End the unit's turn | Enter |
| Cancel | Esc |
| Pause (not online) | P |
| Chat (online) | T, type, Enter to send (Esc closes) |
| Combat log | L or the Log button shows / hides it. Drag its title bar to move it, its corner to resize it; – collapses it. Units appear as their class icons (hover one for its name), and each part of a line takes the color of what it says: damage in red, healing and buffs in green, ability names in gold, and the words joining them in grey. The cog picks every one of those colors, the text size and the background opacity. It keeps the whole battle's messages (scroll up for older ones) and remembers its place. |
| What an ability does | Hover its button: the description, type, shape, range, cast time and the damage or healing it would do appear above the action bar straight away. |
| Everyone on the field | The **Field** button lists both teams: icon, health, statuses and whether each unit is ready. Click a row to pick that unit. |
| What an enemy could do | Click it (or its chip): its stats card opens, and the ground it could walk to plus the reach of its longest attack are drawn in red. |
| What is on its way | While a spell is in the air, the card of any unit standing where it will land shows the **caster's icon** beside the **ability's icon**, under the card. Standing on the spot is enough — it doesn't have to be the target. Hover a pair for who is casting what. |
| Unit Guide (stats, abilities, damage) | U, or the **Units** button. Also on the main menu. Pauses the game when not online. |
| Camera | WASD / arrows pan · R / F raise / lower · Q / E or right-drag rotate and tilt · wheel zoom · middle-drag pan · C center on the selected unit. The camera never moves by itself: press C, or click a unit's chip in the turn order (a second click on your selected unit's chip centers on it). |
| Edit layout | **Menu → Edit layout**: every panel gets a handle you can drag -- turn order, each team's turn cards, the objective line, the planning banner, the selected unit, the action bar, the hover preview, the field list and the stats cards. A turn card dragged along its team's row changes its place in it. **Reset layout** puts everything back. What you arrange is kept for every battle after (`user://layout.cfg`), and the battle holds while you arrange it. |
| Menu (in battle) | **Menu** button: Resume, Options, Unit Guide, How to Play, Edit layout, Surrender, Quit to Main Menu (pauses when not online) |

These are the default keys. Every keyboard control can be rebound in **Options** (main menu, or Menu → Options in battle):
click an action, then press a key. If another action already uses that key, the two swap. Bindings are saved between sessions.

**Options → Game** also has master / music / sound-effect volume, camera speed, UI scale, fullscreen,
**colorblind team colors** (blue / orange), and **turn order as fixed squares** (one card per unit, grouped by team,
each group placed wherever you like in Edit layout) -- one square per unit instead of
chips sliding along a bar: gold with a flashing border while that unit can act and its countdown drains, grey with a
red meter filling from the bottom while its gauge refills. Settings are saved (`user://settings.cfg`). New players: **How to Play**
(main menu or in-game menu) walks through the rules page by page.

## After the battle

The victory screen shows each unit's **damage dealt, taken and avoided** (evaded or soaked by a Shield), **healing,
KOs, abilities used, critical hits, evasions, and buffs and debuffs applied**, per-team totals, how long the battle
ran, and the **MVP** (which counts damage taken, not only damage dealt: the unit that stood in front counts too).
Sides are told apart by **color** rather than by the words Blue and Red. **Rematch** replays the same map and teams; **Watch Replay** plays
the whole battle back (every order is recorded, and the rules are deterministic, so the replay is exact), with
×1 / ×2 / ×4 speed, a **scrub bar** to jump to any point (it is replayed from the start to get there, so it is still
exact), **Pause / Play**, **Back** to rewind one order, **Step** for one order at a time and **Results** to skip to
the end.

## How it plays

- **Time keeps running.** Every unit's **Turn Gauge (TG)** fills at a rate set by its **Speed**: a Speed-10 unit gets a
  turn every 20 s, and slower units less often. A unit with a full gauge is
  **READY** and can act right away. Several units, from both sides, can be ready at the same time, and both players act at once.
- **Each ready unit has its own countdown**: 8 s + 2 s × **Patience** (18-24 s). It appears on the unit's chip in the turn order bar
  (`READY 12s`) and above the unit's head. If it runs out, that unit's turn is lost and its TG resets to 0.
- **Turn order bars** (top of the screen): one bar per team, Blue above Red. Each unit's chip slides along its
  team's bar toward the READY zone at the left end, placed by the seconds until it's ready. Each chip is a uniform
  square with the unit's **class icon**; its name and any spell being cast are in its tooltip, and a small badge shows
  the time (gold READY countdown, purple cast, or white time until ready). The icons sit right on the bar at each
  unit's time. When two or more come close together they merge into one framed group, side by side around their average
  time; each icon in a group can still be clicked on its own.
  The last seconds before READY get the most room, and ticks mark 1, 3, 5, 10, 20 and 30 s. A chip grows as its turn gets closer and is full size once READY.
  The seconds until ready show on the chip for 3 s after the unit's turn ends, in the last 3 s before it's ready,
  and while the mouse is over the chip.
- **Stats cards:** click a unit that isn't taking orders (an enemy, or an ally that isn't READY), or its chip, to see
  its stats, gauges, statuses and abilities. Each ability shows its **icon** and is colored by what it is for --
  physical attack, magic attack, healing, buff / debuff or utility -- with a **legend** under the list. Allies show on the left, enemies on the right. Click it again, click the
  ground or press × to close. Hover the numbers for their calculations.
- On its turn a unit can **walk once** (up to its Move in meters, around water, cliffs and enemies) and **use one ability**,
  in either order. Skipping one keeps some TG, so the next turn comes sooner. A turn that used **no ability at all**
  fills that unit's gauge **25% faster** until its next turn, so holding back is worth something.
- **Sprint** (Shift, or the button) walks **125%** of the unit's Move but spends its action as well: distance instead
  of a blow.
- **Engagement:** every unit engages the ground within **1.8 m** of it. Walking into an enemy's reach is free, but
  stepping back out of it costs **1 m** of movement, so a fight can't be left for nothing.
- **Bars over every unit's head:** HP (green, red when low), TG (blue, gold when READY), Ultimate (orange, pale gold when full).
- **At every unit's feet:** a filled circle in its **team's color** (its size is a Developer Tools slider), ringed by a
  **dial** that fills as its turn comes round and empties while its countdown runs out (purple while casting, red in
  the last five seconds). Over its head it says only what it is doing -- **READY**, or the spell it is casting -- since
  the dial and the turn order carry the timing.
- **Cast times:** basic attacks, most melee and quick shots are **instant**. Stronger abilities take time to cast:
  0.5-1.5 s for abilities like Fire, Cure and Aimed Shot, and 2-4 s for Blizzard, Arrow Rain, Sanctuary and Meteor.
  A unit can move **before** casting, but not after. Only **instant** abilities let a unit move afterwards, so
  starting a cast ends the unit's turn. The cast carries on, and its TG doesn't fill until the spell goes off.
  The caster's TG bar becomes a
  purple cast bar, and its chip shows e.g. `Meteor 2.3s`. A purple circle marks where the spell will land.
  **Aim at a unit** and the spell follows it. **Aim at the ground** and it lands on that spot, hitting whoever is there
  when it goes off. Use this to predict where an enemy will walk, and remember that targets can also walk out of it.
  If the caster is defeated mid-cast, the spell fizzles.
- **Ultimate:** ability 4 unlocks when the Ultimate bar is full. The bar fills when the unit uses abilities, gets hit,
  and a little each time it becomes ready.
- **Fog of war:** you only see what is within the **Sight** radius (meters) of your units, and only where terrain doesn't
  block the view (hills hide units behind them). Hidden enemies show as `???`.
- **Height:** units can climb at most 2 levels at once. Attacking from higher ground adds 10% damage per level (max 30%).
- **Facing:** units face where they last walked or aimed. Hits from the **side deal +10%**, from **behind +25%**.
- **Line of sight:** ranged abilities (reach beyond 1.8 m) need a clear line over the terrain; the targeting hint says
  "No line of sight" when a hill is in the way.
- **Status effects** (tags over the unit's head) last a number of the affected unit's **own turns**: they act and count
  down when its turn comes.

| Tag | Status | What it does |
| --- | --- | --- |
| BRN | Burn | −10% of max HP at the start of each of its turns |
| BLE | Bleed | −6% of max HP a turn |
| RGN | Regen | +10% of max HP a turn |
| SLW | Slow | Turn Gauge fills at half speed |
| STN | Stun | takes the turn it is caught in, and leaves its gauge 75% full |
| SHD | Shield | soaks damage before HP, and breaks when it is used up |
| BAR | Barrier | soaks the same way, and stacks with a Shield |
| ROT | Root | can't walk, can still act |
| CRP | Crippled | walks only half as far |
| STR | Stride | walks half again as far |
| SIL | Silence | can't use abilities, can still walk |
| BLN | Blind | its own attacks are 25% more likely to be evaded |
| SHR | Shred | AttDef and MagDef cut to 60%, so everything hits harder |
| SLP | Sleep | loses its turns, but any damage wakes it at once |
| FRZ | Freeze | pinned and unable to act, but AttDef and MagDef tripled |
| KND | Knockdown | may walk or act on its turn, not both |
| DOM | Doom | when the count runs out the unit falls, at any health |
| TNT | Taunt | its damaging abilities must include whoever taunted it, while that one is in reach |
| FLY | Fly | crosses any height, and melee abilities can't reach it |
| IMM | Immunity | clears every harmful status, and turns new ones away |
| INV | Invulnerable | takes no damage at all |
| RLN | Relentless | takes another turn the moment this one ends, then wears off |

  A class imported from Astra can apply any of these with a `status:<id>` tag on the ability, e.g. `status:blind` or
  `status:doom:3` to set how many turns it lasts.
- **Mending:** a unit that goes **2 of its own turns without taking damage** regains **5% of its max HP** at the
  start of each turn after that, until something hurts it again. Breaking off to let a unit recover is a real option.
  All three numbers are in Developer Tools.
- **The ground itself:** **embers** burn a unit that starts its turn on them and **springs** heal one, both by 8% of
  its max HP (Developer Tools), and **rocks** can't be walked through and hide whatever is behind them. The
  **Ashfields** map is built around them.
- **Planning stage** (Battle Setup, off by default): for 30, 60 or 90 seconds before anyone acts, each side may put
  its units anywhere in its own spawn area. No gauge fills meanwhile. Click one of your units to see the ground you
  may use, click there to place it, and **Ready** starts the battle early once both sides have said so.
- **Winning:** by default the last team standing wins. Battle Setup can add a **time limit** (when it runs out the
  side with the greater share of its health left wins, and level shares are a **draw**) and **holding the middle**
  (stand alone inside the gold ring for 30 or 60 s). The line under the turn bars shows both. The in-game menu also
  has **Surrender**, which asks once and hands the battle to the other side.
- **Knock-outs:** a unit at 0 HP is **knocked out** for 12 s (it lies on the field with a `KO` countdown). The White
  Mage's **Raise** (replaces Staff Strike) revives it with 30% HP; otherwise it's gone. KO'd units don't count as alive.

There is no Power stat: what an ability does is the ability's own number and nothing else. What the stat used
to add was folded into each ability, so the numbers are what they always were.

Damage = (the ability's own **Power** × height bonus − AttDef (physical) or MagDef
(magic)) × 0.5, minimum 1. The final × 0.5 is the damage multiplier in Developer Tools, the quickest dial for overall damage.

Two rolls decide the rest: the target's **A-Eva** (physical) or **M-Eva** (magic) is its chance to evade the ability
completely (a MISS), and the user's **Crit** chance multiplies the damage by 1.5. Baselines are 5%; nimble classes reach
about 30%. Both are rolled from the battle's own seed — only while a command is actually played — so a replay and both
players online see exactly the same hits and misses.

## Classes: roles, ability types and target shapes

Every class has a **role** — Tank, Damage, Support or Special, or a pair like Tank/Support — shown with an icon in the
Unit Guide, which can also **search, filter by role and sort** its 107 classes. A class that doesn't state a role gets
one worked out from its stats and abilities.

Each ability has a **type** and a **target shape**, both taken from Astra Ability Creator:

| Type | What it means |
|---|---|
| Active | Used on the unit's turn (most abilities) |
| Passive | Always on; its buffs apply from the start and it can't be used |
| Toggle | Switched on and off (once a turn); its buffs apply while on |
| Channeled | Repeats on each of the next turns; the unit can't act meanwhile |
| Active + Passive | Always on, and usable as well |
| Aura | Always on; reaches everyone of the target side within its radius |

| Shape | What it covers |
|---|---|
| Unit / Point | One unit, or whoever stands on the spot |
| Circle | Everyone within the radius of the aimed point |
| Self | Centred on the user (with a radius, everyone around it) |
| Line | Everyone along the line out to its range (it skewers) |
| Cone | Everyone inside the arc in front of the user |
| Global | Everyone on the field |
| Vector | Like a line, and the user ends up at the far end (a dash) |

Every ability also has its own **icon** (a glyph for what it does plus a mark for its shape), shown on the action bar
and in the Unit Guide.

## Battle Setup: maps and teams

Every game starts with **Battle Setup**: pick the **map**, each side's **4 classes**, and the computer's **difficulty**.
A host picks for both sides, and the joining player gets the same settings.

- **Class picker:** clicking a slot opens a picker over all 107 classes that can be **searched**, **filtered by role**
  and **sorted** (the same rules as the Unit Guide), showing each class's icon, roles and key stats, and the four
  abilities of whichever class is highlighted.
- **Random** builds a team worth fielding — a tank, two damage dealers and a support — rather than four classes out
  of the hat; **Default** puts back the starting four.
- **Saved teams:** name a team and **Save** it, then load it from the dropdown on either side later, or **Delete**
  it. They are kept in `user://teams.cfg`.
- **Victory**, **Time** and **Planning** choose how the battle ends and whether it begins with a placing stage
  (see *How it plays*), and **Seed** repeats a battle exactly:
  the same seed with the same teams plays out the same way. 0 means a new battle every time.

| Map | What it's like |
|---|---|
| **Highlands** | Rolling hills with a high ridge on each flank. Take the high ground. |
| **River Crossing** | A river splits the field; two narrow bridges are the only way across. |
| **Fortress** | A raised central plateau reachable only by ramps; stone pillars block line of sight. |
| **Ashfields** | Embers burn whoever lingers on them, springs heal, and rocks hide what is behind them. |
| **Open Plains** | Flat and open with a few low hills. |

Maps are 24 × 24 m and point-symmetric (fair for both sides). They're defined as height rows in `scripts/core/map_data.gd`
(`MAPS`); adding a map is adding an entry there.

## Jobs

The default team is Knight, Archer, Black Mage and White Mage (`Jobs.DEFAULT_ROSTER`); Squire and Monk are also
available in Battle Setup. Move and Sight are in meters.

| Class | Role | HP | AttDef | MagDef | A-Eva | M-Eva | Crit | Speed | Move | Patience | Sight |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Squire | Damage | 75 | 8 | 6 | 8% | 5% | 8% | 10 | 7 | 6 | 9 |
| Knight | Tank / Damage | 105 | 12 | 6 | 5% | 5% | 5% | 6 | 6 | 7 | 8 |
| Archer | Damage | 60 | 6 | 7 | 15% | 8% | 15% | 12 | 7 | 6 | 13 |
| Monk | Damage / Support | 80 | 8 | 5 | 18% | 8% | 12% | 12 | 8 | 5 | 9 |
| Black Mage | Damage | 60 | 4 | 12 | 5% | 12% | 10% | 8 | 6 | 8 | 10 |
| White Mage | Support | 65 | 5 | 13 | 5% | 15% | 5% | 8 | 6 | 8 | 10 |

| Job | 1 | 2 | 3 | 4 (Ultimate) |
|---|---|---|---|---|
| Squire | Attack | Throw Stone | Focus (Crit up) | Brave Slash |
| Knight | Attack | Shield Bash (TG −30%, Stun) | Guard (defense up) | Holy Blade (area, 1 s) |
| Archer | Bow Shot | Aimed Shot (1 s) | Pin Shot (TG −40%) | Arrow Rain (area, 2 s) |
| Monk | Punch | Wave Fist | Chakra (area heal + Regen) | Earth Slash (area around self, 1 s) |
| Black Mage | Staff Strike | Fire (Burn, 1 s) | Blizzard (area, Slow, 2 s) | Meteor (large area, 4 s) |
| White Mage | Raise (revive, 2 s) | Cure (1 s) | Haste (TG +50%, 1.5 s) | Sanctuary (large area heal + Regen, 3 s) |

Abilities without a time are instant. The in-game **Unit Guide** lists every class's stats and, for the class picked in its Class dropdown (or clicked in the
stats table), every ability's numbers, including its damage against any class you pick.

Each ability has its own animation (`scripts/battle/fx.gd`). Melee abilities lunge, arrows and fireballs fly in arcs,
Arrow Rain and Blizzard fall on the area, Meteor drops from the sky, Holy Blade brings down a pillar of light, and heals sparkle.

**Speed makes a big difference:** from 4 (a turn about every 50 s) to 16 (about every 12.5 s). Faster classes
trade some HP for it: 3 HP per point of Speed above the middle, and slower ones gain it.

**Changing class stats:** in the **Unit Guide** on the main menu, click any stat to change it; changed stats are gold.
The number box goes up to each stat's limit, **Default** puts back the class's own value, and **Reset class** / **Reset
all stats** undo more. Changes are saved (`user://class_stats.cfg`) and used by every new battle; online matches use
the host's, sent to the other player. A replay uses the stats its battle started with. In a battle the guide only
shows them.

All numbers are in `scripts/core/jobs.gd` (jobs and abilities) and at the top of `scripts/core/game_state.gd`
(time, countdown, damage, height and movement rules). The main rule numbers can also be changed in **Developer Tools**.

### Imported classes (made in Astra Ability Creator)

101 more classes were designed in **Astra Ability Creator** (`E:\Astra-Ability Creator`). Each lives there as five
library entries tagged `class:<id>`, and the game reads Astra's JSON exports in `data/classes/`.

| Class | Role | HP | AttDef | MagDef | A-Eva | M-Eva | Crit | Speed | Move | Patience | Sight | Plays like |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Time Mage | Special | 58 | 5 | 11 | 10% | 16% | 10% | 16 | 6 | 7 | 10 | Turn Gauge control |
| Dragoon | Damage | 95 | 11 | 5 | 12% | 6% | 12% | 8 | 7 | 6 | 9 | Leaps onto distant targets |
| Ninja | Damage | 80 | 10 | 7 | 26% | 10% | 22% | 14 | 8 | 5 | 10 | Fast melee assassin |
| Summoner | Damage | 63 | 4 | 12 | 5% | 14% | 10% | 6 | 6 | 9 | 10 | Slow, huge area magic |
| Paladin | Tank / Support | 105 | 13 | 9 | 6% | 10% | 5% | 8 | 6 | 8 | 8 | Tank, heals and shields |
| Bard | Support | 60 | 6 | 10 | 10% | 12% | 8% | 12 | 6 | 7 | 11 | Speeds allies, slows enemies |
| Berserker | Damage | 115 | 7 | 4 | 8% | 5% | 18% | 8 | 7 | 4 | 8 | Heavy damage, weak defense |
| Chemist | Support | 70 | 7 | 8 | 10% | 10% | 8% | 10 | 6 | 7 | 9 | Bombs, potions, revives |
| Geomancer | Damage / Support | 78 | 9 | 10 | 8% | 12% | 8% | 8 | 6 | 7 | 9 | Earth magic, stuns |
| Oracle | Special | 65 | 5 | 14 | 6% | 20% | 8% | 10 | 6 | 9 | 11 | Debuffs and sleep |
| Samurai | Damage / Support | 85 | 9 | 8 | 14% | 10% | 16% | 10 | 7 | 6 | 9 | Area sword, team Regen |

| Class | 1 | 2 | 3 | 4 (Ultimate) |
|---|---|---|---|---|
| Time Mage | Chrono Bolt (TG −10%) | Slowga (area Slow, 1.5 s) | Quicken (ally TG +40%, 1 s) | Time Stop (area + Stun, 2.5 s) |
| Dragoon | Lance (2.2 m reach) | Jump (dashes onto a target 3-7 m away) | Dragon Spirit (Crit up) | Highwind (area, 2 s) |
| Ninja | Twin Strike | Shuriken (2-8 m) | Smoke Bomb (area Slow) | Assassinate |
| Summoner | Rod | Ifrit (area + Burn, 2 s) | Carbuncle (area MagDef up, 1 s) | Bahamut (huge area, 4 s) |
| Paladin | Holy Strike | Aegis (ally AttDef up) | Lay on Hands (heal, 1 s) | Judgment (area around self, 1.5 s) |
| Bard | Dissonance (1-7 m) | Song of Haste (area TG +25%, 1.5 s) | Lullaby (area Slow, 1.5 s) | Hymn of Life (heal + Regen around self, 2 s) |
| Berserker | Cleave (90° cone) | Rage (toggle: Crit +16%, AttDef −4) | Leap Smash (area + Stun, 1 s) | Rampage (area around self) |
| Chemist | Fire Bomb (area + Burn) | Potion (heal) | Phoenix Down (revive, 1 s) | Elixir Mist (area heal) |
| Geomancer | Rock Toss (1-6 m) | Quake (area + Stun, 2 s) | Stone Skin (ally AttDef up, 1 s) | Tectonic Rift (area + Slow, 3 s) |
| Oracle | Hex (1-7 m) | Curse (AttDef/MagDef −6, 1 s) | Sleep (Stun a turn, 2 s) | Divination (everyone on the field + Slow, 2.5 s) |
| Samurai | Iaido Slash | Draw Out (area around self, 1 s) | Meditate (Crit/MagDef up) | Masamune (heal + Regen around self) |

#### The 90-class pack: 10 roles × 9 elements

Every combination of a **role** and an **element** is its own class, with its own name, ability names, color and icon.
The icon is the role's emblem in the element's colors, with an element badge.

| Role | Fire | Ice | Lightning | Earth | Wind | Water | Holy | Shadow | Nature |
|---|---|---|---|---|---|---|---|---|---|
| Brawler (fast melee) | Ember Pugilist | Frost Brawler | Thunder Fist | Stone Fist | Gale Dancer | Tide Brawler | Temple Fist | Shade Brawler | Thorn Brawler |
| Guardian (tank) | Flame Warden | Glacier Guard | Storm Bulwark | Mountain Sentinel | Sky Warden | Reef Guardian | Templar | Dread Knight | Oakheart |
| Assassin (melee killer) | Cinder Blade | Frost Stalker | — | Sand Viper | Wind Dancer | — | Inquisitor | Shadow Stalker | — |
| Ranger (long range) | — | Frost Ranger | — | Stone Slinger | Wind Archer | — | Sun Archer | Night Hunter | Beast Hunter |
| Sorcerer (area magic) | — | Cryomancer | Stormcaller | — | Aeromancer | — | Lumimancer | Necromancer | Druid |
| Cleric (healer) | — | — | — | — | — | — | — | Blood Cleric | Herbalist |
| Minstrel (buffs, TG) | War Drummer | Winter Skald | Thunder Herald | Stone Chanter | Piper | Siren | Cantor | Dirge Singer | Sylvan Muse |
| Hexer (debuffs, sleep) | Ash Witch | Frost Witch | Arc Warlock | Dust Hexer | Tempest Hexer | Sea Witch | Exorcist | Warlock | — |
| Summoner (huge summons) | Salamander Caller | Yeti Caller | Thunderbird Caller | Golem Master | Roc Caller | Leviathan Caller | Seraph Caller | Lich Caller | Treant Caller |
| Spellblade (magic melee) | Blazeblade | Frostblade | — | Earthshaker | Windblade | — | Crusader | Hexblade | — |

A dash is a combination that no longer exists: where an element made no difference to a role's kit, those
classes had the same four abilities as each other and only one of each set was kept. Clerics lost the most,
since healing abilities take no elemental effect at all.

- **Role:** sets the base stats and the four-ability kit, sized against the built-in jobs.
- **Element:** nudges the stats and adds its own effect to the role's key abilities:
  - fire and nature: Burn
  - ice and water: Slow
  - lightning and earth: Stun
  - wind: knocks the target's Turn Gauge back 25%
  - shadow: MagDef −6 and AttDef −3
  - holy: +10% power
- **Ally buffs** also follow the element. Water, holy and nature heals add Regen.
- **Tooltips:** the Unit Guide and ability tooltips show every number.

Three scripts re-create the classes in a running Astra and re-export them:

- `tools/astra_classes.mjs`: the ten classes from Dragoon to Samurai.
- `tools/astra_time_mage.mjs`: the Time Mage.
- `tools/astra_class_pack.mjs`: the 90-class pack, with its icons.

Run them with `& "E:\Astra-Ability Creator\runtime\node.exe" tools/<script>`.

`tests/balance.gd` pits each class, in a mixed team, against a fixed team in computer-vs-computer battles and reports
win rate, damage dealt, which abilities it used and how long it survived:
`godot --headless --script res://tests/balance.gd -- [games per class] [class ids...]`.
Compare classes by **margin** (how much more of its health the class's team finished with than the other side, averaged
over the games), not by the win rate: a battle is one coin flip, so win rates at 8 games move by 25 points between
runs, while the margin moves smoothly with a class's strength. Every game is seeded, including the computer's own
mistakes, so two runs of the same classes give the same numbers and a change can actually be measured.

## Developer Tools

**Main menu → Developer Tools**, or **Menu → Developer Tools** in a battle. It has a slider for each main rule number:

| Slider | Default | What it changes |
|---|---|---|
| Speed multiplier | 1 | TG per tick = Speed × 2 × this. Higher means more turns for everyone. |
| Countdown base | 8 s | READY countdown = base + Patience × Patience multiplier |
| Patience multiplier | 2 s | extra countdown seconds per point of Patience |
| Damage / Healing multiplier | 0.5 / 1 | the final multiplier on all damage / healing |
| Height bonus, Side / Back attack | 0.1, 1.1 / 1.25 | the position bonuses on damage |
| Knock-out time | 12 s | how long a KO'd unit can be revived (0 = removed at once) |
| Ultimate per action / per turn | 20 / 5 | Ultimate meter gains |
| Move / Sight / Cast time multiplier | 1 | multipliers on every unit's Move and Sight and every cast time |

**Hover a slider** to see the formula it feeds, worked out for example units with the current values. The values are
saved (`user://tuning.cfg`) and used by every battle. In a battle vs the computer or on one device, changes apply at once.
They go through a recorded `tune` command, so replays stay exact. Online, the match uses the **host's** numbers.

**Calculation tooltips** are all over the game. Hover the unit card (Move, Sight, TG timing, countdown, Ultimate),
a turn-order chip, an ability button (its damage, healing and cast-time math), or a number in the Unit Guide. While
aiming, the preview line under the battlefield shows the damage breakdown for the target.

## Importing classes from Astra Ability Creator

Design the class in Astra, export the library as JSON (**Complete library JSON**), and put the file in the classes
folder. Use **Developer Tools → Open classes folder** (`user://classes/`), or `data/classes/` in the project. Classes
load at startup, or with **Reload classes**. Then they appear in Battle Setup, the Unit Guide and battles. Online, the
host sends the class to the other player. The rules, in `scripts/core/astra_import.gd`:

- Tag every ability of the class `class:<id>` (lowercase id).
- One **Passive** entry tagged `profile` holds the class stats as parameters with formula keys `hp`, `att`, `mag`,
  `attdef`, `magdef`, `speed`, `move`, `patience`, `sight`. Its name and color are the class name and color.
  Tag it `look:<job>` to choose a built-in character model (tinted with the class color), and `role:tank`
  (or `damage`, `support`, `special`, or a pair like `tank/support`) to say what the class is for.
  The profile needs hp, attdef, magdef, speed, move, patience and sight; power, aeva, meva and crit are optional
  (0, 5, 5, 5).
  The class icon is `assets/icons/<id>.svg`. Tag the profile `icon:<name>` to use another icon from that folder.
  Without one, the class gets a generic star in its color.
- Four abilities are tagged `slot:1` to `slot:4`; slot 4 is the ultimate. Their parameters are read at **rank 1**, and
  distances are in meters:

  | Key | Meaning | Default |
  |---|---|---|
  | `power` | the damage it does (healing for heals; a share of max HP for a revive) | 0 |
  | `min_range` | closest target point | 0 |
  | `cast_range` | farthest target point | 1.8 (melee); 0 when targeting is Self |
  | `radius` | area radius | 0 (one unit) |
  | `cast_time` | seconds until it takes effect | 0 (instant) |
  | `cooldown_turns` | turns to wait | Astra's `cooldown` seconds ÷ 10 |
  | `channel_turns` | turns a Channeled ability lasts | 2 |
  | `cone_angle` | the spread of a cone, in degrees | 60 |
  | `tg_change` | % change to each target's Turn Gauge | none |
  | `buff_<stat>` + `buff_turns` | a stat buff | none |

- **Damage type** Physical is resisted by AttDef and evaded with A-Eva; anything else by MagDef and M-Eva.
- **Ability type** (Astra's own field) becomes Active, Passive, Toggle, Channeled, Active + Passive or Aura, and
  **targeting** becomes the target shape (Unit, Point, Self, Circle, Line, Cone, Global, Vector).
- **Target team** Enemies targets enemies; anything else targets allies. The tag `revive` makes it revive a KO'd ally.
- **Effects:**
  - A Damage or Heal effect decides what the ability does. With neither, it's a support ability.
  - Slow, Stun, periodic Damage (Burn) and periodic Heal (Regen) put that status on each unit hit for the effect's
    duration in **turns** of that unit.
  - An `fx:<ability id>` tag borrows a built-in animation.
- Formulas work as in Astra: numbers, `+ - * /`, parentheses, postfix `%`, other parameter keys, `rank` and Astra's
  sample stats. They are evaluated by a port of Astra's safe evaluator.

## Game modes

- **Play vs Computer:** you are Blue, and the computer plays Red. The computer only targets what its units can see.
  Pick its **difficulty** in Battle Setup:
  - **Easy:** reacts in about 2.5 s, pauses 1.2 s between orders, and 45% of the time settles for one of its 5 best options.
  - **Medium** (default): about 1.3 s, 0.9 s, and 20% of the time one of its 3 best.
  - **Hard:** about 0.4 s, 0.6 s, and always its best option.
  These are the `LEVELS` table in `scripts/ai/ai_player.gd`.
- **Two Players (Same Device):** both players share the screen and the fog is off.
- **Computer vs Computer:** watch two computer players fight. Pick each side's difficulty in Battle Setup. The fog is
  off, and you can pause, move the camera, open Developer Tools to change rules mid-battle, and watch the replay afterwards.
- **Online:** one player presses **Host Game** and the other enters the host's address and presses **Join Game**. The host plays Blue.
  - On the same Wi-Fi/LAN, use the address shown on the host's screen.
  - Across the internet: the host's game tries to **open the port on the router automatically (UPnP)** and shows the
    public address to share. If the router doesn't allow it, forward **UDP port 7777** manually, or both players can use
    a VPN such as Tailscale or ZeroTier.
  - Both players need the **same version** of the game; a mismatched build is refused with a clear message.
  - Press **T** to **chat**. After the battle, **Rematch** restarts with the same map and teams once both players press it.
  - The host controls time and checks every order. The client's orders go to the host, which applies them and sends them back.

## Tests

Run from this folder (use `Godot_v4.7.2-stable_win64_console.exe` so output shows in the terminal):

```
godot --headless --script res://tests/smoke_test.gd              # rules, AI battles, tuning + tune replays, Astra import, Developer Tools, scenes
godot --headless --script res://tests/net_test.gd -- host        # online test: run these two at the same time;
godot --headless --script res://tests/net_test.gd -- client      # checks settings/tuning/class sync, chat, checksums, rematch
godot --headless --script res://tests/net_test.gd -- host_refuse # version check: run these two together;
godot --headless --script res://tests/net_test.gd -- old_client  # a client on another version must be refused
godot --script res://tests/screenshot.gd -- out.png [seconds] [ability_slot] [cast_after]   (add "guide" for the Unit Guide, "timemage", "tips"; or "-- out.png devtools")
godot --headless --script res://tests/profile_ai.gd              # how long the computer takes per decision
godot --script res://tests/frame_time.gd -- [seconds] [difficulty]   # real-window frame times (stutter check)
```

The computer decides on a background thread, working on a snapshot of the battle (`GameState.snapshot()`), so its
thinking never stalls the game. Its order is then checked against the live battle like any other.

## Credits

All third-party assets are **CC0** (public domain), bundled in `assets/`:

- **Characters:** KayKit Adventurers Character Pack by Kay Lousberg (www.kaylousberg.com)
- **Sound effects:** Kenney (www.kenney.nl): RPG Audio, Impact Sounds, Interface Sounds, Music Jingles
- **Music:** "Battle Theme A" by cynicmusic (cynicmusic.com, pixelsphere.org), via OpenGameArt.org

## Project layout

```
scenes/                 main_menu.tscn, battle.tscn (everything else is built in code)
scripts/core/           the rules, no graphics: game_state, unit, jobs, map_data, astra_import
data/classes/           classes exported from Astra Ability Creator
scripts/ai/             ai_player.gd: the computer opponent
scripts/battle/         battle.gd (time, input, orders), camera_rig, board_view, unit_view, fx (ability animations), hud
scripts/autoload/       GameConfig (chosen mode/map/teams), Net (online), Keybinds, Settings, Audio
assets/                 characters (KayKit), audio (Kenney sounds, battle music)
scripts/ui/             Battle Setup, Unit Guide, Options, How to Play, Developer Tools, shared theme (ui_theme.gd)
scripts/main_menu.gd    title screen
tests/                  headless tests and the screenshot tool
```

Every change to a battle is a **command** (`advance`, `move`, `ability`, `end_turn`, `tune`). `GameState.validate()` checks it
and `GameState.apply()` performs it. Local input, the AI, the clock and the online opponent all use the same path.
