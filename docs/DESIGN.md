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
enum StationKind { case ladder, saltash, dawlish, worcester, birmingham, newark, crewe }
```

- **Bespoke stations:** Saltash (1), Dawlish Warren (2), Worcester Foregate Street (3),
  Newark (4), **Crewe (5)**, Birmingham New Street (19). Each has its own Station/View pair.
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
- **Pinch-to-zoom + 2-axis pan** (Crewe, Birmingham): the view also holds `originY` and a `zoom`
  (`@State`), `sc = size.width/worldW * zoom`, and combines the drag with a `MagnificationGesture`
  (`.simultaneously`). `clampOrigin(_, visibleW)` / `clampOriginY(_, size, sc)` keep the content in view
  at any zoom (centre when the content is narrower/shorter than the viewport). Crewe **starts at
  `zoom = 0.8`** so more of the wide layout is in view; range ~`0.55…2.2`.

### Shared systems
- **Kinematics:** ease `v` toward `target = min(speedCap, sqrt(2*decel*headroom))`; `ceiling` is the
  min of all constraints (berth, signal holds, train-ahead tail − gap). Overrun ceiling so long trains
  don’t vanish while their tail is still on-screen.
- **Position-based following** (Crewe, Birmingham): a train holds clear of any train whose *body* lies
  across the road ahead — sampled from real `(x,y)` positions, not just same-platform/same-target — so
  crossing moves through a throat's merges and splits never overlap. "Ahead" is decided by progress
  (`o.dist > t.dist`, ties by id) so a merge always has a clear winner and never deadlocks. Crewe uses
  `blockedAhead`/`bodyNear` (hard stop); Birmingham uses `aheadCeiling` (a distance, for smooth decel).
  This replaced the older "hold behind the train ahead on the same platform/fast-line" check, which let
  a follower overrun a leader the moment it peeled off toward its platform.
- **Sim-only debug tags:** bespoke views can draw a `#if targetEnvironment(simulator)` overlay
  (`drawDebugTags`) labelling every platform/signal with its id and design coordinates, so the layout
  can be nudged by name. Compiled out of device builds entirely.
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
- **Route lighting:** the stretch of track just ahead of each train lights **green / amber / red** so you
  can read the route it will take and whether it has the road — green = clear run, amber = closing on
  something, red = held. Driven by each train's movement authority (`railAspect`, from the same `ceiling`
  the kinematics use). `drawRouteLights` — rolled out across the stations.
- **Liveries:** express trains long, red or green; locals white/short. Operator colours used where
  relevant (Worcester: GWR lime `gwrGreen`, West Midlands orange `wmrOrange`).

### Feel — the small behaviours
The little touches that make it read as a living station. These are behaviours, not just constants —
keep them true as the code changes.

- **Passengers fill the train at random until it's full.** Each carriage window has its own stable
  random threshold (`seed = train.id ⊕ car`), so as a train boards, seats light up **scattered about**,
  not left-to-right — the carriages just look fuller and fuller until the whole train is full. Amount lit
  = `fill = load / (length·3)`. Dawlish's through expresses arrive **pre-loaded ~75%** so a fast train
  already looks busy.
- **People wait, and get impatient.** A person stands on the platform per arrival. They start happy; the
  longer they wait the crosser they get — a mood bubble climbs **happy → waiting → cross** (`mood`), and
  once past `agitateAfter` they **fidget/pace** and wear an angry red coat. Let a platform stay jammed at
  `platformCap` past `overflowGrace` and you lose.
- **Each boarding throws a sparkle** that flies from the platform to the people counter, so you *see*
  the number tick up. (Crewe's passenger figures are drawn larger, with a dark outline, to stay legible
  when zoomed out.)
- **Trains ease, don't teleport.** They accelerate away and brake smoothly toward whatever's stopping
  them (`sqrt(2·decel·headroom)`), so a train **screeches to a stand** at a red rather than snapping to
  it, and pulls away again when it clears. A long train **overruns the exit** so it doesn't vanish while
  its tail is still on screen.
