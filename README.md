# Retro F1

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

- **Garage**: a pixel pit box with your car in team livery. Tap a part of it and the whole left sidebar becomes the picker for that hardpoint (tap `FIT` / `BUY`, or drag the part onto the car). Wing angle, brake bias and ballast position sliders appear with their part. Four bars summarise the build; `FULL STATS`, `MASS` and `AERO` show the detail.
- **Career** (`scenes/career/`, `scripts/career/`, `data/career/`): pick one of 11 teams, build a pixel manager, then run the team.
  - *Four pages on a bar along the bottom*: HQ, DRIVERS, SCOUTING, STANDINGS, plus the RACE button. HQ shows the next race, the staff roster (tap a tile to fire, `+ HIRE` opens the hiring sheet) and buttons for GARAGE, SPONSOR and SCHEDULE.
  - *Everything about the cars is in the garage*: the car button cycles your cars, WORKSHOP holds materials, factory departments (R&D unlocks parts), the FIA check, who drives which car and building / scrapping cars.
  - *Engineers*: hire and fire up to the FIA headcount (free agents, or rival staff for a buyout). Five specialisms. Every race week the office produces research points: engineer quality x last result (win 1.5, podium 1.3, points 1.1, none 0.9, double DNF 0.7) plus the data analysts' share. Unspent points above 400 are lost.
  - *Cars*: up to four cars, each with its own setup, materials and wind-tunnel data. Research points buy material tiers (monocoque, aero surfaces, power unit, brakes, suspension). Each car has an overall, and a fit rating for each driver (their taste in handling balance and wing level). Assign a car per race driver; the simulation and the grid use the car's overall adjusted for fit. The garage's car button cycles through them.
  - *Driver card*: tap FULL DRIVER CARD / CARD. Every stat (pace, starts, racecraft, consistency, overtaking, defending, tyre care, wet weather, ego), potential, favourite weather, home track, loved and bogey track types and the car they want. A driver signed without a finished scouting report keeps the gaps for good.
  - *Home tracks and conditions*: a home race is worth 0.25 s a lap, a favourite track type 0.15 s, a bogey type costs 0.15 s; wet skill decides pace and mistakes in the rain.
  - *FIA*: minimum weight, wing-angle limit, banned parts and engineer headcount, rewritten every winter. An illegal car is usually caught after the race: disqualification, a fine, more attention. Wind-tunnel runs per week shrink as you climb the championship.
  - *Buyouts and poaching*: SCOUTING > RIVAL DRIVERS lists every contracted driver with a release clause; pay it (and have the reputation) to sign them. Rivals do the same to your drivers and engineers by text: release for the buyout or counter with a 20% raise. An approach you ignore goes through at the next race.
  - *Scouting*: a report has three paid phases (`SCOUT_COSTS` in `Career.gd`): pace, then racecraft and consistency, then ego and potential overall. Prices follow paddock hype rather than true potential, so unscouted signings are a gamble.
  - *Injuries*: each crash raises a race driver's injury risk, and very low morale can sign them off. The best fit reserve covers the seat; with an empty bench you get a stand-in rookie.
  - *Phone*: texts from drivers, your race engineer, technical director, scout and rival bosses after every race. Some carry offers (one-race sponsor sticker, a bid for one of your drivers, a job at another team) with ACCEPT / DECLINE. CONTACTS has a profile for everyone.
  - *Dilemmas*: `events.json`. Each event lists the conditions it needs (`"if": ["board<35"]`, `"win"`, `"cash<2500"` ...); after a race the highest-priority event whose conditions are all true fires, and none repeats within five races. The popup says why it came up and each option lists exactly what it changes.
  - *Disqualification*: a car that breaks the FIA rules is shown as DSQ with the reason. Season one has no wing-angle limit.
  - *Race day*: DRIVE IT (you race the seven cars around you on the grid in the real driving game; your result is slotted into the full 22-car classification), PIT WALL (lap-by-lap strategy calls), or QUICK SIM.
  - Money is in thousands: `25000` is shown as `$25.0M`.
- **Difficulty**: ROOKIE, INTERMEDIATE, PRO, CHAMPION, LEGEND. Each sets CPU pace and aggression, steering and braking help, extra grip, damage, ABS, traction control, stability and the racing line (`Difficulty.gd`). Main menu, pause menu and race day.
- **Weather**: dry, light rain or heavy rain on track: less grip, spray, rain and lightning. Career races use the forecast; Free Drive follows the track's climate or your choice in the difficulty panel.
- **Scenery**: each circuit has its own surroundings from `TrackTheme.gd` / `TrackScenery.gd`: Falcon Ridge desert canyon, Port Azure harbour city, Tempo Park royal park, Silver Lake lakeside airfield, Nordhaven nordic forest.
- **Wind tunnel** (garage): the only 3D view in the game. A blocky model built from the setup turns under streamlines, with drag, downforce and top speed underneath. In career each run uses the FIA allowance and adds car knowledge (car rating).
- **Tracks**: five circuits in `data/tracks/` (Falcon Ridge, Tempo Park, Port Azure, Silver Lake, Nordhaven). Free Drive has a track picker; each career round names its track in `calendar.json`. Records and ghosts are kept per track.
- **Pit stops while driving**: the left side of the start straight is a pit lane with one red service box. Stop in it to repair damage, refuel and take new tires. The stop lasts longer with more damage and less fuel, and shorter with a better pit crew (Factory). Fuel only burns in races; thirsty engines cannot finish five laps without a stop.
- **Race HUD**: position and lap, live leaderboard, lap time and delta, FUEL / TIRES / DAMAGE bars, track map with every car and the weather, gear and speed.
- **Saves**: the saves are careers. CAREER on the main menu lists six: continue one or start a new one in an empty slot. Each has its own garage and records.
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

`TeamTest.tscn` checks engineers, research, multiple cars, fit, materials, wind tunnel, scrutineering, buyouts, poaching, difficulty, and laps every circuit on the driving aids alone. `FeatureShots.tscn` (windowed) screenshots those screens and each circuit's scenery. `PitTest.tscn` checks fuel burn and the pit stop. `CareerTest.tscn` plays two full seasons with random decisions. `FlowTest.tscn` (windowed) walks garage → time trial → results and writes screenshots; `TrackCheck.tscn` prints track facts.

Reference results on the starter car (lap 2, AI driver):

| Test | Result |
|---|---|
| Engines | Compact 4 1:35.0 / 237 km/h → Turbo 6 1:33.0 / 276 km/h, heavier and worse under braking |
| Wings | low drag 247 km/h, 1:36.0 · balanced 237, 1:34.9 · high downforce 220, 1:34.7 |
| Tires over 5 laps | hard 1:35.0 → 1:35.3 · medium 1:32.0 → 1:33.0 · soft 1:29.8 → 1:31.4 |
| Driver skill | smooth pedals 1:34.9 · 0/100 % pedals with assists 1:35.9 · 0/100 % without assists 1:37.5 and overheated tires |

## Not in this MVP

Multiplayer, accounts, liveries, a track editor and the rest of the spec's exclusion list. Export presets for Android / iOS are not included: add them in *Project → Export* once the platform templates are installed.
