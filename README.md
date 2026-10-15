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

- **Garage**: a pixel pit box with your car in team livery. Everything is told as an overall rating: the sidebar shows a big `CAR OVR` and five ratings (top speed, acceleration, cornering, braking, balance) with the raw stat in small grey text underneath. Tap a part of the car and the whole sidebar becomes the picker for that hardpoint: each part card shows what fitting it would do to the overall (`OVR 78 -> 83`), and you `FIT` it or `RESEARCH` it with research points (or drag it onto the car). Wing angle, brake bias and ballast sliders appear with their part. `CAR CARD` shows all ten ratings.
- **Research points are the only currency for the car.** Money never buys parts. RP research new parts (unlocked for good, free to fit on any car) and buy **upgrade levels**: engine, wings, brakes, suspension, chassis and gearbox each go from level 0 to 5 (20 / 35 / 55 / 80 / 110 RP). Levels belong to the team, apply to every car, change the physics (more power, downforce, braking, grip, less weight, quicker shifts) and add to the overall.
- **Career** (`scenes/career/`, `scripts/career/`, `data/career/`): pick one of 11 teams, build a pixel manager, then run the team.
  - *Four pages on a bar along the bottom*: HQ, DRIVERS, SCOUTING, STANDINGS, plus the RACE button. HQ shows the next race, the staff roster (tap a tile to fire, `+ HIRE` opens the hiring sheet) and buttons for GARAGE, SPONSOR and SCHEDULE.
  - *Everything about the cars is in the garage*: the car button opens your car list (switch, build a new chassis with money, scrap). Who drives which car is on the driver card; FIA problems show as a red warning line.
  - *Engineers*: hire and fire up to the FIA headcount (free agents, or rival staff for a buyout). Five specialisms. Every race week the office produces research points: engineer quality x last result (win 1.5, podium 1.3, points 1.1, none 0.9, double DNF 0.7) plus the data analysts' share. Unspent points above 600 are lost.
  - *Cars*: up to four cars, each with its own setup and wind-tunnel data (shown on the car card as extra overall). Each car has an overall, and a fit rating for each driver (their taste in handling balance and wing level). Assign a car per race driver; the simulation and the grid use the car's overall adjusted for fit. The garage's car button cycles through them.
  - *Driver card*: tap FULL DRIVER CARD / CARD. Every stat (pace, starts, racecraft, consistency, overtaking, defending, tyre care, wet weather, ego), potential, favourite weather, home track, loved and bogey track types and the car they want. A driver signed without a finished scouting report keeps the gaps for good.
  - *Home tracks and conditions*: a home race is worth 0.25 s a lap, a favourite track type 0.15 s, a bogey type costs 0.15 s; wet skill decides pace and mistakes in the rain.
  - *FIA*: minimum weight, wing-angle limit, banned parts and engineer headcount, rewritten every winter. An illegal car is usually caught after the race: disqualification, a fine, more attention. Wind-tunnel runs per week shrink as you climb the championship.
  - *Buyouts and poaching*: SCOUTING > RIVAL DRIVERS lists every contracted driver with a release clause; pay it (and have the reputation) to sign them. Rivals do the same to your drivers and engineers by text: release for the buyout or counter with a 20% raise. An approach you ignore goes through at the next race.
  - *Scouting*: a report has three paid phases (`SCOUT_COSTS` in `Career.gd`): pace, then racecraft and consistency, then ego and potential overall. Prices follow paddock hype rather than true potential, so unscouted signings are a gamble.
  - *Injuries*: each crash raises a race driver's injury risk, and very low morale can sign them off. The best fit reserve covers the seat; with an empty bench you get a stand-in rookie.
  - *Phone*: texts from drivers, your race engineer, technical director, scout and rival bosses after every race. Some carry offers (one-race sponsor sticker, a bid for one of your drivers, a job at another team) with ACCEPT / DECLINE. CONTACTS has a profile for everyone.
  - *Dilemmas*: `events.json`. Each event lists the conditions it needs (`"if": ["board<35"]`, `"win"`, `"cash<2500"` ...); after a race the highest-priority event whose conditions are all true fires, and none repeats within five races. The popup says why it came up and each option lists exactly what it changes.
  - *Disqualification*: a car that breaks the FIA rules is shown as DSQ with the reason. Season one has no wing-angle limit.
  - *Race day*: the track, the weather, two big DRIVE buttons (you race the seven cars around you on the grid; your result is slotted into the full 22-car classification), SIMULATE, and the only GARAGE button in the career.
  - *Cards*: every person (drivers, reserves, prospects, rival drivers, engineers, staff, you) is the same card; tap it for the full-screen card. Signing a driver puts them straight on your bench (up to three); race them from their card.
  - *Driver development*: drivers improve a little after every race towards their potential - fastest when young, with points finishes, in a race seat and next to a star team-mate; veterans decline. Per-driver training (REST / NORMAL / INTENSE / EXTREME) trades speed of development for fitness and morale (below 40 fitness they can break down), and a simulator programme speeds learning for cash.
  - *You*: the manager card shows your contract (salary, years, expiry), rating, history, job security and the teams that would hire you (they pay your release fee). When a contract runs out the owners renew it or let you go.
  - *Seasons*: after the last round a season review shows the result and starts the next season.
  - *Calendar*: the season runs day by day from 1 March. Race weekends are Friday practice, Saturday qualifying and the Sunday race, with a test day the Friday before. The bottom-right button shows today's job (PRACTICE, QUALIFYING, RACE); once it is done it says NEXT, which opens the sim picker: next day, next week, next race or next month. Every sim stops at the next race weekend - you can never miss a race - and a red slide shows the new date. Paddock news appears most days.
  - *Days*: race weekends are free practice (Friday), qualifying (Saturday) and the race (Sunday). Every other day is a practice day, except three recovery days a fortnight (the Monday after a race, then two mid-week). On a recovery day you pick each driver's technique: PHYSIO (fitness +15), ICE BATH (fitness +10, morale +3), MENTAL COACH (morale +8), SIMULATOR (skill like a race) or MEDIA DAY (reputation +1, morale -3). Skipped recovery days default to physio.
  - *Practice and test days*: pick a programme (setup work, race simulation, qualifying sims, young driver day) and up to two drivers - reserves too - and run the session, or drive it yourself on that weekend's circuit. Each programme gives a bonus for that weekend (car rating, tyre care, qualifying pace) and research.
  - *Form-based ratings*: like the in-season rating updates in the official F1 games, every driver's rating moves with their recent form: finishing position against where their car and rating said they should finish, beating the team-mate, crashing out. Ratings drift with the last five results; young drivers who keep over-performing have their potential raised, and the reverse. Reserves earn form in practice sessions. The driver card shows the last results.
  - *Driver card*: BACK in the top left; RACE INSTEAD OF / BENCH FOR, RELEASE and ADJUST (full-screen training: rest, normal, intense, extreme and the simulator programme).
  - Money is in thousands: `25000` is shown as `$25.0M`.