- **You can read a train's intent** from the coloured road just ahead of it (green/amber/red route
  lighting) before it gets there.

## Stations

### Saltash (1) — `saltash`
Two platforms with green small + green/red **express** trains (`express: 0.28`). 3-aspect block
signals keep expresses spaced back from locals. Intro to expresses running through.
- The **Royal Albert Bridge is drawn in front of (over) the trains** — trains pass *under* its spans, so
  the drawing order puts the bridge last.

### Dawlish Warren (2) — `dawlish`
Two platform **loops** off the up/down mains. The player controls **platform starters** — tap to
hold/release a boarded local out of its loop; releasing one throws the interlock and shuts the main
point signal (`…MainBlocked`) so a through express can’t hit it. Long expresses run straight through
the mains and **cannot** divert.
- **Heritage steam special** (occasional, same rarity as the speedboat): a fast service that **never
  stops**. A 3-D–extruded Brunswick-green engine matching the coaches' depth (`drawSteamLoco`), a
  **single central yellow dome and one funnel**, an **animated coupling rod**, and a short rake of
  brown, squarer, non-overlapping coaches — already ~75% loaded. It runs at ~2× local speed and, while
  approaching, shows a **"Special"** warning pill (not "Fast").
- **Smoke** (`drawSteamPlume`): streams **backwards** from the funnel, moving fast then slowing, with a
  **per-particle random speed** and a short fade so there's plenty of it.
- **Ambient life** (all occasional / parallax so the scene lives without clutter): dune **grass** and the
  **sun** scroll with a **parallax** offset; a **speedboat** crosses the front with an **animated
  rippling wake** and is **affected by the panning**; a lighter, **animated seagull** in the sky; and a
  slow **tanker on the horizon**, high up and distant.
- Automatic 3-aspect block signals down each main.
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

### Crewe (5) — `crewe`
A big twelve-platform through junction. Trains **arrive from the east**, self-navigate, and the player
controls the lights. Wide and tall — **pinch-to-zoom + 2-axis pan**, starts at `zoom = 0.8`.

**Platforms (`CrewePlat`, `plats`):**
- **Through** (arrive east → berth → leave west): P1 (`y=-30`, across the top), P5 (`220`), P6 (`360`),
  P7 (`424`), P8 (`488`). `throughIds = [1,5,6,7,8,11]`.
- **East-facing bays** (buffer at the west end `xL=820`, open east — a train pulls up to the buffer,
  boards, then **reverses back out east**; no west exit): P2 (`34`), P3 (`88`), P4 (`142`).
  `bayIds = [2,3,4]`.
- **Two express "fast" lines** between P5 and P6, `fastY=[262,316]` — non-stop fly-throughs, kept clear
  of stopping traffic.
- **Two "slow" lines** the platforms gather onto in the throats, `slowY=[200,380]`, flanking the express
  pair. Top slow carries P1/P5 + the bays; bottom slow carries P6/7/8 + the single line.
- **Single line** `singleY=606`, faced by **P11** (above) and **P12** (below). A platform's *running
  line* can differ from its slab: `CrewePlat.lineY` (= `lineOverride ?? y`); P11/P12 both
  `lineOverride: 606`. **Island faces** share a line too — P7+P9 (`424`), P8+P10 (`488`).
- A berthed train boards **every face standing on its line** (`facesOnLine`, matched on `lineY`), so the
  far island faces and the single line's two faces all get cleared. Passengers wait on **all 12**.

**Throat & feed-in:** each platform gathers onto its slow line via a **staggered staircase** of points
(one turnout at a time); the top group (P1 + bays) cascades `1→2→3→4→slow` (`topCascade`). Each slow
line then **feeds into its fast line** at both mouths via a turnout spur, so the sides run into the fast
tracks rather than dead-ending. Geometry: `xSL=300`/`xSR=1300` (platform ends), `xW=-760`/`xE=2360`
(spawn/exit), `xWMouth=-120`/`xEMouth=1740` (throat mouths), `throatY=289`, concourse gap `720…900`.

