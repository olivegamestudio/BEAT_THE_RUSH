# Beat the Rush — Design & Reference

A landscape iOS SwiftUI signal-box puzzle. Trains self-navigate; the player controls only the
signals/points. Clear each station by carrying its goal number of people before a platform overflows.

> **Living document — keep it current at all times.** This file is the design canon and **must be kept
> up to date at all times**. Any change to a behaviour, mechanic, layout, control, signal, or constant is
> updated here **in the same change** that touches the code — never left to drift, never deferred to
> "later". Every working session that changes the game corrects this doc before it's done. If anything
> here ever disagrees with the code, the code wins and this file is fixed on the spot.

- Bundle id: `com.ogs.signalbox` · Display name: **Beat the Rush**
- Remote: `github.com/olivegamestudio/TrainStationManager`, work lands on `main`.

## Architecture

Each station is a pair: a `…Station` model (`ObservableObject`, all game logic + geometry constants)
and a `…View` (SwiftUI `Canvas` that draws it). `StationDef.swift` lists every station (`allStations`,
ids 1–20) and a `StationKind` picks which view/model to use.

```
enum StationKind { case ladder, saltash, dawlish, worcester, birmingham, newark, crewe, lostwithiel }
```

- **Bespoke stations:** Saltash (1), Dawlish Warren (2), Worcester Foregate Street (3),
  Newark (4), **Crewe (5)**, **Lostwithiel (6)**, Birmingham New Street (19). Each has its own
  Station/View pair.
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
- **First level built on RailKit** (the shared toolkit, below). Its layout is a `RailGraph` (the two
  routes are stitched from named nodes/edges — the bridge is one *shared* edge both directions traverse),
  its filter signals and bridge levers are typed `BlockSignal`/`HoldGroup`, and its trains ride the shared
  `RailSim` movement engine; only Saltash's own rules (boarding, the single-line turn-taking, spawn
  balancing) live in the model, as sim hooks. Because it now uses the shared kinematics, its trains
  **ease and screech to a stand** at a red rather than snapping to it — the feel the doc asks for
  everywhere. `SaltashView` (rendering) is unchanged — still bespoke (graph rendering is a later piece).

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
express/junction conflict are the level's texture. (Breakdown-and-rescue was considered here but built at
**[[Lostwithiel (6)]]** instead — Crewe already carries enough.)
- **Passengers seed a crowd.** Twelve platforms fed one arrival at a time left trains berthing and leaving
  almost empty, so each platform starts with `Int.random(3...7)` waiting (`seededCrowd`) and arrivals top up
  **two** platforms per tick — otherwise the carriages never visibly fill.

### Lostwithiel (6) — `lostwithiel`  *(breakdown & rescue)*
A **double-track** section in the Fowey valley — **no platforms**, a pure congestion level. Trains run
left↔right on their own lane (up lane `yTop=196` eastbound, down lane `yBot=300` westbound), so normally
it just flows — two independent lanes, no head-on possible. `carried` counts **trains sent through**, not
people. Goal 22.

- **The event:** once three services are through, a slow, **steam-hauled china-clay freight** (an engine
  drawn with `drawSteamLoco` + **ten short clay hoods** at `wagonUnit=34` spacing, smoke off the chimney
  via `drawSteamPlume` while it moves) plods up the **up lane** and **fails** at `xFreight=780`. It sits
  dead, a wall on the up lane, wearing a ⚠️ flash.
- **After the block:** up-line services **divert** — across the **west crossover** (`xCW=380`) onto the
  down lane, along the shared stretch, back up the **east crossover** (`xCE=900`). That stretch of the down
  lane (`[contestL, contestR]`) is now shared by both directions, so they **take turns**: one **Saltash-style
  route light** (`passGreen: Dir?`, tap a signal to clear that way) grants it one direction at a time; a
  train holds at its crossover until granted **and** the stretch is clear of the other way. Up-trains already
  past `xCW` when it fails are stuck behind the freight until the rescue (realistic).