- **Difficulty**: ROOKIE, INTERMEDIATE, PRO, CHAMPION, LEGEND. Each sets CPU pace and aggression, steering and braking help, extra grip, damage, ABS, traction control, stability and the racing line (`Difficulty.gd`). Main menu, pause menu and race day.
- **Weather**: dry, light rain or heavy rain on track: less grip, spray, rain and lightning. Career races use the forecast; Free Drive follows the track's climate or your choice in the difficulty panel.
- **Scenery**: each circuit has its own surroundings from `TrackTheme.gd` / `TrackScenery.gd`: Falcon Ridge desert canyon, Port Azure harbour city, Tempo Park royal park, Silver Lake lakeside airfield, Nordhaven nordic forest.
- **Wind tunnel** (garage): the only 3D view in the game. A blocky model built from the setup turns under straight streamlines; the lines over the car's weakest areas (front wing, rear wing, wheels, floor, sidepods) are tinted orange to red, worst named underneath.
- **Car card** (garage, CAR CARD): an overall plus ten ratings - power, acceleration, top speed, downforce, drag efficiency, cornering, braking, balance, weight, tyre life. Every part and setup change moves them, and in the career the overall drives the car's rating. In career each run uses the FIA allowance and adds car knowledge (car rating).
- **Tracks**: ten circuits in `data/tracks/`. Monza, Silverstone, Spa-Francorchamps, Interlagos and the Red Bull Ring use the real layouts (centrelines from the MIT-licensed [f1-circuits](https://github.com/bacinger/f1-circuits) dataset by Tomislav Bacinger); Falcon Ridge, Tempo Park, Port Azure, Silver Lake and Nordhaven are fictional. Several circuits are fenced off with a perimeter fence and gates; Port Azure has concrete street walls. The real circuits carry their landmarks in simplified form: Monza's old banked oval in the park, Silverstone's long curved pit building, the Eau Rouge stream crossing under Spa, the lake at Interlagos, the Styrian hills at the Red Bull Ring. Floodlights ring every circuit, a start gantry counts down the lights, night rounds are floodlit, and the crowd gets louder as you pass the grandstands.
- **Camera**: CAM switches between the classic overhead view and the driver's view (close, turned with the car, looking up the road, with speed streaks and an F1 steering wheel showing revs, gear and speed).
- **Car options**: eleven tyre compounds from vintage and endurance to hyper soft and qualifier, plus intermediates and full wets that are faster in the rain; ride height, tyre pressure and anti-roll balance; seven body sets (70s classic to ground effect) that trade downforce for drag. Starter parts and a few cheap alternatives are open from the start; research points unlock the rest. Free Drive has a track picker; each career round names its track in `calendar.json`. Records and ghosts are kept per track.
- **Pit stops while driving**: steer into the pit lane after the start line and the stop plays as a cutscene: the car drives the lane at the 80 km/h limit, the crew runs out (wheel guns, jacks, a new nose if it was damaged, lollipop), you pick the next tyre, and the car is released at the exit. Stop time depends on the pit crew level (HQ staff tile, paid with money) and how much work there is; crews occasionally fumble. Rival cars stop in the same lane.
- **Race HUD**: position and lap, live leaderboard, lap time and delta, FUEL / TIRES / DAMAGE bars, track map with every car and the weather, gear and speed.
- **Saves**: the saves are careers. CAREER on the main menu lists six: continue one or start a new one in an empty slot. Each has its own garage and records.
- **Tutorial**: guided tips the first time you open the main menu, Team HQ, the garage, race day and your first race: the screen dims, the control is spotlighted, a finger points at it and a bubble says what it does. TUTORIAL on the main menu replays them (`CoachMarks.gd`).
- **Real-world ratings**: the starting drivers and team car ratings follow the real 2026 season up to the Singapore Grand Prix (11 October 2026): the championship order, the Singapore result (seeded as each driver's first form entry) and young drivers' progress (Antonelli, Hadjar, Lindblad, Bearman, Bortoleto get higher potential).
- **Look**: `UIKit.gd` (palette, bevelled buttons, title bars, backdrop), `PixelFont.gd` (5x7 dot-matrix titles), `Frame.gd` (captioned group boxes), `PixelArt.gd` (16x16 portraits, helmets, flags, cars, logos).
- **Free Drive**: Test Drive, Time Trial (PB ghost, live delta, target times), 5 Lap Race (7 AI, you start P4).
- **Damage**: impacts fill the damage bar on the HUD. At 100 % the car explodes, the session ends and a rebuild fee is charged (`explosion_penalty` in `economy.json`, smaller in Test Drive).
- **Stability Assist** (Settings, on by default) damps slides and trims power while the rear is stepping out.

## F1 rules in the game

Researched from the real sporting regulations and simplified where a mobile game needs it:

| Real F1 | In Retro F1 |
|---|---|
| Grand Prix and Sprint weekends | The calendar mixes Grands Prix (5 laps driven / 20 simulated) and Sprints (3 / 8) |
| Points 25-18-15-12-10-8-6-4-2-1, sprint 8-1 | Same, and the season finale pays double (as F1 did once, in 2014) |
| Qualifying sets the grid | QUALIFY on race day: one flying lap, judged against your car's ideal lap, moves your grid slot; three tries for a valid lap |
| Two different dry compounds in a dry race | A dry Grand Prix needs one stop onto a different dry compound, or +25 s |
| Pit lane speed limit 80 km/h | The pit-lane autopilot drives at 80 km/h |
| Track limits: warnings, then 5 s penalties | Three warnings, then +5 s for each time off the track |
| DRS within one second on a straight | DRS button lights up on long straights within a second of the car ahead from lap 2; it closes when you brake |
| Intermediate and full wet tyres | Inters and wets are faster in the rain, slower in the dry |
| Street and night races | Street circuits and floodlit night rounds on the calendar |
| No refuelling since 2010 | Kept: cars still refuel at stops, so thirsty engines remain a strategy choice |

Skill matters at every step: the qualifying lap, using DRS at the right moment, staying inside track limits, managing tyres and damage (kerbs and run-offs wear the car faster), and choosing when to pit and on which tyre.

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

`TeamTest.tscn` checks engineers, research, multiple cars, fit, upgrade levels, rest days, wind tunnel, scrutineering, buyouts, poaching, difficulty, and laps every circuit on the driving aids alone. `FeatureShots.tscn` (windowed) screenshots those screens and each circuit's scenery. `PitTest.tscn` checks fuel burn and the pit stop. `CareerTest.tscn` plays two full seasons with random decisions. `FlowTest.tscn` (windowed) walks garage → time trial → results and writes screenshots; `TrackCheck.tscn` prints track facts.

Reference results on the starter car (lap 2, AI driver):

| Test | Result |
|---|---|
| Engines | Compact 4 1:35.0 / 237 km/h → Turbo 6 1:33.0 / 276 km/h, heavier and worse under braking |
| Wings | low drag 247 km/h, 1:36.0 · balanced 237, 1:34.9 · high downforce 220, 1:34.7 |
| Tires over 5 laps | hard 1:35.0 → 1:35.3 · medium 1:32.0 → 1:33.0 · soft 1:29.8 → 1:31.4 |
| Driver skill | smooth pedals 1:34.9 · 0/100 % pedals with assists 1:35.9 · 0/100 % without assists 1:37.5 and overheated tires |

## Not in this MVP

Multiplayer, accounts, liveries, a track editor and the rest of the spec's exclusion list. Export presets for Android / iOS are not included: add them in *Project → Export* once the platform templates are installed.
