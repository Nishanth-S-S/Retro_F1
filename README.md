# Apex Assembly

A mobile-first 2D top-down motorsport engineering and racing prototype for **Godot 4** (GDScript, 2D, landscape).

Build a car on a blueprint table, test it on Falcon Ridge Circuit, feel what your design did, go back and change it.

## Run it

1. Install Godot 4.3 or newer (built and verified on 4.7.2).
2. Open the project folder in Godot (`project.godot`) and press **F5**. Nothing else to install: all art and audio are generated in code.

The save file lives at `user://apex_assembly_save.json`.

## Controls

| | Touch (primary) | Keyboard (debug) |
|---|---|---|
| Steer | left thumb, horizontal strip | `A` / `D` or arrows |
| Throttle / brake | right thumb, one vertical pedal (up = throttle, down = brake) | `W` / `S` or arrows |
| Shift (manual) | `SHIFT +` / `SHIFT −` buttons | `E` / `Q` |
| Reset to track (+3 s) | `RESET` | `Space` |
| Pause | `II` | `Esc` |
| Physics debug overlay | – | `F3` |

On desktop the mouse emulates one finger, so the touch widgets can be tried there too.
Holding the brake at a standstill selects reverse (automatic gearbox).

## The loop

`Main Menu → Garage → build / tune → TEST CAR → drive → Garage` (the test drive has a one-tap `◀ GARAGE` button), or
`Time Trial / 5 Lap Race → Results + telemetry → money + research → Garage`.

- **Garage**: a pixel pit box with your car in team livery. Tap a part of it and a picker for that hardpoint opens on the right (tap `FIT` / `BUY`, or drag the part onto the car). Wing angle, brake bias and ballast position sliders appear with their part. Four bars summarise the build; `FULL STATS`, `MASS` and `AERO` show the detail.
- **Career** (`scenes/career/`, `scripts/career/`, `data/career/`): pick one of 11 teams, build a pixel manager, then run the team.
  - *HQ tabs*: HQ, Drivers (two race seats plus up to two reserves), Scouting, Sponsors, Factory (cost cap, R&D unlocks garage parts), Standings.
  - *Scouting*: a report has three paid phases (`SCOUT_COSTS` in `Career.gd`): pace, then racecraft and consistency, then ego and potential overall. Prices follow paddock hype rather than true potential, so unscouted signings are a gamble.
  - *Injuries*: each crash raises a race driver's injury risk, and very low morale can sign them off. The best fit reserve covers the seat; with an empty bench you get a stand-in rookie.
  - *Phone*: texts from drivers, your race engineer, technical director, scout and rival bosses after every race. Some carry offers (one-race sponsor sticker, a bid for one of your drivers, a job at another team) with ACCEPT / DECLINE. CONTACTS has a profile for everyone.
  - *Dilemmas*: one event after most races from `events.json`.
  - *Race day*: DRIVE IT (you race the seven cars around you on the grid in the real driving game; your result is slotted into the full 22-car classification), PIT WALL (lap-by-lap strategy calls), or QUICK SIM.
  - Money is in thousands: `25000` is shown as `$25.0M`.
- **Tracks**: five circuits in `data/tracks/` (Falcon Ridge, Tempo Park, Port Azure, Silver Lake, Nordhaven). Free Drive has a track picker; each career round names its track in `calendar.json`. Records and ghosts are kept per track.
- **Pit stops while driving**: the left side of the start straight is a pit lane with one red service box. Stop in it to repair damage, refuel and take new tires. The stop lasts longer with more damage and less fuel, and shorter with a better pit crew (Factory). Fuel only burns in races; thirsty engines cannot finish five laps without a stop.
- **Race HUD**: position and lap, live leaderboard, lap time and delta, FUEL / TIRES / DAMAGE bars, gear and speed.
- **Saves**: six slots (`CHANGE SAVE` on the main menu). Each slot has its own career, garage and records.
- **Tutorial**: six pages, opens on first launch of a save and from the main menu.
- **Look**: `UIKit.gd` (palette, bevelled buttons, title bars, backdrop), `PixelFont.gd` (5x7 dot-matrix titles), `Frame.gd` (captioned group boxes), `PixelArt.gd` (16x16 portraits, helmets, flags, cars, logos).
- **Free Drive**: Test Drive, Time Trial (PB ghost, live delta, target times), 5 Lap Race (7 AI, you start P4).
- **Damage**: impacts fill the damage bar on the HUD. At 100 % the car explodes, the session ends and a rebuild fee is charged (`explosion_penalty` in `economy.json`, smaller in Test Drive).
- **Stability Assist** (Settings, on by default) damps slides and trims power while the rear is stepping out.