- **The rescue:** a **visible siding** each side of the running lines (`casualtyStub` up, `rescueStub` down,
  both drawn with buffer stops). When the freight fails, `rescueReady` turns the **siding starter** green;
  tapping it sends the **orange rescue loco** out — up onto the up lane at the east crossover, west to the
  casualty, **couples**, then **hauls it east into the refuge siding**. Once it's away, `broken` clears, the
  road reopens, and you clear the backlog.
- **Win:** `carried >= goal` **and** `rescued`. **Lose:** a portal backlog (`eastBacklog`/`westBacklog`)
  over `maxBacklog=5` for longer than `overflowGrace`.
- Replaced the generic Hereford at slot 6. **Still to tune by feel:** breakdown timing, backlog balance,
  the rescue choreography, and whether the freight should stop *fully* on-screen (currently mid-loop of the
  view). Rescue loco also puffs smoke while running.

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

### Building a new bespoke station — the recipe (so you needn't re-scan)
A station is a `…Station` model (`ObservableObject`) + a `…View` (`Canvas`). Copy Saltash as the
template; it is the closest pattern (bespoke, route-light, pannable).

**Shared helpers you can rely on (don't reinvent):**
- `RoutePath([CGPoint])` → `.sample(d) -> (p, angle)`, `.smoothAngle(d)`, `.total`,
  `.distanceTo(vertex: i)`. A train's `dist` is arc-length along its path.
- `Train(length:tint:name:)`, `.carLength`; `Track.carUnit = 50`, `Track.carHeight = 34`, `Track.H = 452`.
- Drawing (`Carriage.swift`): `drawCarriage(ctx, at:, angle:, tint:, cw:, ch:, scale:, endCap:, fill:, seed:, cornerRadius:)`,
  `drawSignal(ctx, at:, red:, scale:)`, `drawBlockSignal(ctx, at:, aspect:, scale:)`,
  `drawRouteAhead(ctx, pts, aspect:, scale:)`, `drawSparkleBurst(...)`, `drawMood(ctx, emoji, at:, scale:)`,
  `drawSteamLoco(...)`. Movement authority → aspect: `railAspect(headroom:, clearToEnd:, amber:)`.
- Flow/UI (`AppFlow.swift`): `GameOutcome`, `Mood`, `Progress`, `levelStars`, `levelTasks`,
  `OutcomeOverlay`, `LevelBriefing`, `SignalHalo`, `PressStyle`, `Vignette`, `MuteButton`, `ConfirmDialog`.
- `Sound.shared.play(.board/.depart/.ding/.win/.lose/.ui/.tap)`; `Sparkle`, `sparkleLife`.

**View scaffolding (from Saltash):** `@StateObject` the model; a `Timer.publish(every: 0.03)` that
calls `station.tick(0.03)` only while `started`; `designW` + `originX`/`clampOrigin` + `project(p,scale,size)`
for the panned window; a `Canvas` drawing relief → rails → route-lights → trains → signals; a `controls`
`ZStack` (signal `Button`s over `SignalHalo`, back, mute, score, name); the `started`-gated `LevelBriefing`;
the `OutcomeOverlay` on `outcome != .playing`; a `ConfirmDialog` for exit.

**Model tick pattern:** iterate a `let roster = trains` snapshot; compute a `ceiling` (min of every
constraint — berth, held signal, train-ahead tail − gap), `t.dist = max(t.dist, min(t.dist+step, ceiling))`;
set `t.railAspect`; never mutate `trains` inside the loop (defer spawns/removals).

**Wiring a new station (five touch-points):** add the `StationKind` case (`StationDef.swift`); give it a
row in `allStations` with `kind:`; add its first-move label in `levelTasks` (`AppFlow.swift`); add the
`case` in `RootView`'s play switch; and (bespoke) add the `started` gate + `OutcomeOverlay(def:)`.

## Planned: a shared level toolkit ("RailKit")

**Problem.** Bespoke levels are built from scratch — each `…Station` reimplements its own tick, signals,
routing and geometry. Layout alone is ~a day per level, and a fix in one (e.g. the filter-signal cascade
in Lostwithiel) doesn't reach the others. To reach twelve levels this has to become assemble-from-pieces.

**Approach.** Build a shared foundation and prove it on a level; leave the other working bespoke levels
alone and migrate them opportunistically, not in a big bang. **Phase 1 (pieces 1–3) is built and proved
on Saltash** (the first level composed on it — see [[Saltash (1)]]), and **Dawlish Warren and Worcester
Foregate Street are now fully migrated onto it too** (pieces 1–3, each in three verified steps: track
graph → typed signals → movement engine). Dawlish drove the per-vehicle-kinematics and overrun additions
to piece 3 below; Worcester models its player-granted single line as a three-way `HoldGroup` (like
Saltash's bridge) and its Platform 2 approach queue as a `BlockSignal` chain. **Lostwithiel is now fully
migrated too** (pieces 1–3): RailGraph lanes/crossovers; two `HoldSignal` route lights + two `BlockSignal`
filter chains; and its movement on `RailSim` with the scripted breakdown/rescue in the hooks. Lostwithiel
is constant-speed (no easing), which it keeps by giving the sim **huge accel/decel (100000)** so the eased
step behaves like the old fixed-step move (full speed until the ceiling, then a hard stop) — proving the
engine spans both eased and constant-speed levels. Still legacy: Birmingham, Newark, Crewe (crossing
levels — they need the position-based body-ahead follow mode). The *next* new level (US freight) should be
laid out from the toolkit directly.

**Pieces (roughly in build order):**
1. **Track graph — BUILT (`RailGraph.swift`).** A level's lines are named polyline `RailEdge`s joined at
   named `RailNode`s; `RailGraph.route([nodeIDs])` (the `Router`) stitches a chosen node sequence into a
   `RoutePath`. One *shared* edge can serve both directions (Saltash's single-line bridge is one edge the
   two routes traverse opposite ways). Layout becomes a small diagram of names, not hand-placed
   coordinates. (Rendering the graph is piece 4 — not yet built; views still draw their own rails.)
2. **Signals as types — BUILT (`RailSignals.swift`).** `HoldSignal` (player-tappable, latches the player's
   intent to clear a route/direction — the Saltash/Lostwithiel levers) with `HoldGroup` for a
   mutually-exclusive radio set (Saltash's two bridge portals: only one direction cleared at a time);
   `BlockSignal` (automatic 3-aspect — red while its block is occupied, amber while the next signal's is,
   the filter signals). Each owns the stretch it protects and computes its own aspect from an occupancy
   test the level hands it, so the same type serves any axis-aligned line. One tested implementation
   instead of per-level copies.
3. **Movement engine — BUILT (`RailSim.swift`).** A generic `RailSim<V: RailVehicle>` owns the trains and,
   per tick, computes each train's ceiling = min(path end, built-in follow-gap to the train ahead **on its
   lane**, and a level `ceiling` hook for held-signal/resource/berth stops), then **eases `v`** toward a
   sqrt braking target (`v² = 2·decel·headroom`) so trains brake smoothly to a stand and accelerate away —
   the shared kinematics + route-light `aspect` every level was re-implementing. Level rules plug in via
   hooks: `ceiling`, `speedLimit` (caution at amber), `onAdvance` (boarding, grabbing a resource),
   `isFinished`/`onFinish`, plus `kinematics` (per-vehicle feel — Dawlish's brisk express vs gentle local)
   and `overrun` (extra arc-length past the path end so a long train's tail clears the exit). *(Position-based
   body-ahead for crossing moves — the Crewe/Birmingham rule — is the intended default follow mode; Saltash's
   lanes never cross off the resource-gated bridge and Dawlish does its own shared-physical-track follow in the
   `ceiling` hook (unique lane per train), so neither needs it yet. Body-ahead lands when a crossing level is
   migrated.)*
4. **Rendering — planned.** `drawGraph` draws every edge in the rail style; reuse `drawCarriage`/
   `drawSignal`/`drawBlockSignal`/route-lights placed from the definitions.
5. **Level scaffold — planned.** A base the level composes: graph + signals + sim + the shared HUD
   (briefing, `ScoreTicker`, pause, mute, haptics, outcome) in a thin `RailLevelView`. A new level =
   define the graph, place signals, write only its unique mechanic.

Each of 1–5 is independently shippable; a level can adopt them piecemeal. Success measure: US freight is
laid out and running in hours, not a day, and a signalling fix lands once.

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
  a symptom of the earlier over-routing, now on-demand). Consider whether the join signals should be
  player-tappable rather than auto. Rebalance the bottom slow line (P6/7/8/11) vs the top (P1/P5) if lopsided.
- **Lostwithiel:** tune by feel — breakdown timing, backlog balance, the rescue choreography; confirm the
  two lanes flow cleanly and both sidings read clearly. (Breakdown & rescue now lives here, not Crewe.)
- Birmingham: build the player-controlled **points routing** (currently auto only).
- Worcester: general polish pass.
- Menu-screen accel/decel easing (long-outstanding).
- **Split-flap departure board — BUILT (`FlapBoard.swift`).** The menu title **"BEAT THE RUSH"** and the
  **station-select screen** are now split-flap boards. `enum Flap` holds the charset + palette; each cell's
  glyph is a **pure function of elapsed time** (start blank, step through the charset to the target at
  `stepDur=0.05`, staggered `cellStagger=0.04`/column, `tileStagger=0.09`/board), so there's no mutable flip
  state — the board reads the clock. `drawFlapCell` draws two charcoal leaves + seam and, mid-flip, the
  folding leaf squashed about the hinge (a 2-D fake of the fold) with the new glyph revealed behind. Driven
  by `TimelineView(.animation)` **only while revealing**, then frozen to a static `Canvas` (costs nothing at
  rest). `FlapHeadline` = the title; `StationBoardTile` = one mini board per station — **unlocked** flaps in
  `boardName`/county/status (`CLEARED` amber / `ON TIME` green) + stars; **locked** stays **blank** ("not in
  service"). `StationDef.boardName` shortens long names to the town. Web feel-prototype:
  `scratchpad/departure-board.html`.
  **Still to tune:** the per-flap **tick sound** isn't wired to `Sound` yet; trailing blank cells on short
  names; reveal pacing; a locked→in-service flap when a level is cleared.

## Future level ideas
- **Breakdown & rescue** (Simon): *built* as **[[Lostwithiel (6)]]** — a double-track section where the
  clay freight fails, up-line traffic diverts and takes turns over the down lane, and a rescue loco is
  called out of its siding to drag the casualty into the refuge. (Was first mooted for Crewe.)
### The road to twelve levels
Seven are built (Saltash, Dawlish Warren, Worcester, Newark, Crewe, Lostwithiel, Birmingham). The plan is
**twelve total**, each hanging on a *distinct* mechanic — a new level earns its place by teaching something
the others don't. The next five, agreed with Simon:

- **US freight — the long-train "meet."** A mile-long double-stack freight ties up a single-track section
  for ages; you're the dispatcher deciding who takes the siding and who waits. Add a **grade crossing** with
  road traffic queuing. The lever is *length and priority*, not failure — deliberately unlike Lostwithiel.
  Prairie/desert.
- **Norway snow (one or two levels) — weather changes the physics.** Snow lengthens braking and trains slip
  on the steep Bergen/Flåm gradients, so timing gets harder; a **recurring snowplough** must clear drifts
  blocking a section (a rhythmic cousin of Lostwithiel's rescue). Fjords, tunnels, snow sheds. Possibly a
  gentle "falling snow" level and a brutal "blizzard + plough" one.
- **London Underground — headway & flat-junction interleaving.** Keep a dense service **evenly spaced** so it
  doesn't bunch (new scoring: "keep it even", not just throughput), and **interleave two lines at a flat
  junction** (Camden Town). Tunnels = limited sightlines.
- **India — Darjeeling spiral loops.** The unique-geometry level: a train climbs **over itself** round the
  Batasia loop. (Mumbai suburban was the alternative — dropped to avoid repeating the Tube's frequency idea.)

Differentiation is the watch-point: breakdown/rescue is spoken for (Lostwithiel), and frequency should appear
once (the Tube, not also Mumbai). That's 7 + 5 ≈ 12; a spare snow level or a second world station rounds it out.