**Signals** (all lifted off the line; `S` are the only player controls):
- **E** (entry, east end) — red while the platform is occupied.
- **S** (starter, west end) — **tappable**: holds/releases the berthed train (`platformHeld`); a bay's is
  its reverse release.
- **Pt** (east point light, at the throat turnout) — red when the platform is occupied *or* the top
  throat is reserved for a reversing bay.
- **WPt** (west point light) — mirror of Pt for departing trains (bays reverse east, so have none).
- **FJ** (join signals where the slow lines feed the fast) — `FJe` (east mouth / top fast), `FJw` (west
  mouth / bottom fast): red while a stopper is in that mouth on the paired slow line. An **express
  reaching a red join brakes hard to a stand** (`joinOccupied`, `eDecel=520`), then accelerates away.
- *(There is no home signal — one used to sit across the expresses and was removed as confusing.)*

**Routing (`pickPlatform`, round-robin):** rotate to the next clear through platform so arrivals fan
evenly; keep rotating even when all are taken (spread the queue rather than stack one road). The
**single line (11) is on-demand** — only routed to once its two faces have `8+` waiting. **Bays** are
occasional (~30% when a bay is free) and **one at a time**. A **reversing bay** reserves the top slow
line (`reverseActive`): it runs against the arriving flow, so top-slow arrivals are held off (their point
lights go red) until the throat clears, then it backs out briskly.

**Expresses:** long silver rakes, a power car (`endCap`) at each end and a headlight at the nose; top
fast runs west→east, bottom east→west (up/down fasts); `expressSpeed=550`, spawned every 4–9s.

Constants: `baseSpeed=86`, `dwellTime=2.4`, `platformCap=16`, goal 55. **Bay-and-reverse** and the
express/junction conflict are the level's texture; the **breakdown-and-rescue** mechanic is still to
build here.

### Birmingham New Street (19) — `birmingham`  *(auto-routing)*
12 long through platforms as **six two-track islands** fanning above/below **two central lanes**. A
train shuffles **one track at a time** (a staggered crossover **staircase**, never a diagonal across the
stack) out to its platform and back to a lane to leave. Throats stretched wide (pannable) so each
shuffle plays out over a long run.
- Key: `trackLevels=14`, central `laneLevels=[6,7]`, `platformLevel(p)` maps 0–5 above / 6–11 below,
  `platL=520`/`platR=860`, throats `xWT=-260`/`xET=1640`, per-platform starting signals red when
  berthed.
- Tidied with the Crewe learnings: **position-based following** (`aheadCeiling`/`bodyNear`) so crossing
  moves don't overlap, **round-robin routing** (`routeCursor`) so arrivals fan evenly, **pinch-to-zoom +
  vertical pan**, and sim-only debug tags.
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
- **Crewe:** verify the **PL11 (single line) signal** — Simon reported trains ignoring it (may have been
  a symptom of the earlier over-routing, now on-demand). Build the **breakdown-and-rescue** mechanic here
  (Crewe has the alternates for it). Consider whether the join signals should be player-tappable rather
  than auto. Rebalance the bottom slow line (P6/7/8/11) vs the top (P1/P5) if it feels lopsided.
- Birmingham: build the player-controlled **points routing** (currently auto only).
- Worcester: general polish pass.
- Menu-screen accel/decel easing (long-outstanding).

## Future level ideas
- **Breakdown & rescue** (Simon): a train fails and sits blocking a track; the player keeps the rest
  flowing by routing around the blockage until a **rescue/recovery train** arrives, couples, and drags
  it clear. A dynamic obstacle + countdown. Crewe is the intended home (it has the alternates to divert
  around a blockage).
- **L6 snow**, **L7 UK freight** (long trains) — logged themes.
