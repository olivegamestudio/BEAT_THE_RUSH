# Beat the Rush — Design & Reference

A landscape iOS SwiftUI signal-box puzzle. Trains self-navigate; the player controls only the
signals/points. Clear each station by carrying its goal number of people before a platform overflows.

> **Living document.** Kept in sync with the code by Claude as changes land. If something here
> disagrees with the code, the code wins — and this file should be corrected.

- Bundle id: `com.ogs.signalbox` · Display name: **Beat the Rush**
- Remote: `github.com/olivegamestudio/TrainStationManager`, work lands on `main`.

## Architecture

Each station is a pair: a `…Station` model (`ObservableObject`, all game logic + geometry constants)
and a `…View` (SwiftUI `Canvas` that draws it). `StationDef.swift` lists every station (`allStations`,
ids 1–20) and a `StationKind` picks which view/model to use.

```
enum StationKind { case ladder, saltash, dawlish, worcester, birmingham }
```

- **Bespoke stations:** Saltash (1), Dawlish Warren (2), Worcester Foregate Street (3),
  Newark (4), Birmingham New Street (19). Each has its own Station/View pair.
- **Planned bespoke:** Reedham (5, swing bridge on a timer), an inland reversing terminus (6, bay
  platforms — not seaside).
- **Generic “ladder” stations:** all the rest — one shared `StationView`/`Station` with platforms
  fed by a points ladder; difficulty scales via `StationDef` (spawn rate, speed, goal, express %).

### Design space & camera
- Design units: width varies per station, height `Track.H = 452`. `Track.carUnit = 50`,
  `carHeight = 34`.
- Views map design→screen with `project(p, sc, size)` where `sc = size.width / worldW`; vertical is
  centred on the `Track.H` band, and content may extend into the top/bottom margins (usable design-y
  is roughly `[-119, 571]` on the widest phones).
- Pannable stations hold an `originX` (`@State`) with `clampOrigin`; a `DragGesture(minimumDistance:14)`
  scrolls. The **start** camera is the initial `originX`.

### Shared systems
- **Kinematics:** ease `v` toward `target = min(speedCap, sqrt(2*decel*headroom))`; `ceiling` is the
  min of all constraints (berth, signal holds, train-ahead tail − gap). Overrun ceiling so long trains
  don’t vanish while their tail is still on-screen.
- **Signals** (`Carriage.swift`): `drawSignal(at:red:scale:)` = 2-aspect red/green; `drawBlockSignal(at:aspect:scale:)`
  = 3-aspect (0 green, 1 amber, 2 red). Both render the head ~22px *above* the anchor point — so to
  lift a signal “off the track”, move its anchor up ~24, and move its tappable `SignalHalo` circle to
  match the lamp.
- **Boarding:** train dwells at `berthDist`, tops up `carried` from the platform’s waiting count while
  standing; sparkles on each boarded person (each flies to the people counter). `drawCarriage(..., fill:seed:)`
  fills the car’s three windows with passenger silhouettes: `fill = load / (length*3)` (generic uses
  `loaded`), `seed = t.id.hashValue &+ c` — each window has a stable pseudo-random threshold so seats
  populate scattered about, more as the train fills. Dawlish pre-loads ~75% of through expresses so
  fast trains already carry people.
- **Outcome:** win at `carried >= goal` (stars from peak platform fill); lose if a platform stays over
  `platformCap` past `overflowGrace`.
- **Level briefing + tasks:** every station view holds a `started` flag; while `!started` it shows
  `LevelBriefing` (name + task checklist + Start / red **X** = back to list) over the frozen scene and
  does **not** call `station.tick`. `levelTasks(def)` returns three tickable `LevelTask`s (a first-move
  task, a halfway target, the finish), each `done` once `carried >= need`. **Stars = completed tasks**
  (`levelStars`), rewarded on win *and* fail — the `OutcomeOverlay` shows the tasks ticked (why you
  won/lost) and the star row on both. New station views must add the `started` gate + briefing, and
  pass `def:` to `OutcomeOverlay`.
- **Liveries:** express trains long, red or green; locals white/short. Operator colours used where
  relevant (Worcester: GWR lime `gwrGreen`, West Midlands orange `wmrOrange`).

## Stations

### Saltash (1) — `saltash`
Two platforms with green small + green/red **express** trains (`express: 0.28`). 3-aspect block
signals keep expresses spaced back from locals. Intro to expresses running through.

### Dawlish Warren (2) — `dawlish`
Two platform **loops** off the up/down mains. The player controls **platform starters** — tap to
hold/release a boarded local out of its loop; releasing one throws the interlock and shuts the main
point signal (`…MainBlocked`) so a through express can’t hit it. Long expresses run straight through
the mains and **cannot** divert. Automatic 3-aspect block signals down each main; sun in the sky.
- Key: `upLoopY`/`downLoopY` (loops), `upMainY`/`downMainY` (mains), `xW`/`xE` throats, `blockXs`.
- Signals sit lifted off their tracks: top starter up, bottom starter down-left beside its platform,
  the two point signals up-left / down-right off the mains, halos aligned to lamps.

### Worcester Foregate Street (3) — `worcester`
**Single-line working.** Two platforms; east of them the line pinches to a single Shrub Hill track that
everything shares. Platform 2 (orange, top) departs **east** over it; Platform 1 (lime, bottom) trains
arrive **west** over it. Only one train fits — the player grants the single line one movement at a time.
The Malverns sit on the west skyline; a moon above.

