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
| Use ability 1-4 | 1-4, then click a unit **or the ground**. Orange rings show the range, the red circle shows the area hit. |
| End the unit's turn | Enter |
| Cancel | Esc |
| Pause (not online) | P |
| Chat (online) | T, type, Enter to send (Esc closes) |
| Combat log | L or the Log button shows / hides it. Drag its title bar to move it, its corner to resize it; – collapses it. It keeps the whole battle's messages (scroll up for older ones) and remembers its place. |
| Unit Guide (stats, abilities, damage) | U, or the **Units** button. Also on the main menu. Pauses the game when not online. |
| Camera | WASD / arrows pan · R / F raise / lower · Q / E or right-drag rotate and tilt · wheel zoom · middle-drag pan · C center on the selected unit. The camera never moves by itself: press C, or click a unit's chip in the turn order (a second click on your selected unit's chip centers on it). |
| Menu (in battle) | **Menu** button: Resume, Options, Unit Guide, How to Play, Quit to Main Menu (pauses when not online) |

These are the default keys. Every keyboard control can be rebound in **Options** (main menu, or Menu → Options in battle):
click an action, then press a key. If another action already uses that key, the two swap. Bindings are saved between sessions.

**Options → Game** also has master / music / sound-effect volume, camera speed, UI scale, fullscreen, and
**colorblind team colors** (blue / orange). Settings are saved (`user://settings.cfg`). New players: **How to Play**
(main menu or in-game menu) walks through the rules page by page.

## After the battle

The victory screen shows each unit's **damage dealt and taken, healing and KOs**, and the **MVP**. **Rematch** replays the
same map and teams; **Watch Replay** plays the whole battle back (every order is recorded, and the rules are
deterministic, so the replay is exact), with ×1 / ×2 / ×4 speed.

## How it plays

- **Time keeps running.** Every unit's **Turn Gauge (TG)** fills at a rate set by its **Wits**: a Wits-10 unit gets a
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
  room, and ticks mark 1, 3, 5, 10, 20 and 30 s. A chip grows as its turn gets closer and is full size once READY.
  The seconds until ready show on the chip for 3 s after the unit's turn ends, in the last 3 s before it's ready,
  and while the mouse is over the chip.
- **Stats cards:** click a unit that isn't taking orders (an enemy, or an ally that isn't READY), or its chip, to see
  its stats, gauges, statuses and abilities. Allies show on the left, enemies on the right. Click it again, click the
  ground or press × to close. Hover the numbers for their calculations.
- On its turn a unit can **walk once** (up to its Move in meters, around water, cliffs and enemies) and **use one ability**,
  in either order. Skipping one keeps some TG, so the next turn comes sooner.
- **Bars over every unit's head:** HP (green, red when low), TG (blue, gold when READY), Ultimate (orange, pale gold when full).
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
- **Status effects** (tags over the unit's head): **Burn** (from Fire, −3% max HP per second), **Regen** (from Chakra and
  Sanctuary, +3% per second), **Slow** (from Blizzard, Turn Gauge fills at half speed), **Stun** (from Shield Bash, can't
  act and the Turn Gauge is frozen).
- **Knock-outs:** a unit at 0 HP is **knocked out** for 12 s (it lies on the field with a `KO` countdown). The White
  Mage's **Raise** (replaces Staff Strike) revives it with 30% HP; otherwise it's gone. KO'd units don't count as alive.

Damage = (power stat × ability power × 2 × height bonus − AttDef (physical) or MagDef (magic)) × 0.5, minimum 1.
There is no randomness. The final × 0.5 is `DAMAGE_MULTIPLIER` in `game_state.gd`, the quickest dial for overall damage.

## Battle Setup: maps and teams

Every game starts with **Battle Setup**: pick the **map**, each side's **4 jobs** (any of the 6, repeats allowed; **Random**
and **Default** buttons), and the computer's **difficulty**. A host picks for both sides, and the joining player gets the
same settings.

| Map | What it's like |
|---|---|
| **Highlands** | Rolling hills with a high ridge on each flank. Take the high ground. |
| **River Crossing** | A river splits the field; two narrow bridges are the only way across. |
| **Fortress** | A raised central plateau reachable only by ramps; stone pillars block line of sight. |
| **Open Plains** | Flat and open with a few low hills. |

Maps are 24 × 24 m and point-symmetric (fair for both sides). They're defined as height rows in `scripts/core/map_data.gd`
(`MAPS`); adding a map is adding an entry there.

## Jobs

The default team is Knight, Archer, Black Mage and White Mage (`Jobs.DEFAULT_ROSTER`); Squire and Monk are also
available in Battle Setup. Move and Sight are in meters.