## How it is built

```
data/            parts/*.json, tracks/falcon_ridge.json, progression/*.json, physics/default_physics.tres
scenes/          MainMenu, Garage, Track, Race, Results  +  components/  +  tests/
scripts/core     GameManager, SaveManager, SceneManager, EventBus, AudioManager (autoloads)
scripts/vehicle  VehicleController (RigidBody2D) → VehiclePhysics → Engine / Transmission / Tire / Aero / Brake models,
                 CarSetup (the build) → CarStats (derived numbers, shared by garage and physics), CarVisual
scripts/track    TrackData (geometry, surfaces, corners, checkpoints), Track (mesh + barriers)
scripts/race     RaceManager, LapTimer, CheckpointManager, RacePositionManager, RaceResults, ghost, delta, camera
scripts/ai       RacingLine (line + speed profile), AIDriver, AIOvertake
scripts/telemetry, scripts/garage, scripts/ui
```

Things worth knowing:

- **Physics** is a custom single-track (bicycle) model in `VehiclePhysics.gd`: per-axle load (static + longitudinal transfer + downforce), slip angles, a saturating lateral curve and one traction circle per axle. Understeer, oversteer, lockups, wheelspin and trail braking are not scripted; they come out of that force allocation. Player and AI cars are the same class and receive the same three analog inputs.
- **Everything tunable** is in `data/physics/default_physics.tres` (`VehiclePhysicsConfig`): cornering stiffness, steering lock, load sensitivity, assist levels, surface grip and so on.
- **Parts are data**. Add an entry to a file in `data/parts/` and it appears in the garage. `CarStats` reads the numbers; no per-part code.
- **Tracks are data**. A track is a list of control points; curbs, gravel traps, barriers, corners, the racing line and AI speed profile are derived from it. Nothing assumes a road course or an open-wheel car.
- **Economy** numbers are in `data/progression/economy.json` and `challenges.json`; AI drivers and their cars in `ai_drivers.json`.

## Tests and tuning tools

Headless scenarios drive the real physics with an AI at the wheel, so setup changes can be compared with lap times.
After adding a script with a new `class_name`, run `godot --headless --import` once.

```bash
godot --headless res://scenes/tests/PhysicsTests.tscn -- engines 2
```

Scenarios: `baseline`, `engines`, `wings`, `balance`, `tires`, `skill`, `field`; the number is laps. Add `trace` for an incident log.

```bash
godot --headless res://scenes/tests/RaceSim.tscn
```

```bash
godot --headless res://scenes/tests/SaveTest.tscn
```

`PitTest.tscn` checks fuel burn and the pit stop. `CareerTest.tscn` plays two full seasons with random decisions. `FlowTest.tscn` (windowed) walks garage → time trial → results and writes screenshots; `TrackCheck.tscn` prints track facts.

Reference results on the starter car (lap 2, AI driver):

| Test | Result |
|---|---|
| Engines | Compact 4 1:35.0 / 237 km/h → Turbo 6 1:33.0 / 276 km/h, heavier and worse under braking |
| Wings | low drag 247 km/h, 1:36.0 · balanced 237, 1:34.9 · high downforce 220, 1:34.7 |
| Tires over 5 laps | hard 1:35.0 → 1:35.3 · medium 1:32.0 → 1:33.0 · soft 1:29.8 → 1:31.4 |
| Driver skill | smooth pedals 1:34.9 · 0/100 % pedals with assists 1:35.9 · 0/100 % without assists 1:37.5 and overheated tires |

## Not in this MVP

Multiplayer, accounts, damage, pit stops, weather, fuel strategy, liveries, a track editor and the rest of the spec's exclusion list. Export presets for Android / iOS are not included: add them in *Project → Export* once the platform templates are installed.