- **Controls (3 tappable signal+circle):** Platform 2 starter (grant *east*, sits at the platform’s
  east end and **holds the train at the berth** until granted), plus **London** and **Bristol** admit
  toggles on their inbound lanes.
- **East throat:** the single line runs to the last junction, then the four destination lines peel off
  **one at a time at staggered junctions** (never all at one point): west→east **London (far up),
  Droitwich (near up), Birmingham (far down), Bristol (near down)** — ordered so lines don’t cross.
  Each junction carries a **3-aspect light reflecting its own road** (green when the line is set that
  way, amber when a train waits on it, red otherwise), lifted off the single line toward its branch.
- **West (inbound-left) approach:** three **3-aspect queue lights** that eastbound arrivals honour
  (hold at a red), lifted up off the P2 approach.
- Key geometry: `yP2=210`, `ySingle=276`, `yP1=344`, `xEJ=800` (throat), `xSH=1200`, `platL=456`,
  `platR=716`, `branchStep=96`, `branchFan=130`, `spawnR=1740`. Start camera `originX=40` (shifted
  right to reveal the eastern entry). P2 deck drawn at `yP2-40` so its 3-D edge clears the rail.
- Goal 40.

### Newark (4) — `newark`
**Flat crossing.** The East Coast Main Line (blue, horizontal) crosses the Nottingham–Lincoln
**Castle line** (orange — a horizontal platform lead that dives across the main line) on the level, at a
**diamond**. Only one train fits the crossover at a time. Newark Castle ruin on the skyline, drifting
clouds, a subtly-graded green.
- **Four lights (two per line):** an **entry** signal (admit a train into the platform, default green)
  and a **platform starter** (send the loaded train over the crossing, default red). The diamond is the
  shared resource — `occupant` weak var, auto-arbitrated: a dispatched train takes it when it arrives
  and it's clear, else holds short. Sequence the two starters so both don't hit the diamond at once.
- A train holds at `entryDist` (entry red), loads and waits at `berthDist` (starter red), then crosses.
- Key: `yEcml=252`, `yCastle=132` (Castle platform lead), diamond `xD=980`, `platL=380`/`platR=860`.
  Entry lights at the platform mouth, starters at the exit end; a non-tappable indicator on the diamond
  goes red while it's occupied. Goal 45.
- **Polish TODO:** entry/starter halos still touch a little; ECML can queue heavily (spawn balance);
  castle silhouette is blocky.

### Birmingham New Street (19) — `birmingham`  *(scaffold — auto-routing)*
12 platforms as **six two-track islands** fanning above/below **two central lanes**. A train shuffles
**one track at a time** (a staggered crossover **staircase**, never a diagonal across the stack) out to
its platform and back to a lane to leave. Throats stretched wide (pannable) so each shuffle plays out
over a long run.
- Key: `trackLevels=14`, central `laneLevels=[6,7]`, `platformLevel(p)` maps 0–5 above / 6–11 below,
  `platL=520`/`platR=860`, throats `xWT=-260`/`xET=1640`, per-platform starting signals red when
  berthed.
- **Not yet built:** player-controlled points (currently trains auto-route to a free platform).

### Generic ladder stations (4–18, 20) — `ladder`
Shared `StationView`. Platforms fed from mains via a points ladder; the player toggles the platform
signals. Difficulty ramps through `StationDef` (spawn/speed/goal/express).

## Build, run, deploy

Sim (fast iterate):
```bash
xcodebuild -scheme TrainStationManager -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath build/sim -quiet build
xcrun simctl install <UDID> build/sim/Build/Products/Debug-iphonesimulator/TrainStationManager.app
xcrun simctl launch <UDID> com.ogs.signalbox
```

Device (signed):
```bash
xcodebuild -scheme TrainStationManager -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=ZQFRPBBFF3 -derivedDataPath build/dev build
xcrun devicectl device install app --device <DEVICE_ID> \
  build/dev/Build/Products/Debug-iphoneos/TrainStationManager.app   # retry on "Connection reset by peer"
xcrun devicectl device process launch --device <DEVICE_ID> com.ogs.signalbox
```

- Registered devices (team `ZQFRPBBFF3`): Simon’s iPhone, Rachel’s iPhone, Keaton’s iPad,
  Mackenzie’s iPad. New devices need Developer Mode + trust + a one-off “Register Device” in Xcode.
- Unlock all stations on a **simulator** for testing (edit the app’s container plist, not the global
  domain, then reboot the sim to clear the cfprefsd cache):
  `PlistBuddy -c "Set :btr.unlockedThrough 21" <container>/Library/Preferences/com.ogs.signalbox.plist`
- Progress key: `btr.unlockedThrough` (station 1 always open; clearing N unlocks N+1).

## Open threads
- Birmingham: build the player-controlled **points routing** (currently auto only).
- Worcester: general polish pass.
- Menu-screen accel/decel easing (long-outstanding).

## Future level ideas
- **Breakdown & rescue** (Simon): a train fails and sits blocking a track; the player keeps the rest
  flowing by routing around the blockage until a **rescue/recovery train** arrives, couples, and drags
  it clear. A dynamic obstacle + countdown. Needs a layout with alternates (a ladder station or a
  passing loop) so there's somewhere to divert.
- **L5 Reedham** — swing bridge on a timer (planned). **L6** — inland reversing terminus, bay
  platforms, trains reverse out (planned; not seaside).