| Job | HP | AttPwr | MagPwr | AttDef | MagDef | Wits | Move | Patience | Sight |
|---|---|---|---|---|---|---|---|---|---|
| Squire | 80 | 14 | 6 | 8 | 6 | 9 | 7 | 6 | 9 |
| Knight | 100 | 16 | 5 | 12 | 6 | 7 | 6 | 7 | 8 |
| Archer | 70 | 15 | 6 | 6 | 7 | 10 | 7 | 6 | 13 |
| Monk | 90 | 17 | 6 | 8 | 5 | 10 | 8 | 5 | 9 |
| Black Mage | 60 | 5 | 18 | 4 | 12 | 8 | 6 | 8 | 10 |
| White Mage | 65 | 5 | 15 | 5 | 13 | 8 | 6 | 8 | 10 |

| Job | 1 | 2 | 3 | 4 (Ultimate) |
|---|---|---|---|---|
| Squire | Attack | Throw Stone | Focus (AttPwr up) | Brave Slash |
| Knight | Attack | Shield Bash (TG −30%, Stun) | Guard (defense up) | Holy Blade (area, 1 s) |
| Archer | Bow Shot | Aimed Shot (1 s) | Pin Shot (TG −40%) | Arrow Rain (area, 2 s) |
| Monk | Punch | Wave Fist | Chakra (area heal + Regen) | Earth Slash (area around self, 1 s) |
| Black Mage | Staff Strike | Fire (Burn, 1 s) | Blizzard (area, Slow, 2 s) | Meteor (large area, 4 s) |
| White Mage | Raise (revive, 2 s) | Cure (1 s) | Haste (TG +50%, 1.5 s) | Sanctuary (large area heal + Regen, 3 s) |

Abilities without a time are instant. The in-game **Unit Guide** lists every number, including each ability's
damage against any job you pick.

Each ability has its own animation (`scripts/battle/fx.gd`). Melee abilities lunge, arrows and fireballs fly in arcs,
Arrow Rain and Blizzard fall on the area, Meteor drops from the sky, Holy Blade brings down a pillar of light, and heals sparkle.

All numbers are in `scripts/core/jobs.gd` (jobs and abilities) and at the top of `scripts/core/game_state.gd`
(time, countdown, damage, height and movement rules). The main rule numbers can also be changed in **Developer Tools**.

### Imported class: Time Mage (from Astra Ability Creator)

| Job | HP | AttPwr | MagPwr | AttDef | MagDef | Wits | Move | Patience | Sight |
|---|---|---|---|---|---|---|---|---|---|
| Time Mage | 65 | 5 | 16 | 5 | 11 | 12 | 6 | 7 | 10 |

1 **Chrono Bolt** (instant magic bolt, 1-7 m, target's TG −10%) · 2 **Slowga** (Slow everyone within 2.5 m, 1.5 s) ·
3 **Quicken** (ally TG +40%, 1 s) · 4 **Time Stop** (ultimate: damage and a 2 s Stun within 3 m, 2.5 s).

The Time Mage was designed in **Astra Ability Creator** (`E:\Astra-Ability Creator`) and lives there as five
library entries tagged `class:time_mage`. The game reads Astra's JSON export, `data/classes/time_mage.astra.json`.
`tools/astra_time_mage.mjs` re-creates the class in a running Astra and re-exports it:
`& "E:\Astra-Ability Creator\runtime\node.exe" tools/astra_time_mage.mjs`.

## Developer Tools

**Main menu → Developer Tools**, or **Menu → Developer Tools** in a battle. It has a slider for each main rule number:

| Slider | Default | What it changes |
|---|---|---|
| Wits multiplier | 1 | TG per tick = Wits × 2 × this. Higher means more turns for everyone. |
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
  `attdef`, `magdef`, `wits`, `move`, `patience`, `sight`. Its name and color are the class name and color.
  Tag it `look:<job>` to choose a built-in character model (tinted with the class color).
  The class icon is `assets/icons/<id>.svg`. Tag the profile `icon:<name>` to use another icon from that folder.
  Without one, the class gets a generic star in its color.
- Four abilities are tagged `slot:1` to `slot:4`; slot 4 is the ultimate. Their parameters are read at **rank 1**, and
  distances are in meters:

  | Key | Meaning | Default |
  |---|---|---|
  | `power` | multiplier on AttPwr or MagPwr | 1 |
  | `min_range` | closest target point | 0 |
  | `cast_range` | farthest target point | 1.8 (melee); 0 when targeting is Self |
  | `radius` | area radius | 0 (one unit) |
  | `cast_time` | seconds until it takes effect | 0 (instant) |
  | `cooldown_turns` | turns to wait | Astra's `cooldown` seconds ÷ 10 |
  | `tg_change` | % change to each target's Turn Gauge | none |
  | `buff_<stat>` + `buff_turns` | a stat buff | none |

- **Damage type** Physical uses AttPwr against AttDef; anything else uses MagPwr against MagDef.
- **Target team** Enemies targets enemies; anything else targets allies. The tag `revive` makes it revive a KO'd ally.
- **Effects:**
  - A Damage or Heal effect decides what the ability does. With neither, it's a support ability.
  - Slow, Stun, periodic Damage (Burn) and periodic Heal (Regen) put that status on each unit hit for the effect's
    duration in seconds.
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
