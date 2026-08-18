# Beat the Rush

**A landscape iOS signal-box puzzle.** The trains drive themselves — you control only the signals and
points. Pull the right levers, in the right order, to route every service to a free platform, let the
passengers board, and send it on its way *before* a platform overflows.

Built in SwiftUI. Every station is a real British junction, hand-laid and run on a shared simulation
toolkit ([RailKit](#railkit--the-engine)).

---

## How it plays

- **Trains navigate themselves.** They find their road, follow the train ahead, ease up to a red, and
  pull away when it clears. You never drive a train — you clear its path.
- **You work the box.** Tap a signal to clear a route, hold a starter to keep a boarded train at the
  platform, grant a single line or a crossing to one direction at a time.
- **People pile up.** A crowd builds on every platform. Board them before the platform overflows past its
  grace period, or you lose. Carry the station's goal number of people and it's cleared — with 1–3 stars
  for how comfortably you kept it flowing.
- **Read the road.** The track just ahead of each train lights **green / amber / red** so you can see
  what has the road and what's held, before it gets there.

## Stations

Seven bespoke junctions, each with its own real-world mechanic:

| Station | Where | The knot to untie |
|---|---|---|
| **Saltash** | Cornwall | A single-line bridge over the Tamar — one train at a time; clear it east or west and they take turns. |
| **Dawlish Warren** | Devon | Two through mains with platform loops; stop the locals to board while expresses and a steam special race straight through. |
| **Worcester Foregate Street** | Worcestershire | A single line to Shrub Hill shared by both directions — grant it out east, or admit an arrival from London or Bristol. |
| **Newark** | Nottinghamshire | The famous flat crossing, where two lines cross on the level — grant the diamond to one train at a time. |
| **Lostwithiel** | Cornwall | A double-track section where the china-clay freight breaks down and blocks the line; divert the traffic and call the rescue loco. |
| **Crewe** | Cheshire | A twelve-platform junction with terminating bays that reverse back out and fly-through expresses on the fast lines. |
| **Birmingham New Street** | West Midlands | Twelve platforms buried under the city, fed by a full ladder throat — route every arrival across the weaving points to a free road. |

## RailKit — the engine

Rather than hand-code each level from scratch, the game runs on **RailKit**, a small shared toolkit. A
new station is *assembled*, not written:

- **`RailGraph`** — a station's track is named nodes joined by named edges; `route([...])` stitches a
  chosen sequence into the path a train follows. Layout is a diagram of names, not a wall of coordinates.
- **`RailSignals`** — one tested implementation of each signal kind: `HoldSignal` (a player's lever),
  `HoldGroup` (a mutually-exclusive set — a single line that takes turns), and `BlockSignal` (an
  automatic three-aspect signal that spaces a queue a block apart).
- **`RailSim`** — the movement engine. Each tick it works out how far every train may advance — the end
  of its road, the train ahead, and whatever the level says is holding it — then eases its speed toward
  a smooth braking target and moves it. Levels plug their rules in through hooks. It supports lane and
  position-based *body-ahead* following, eased and constant-speed feels, per-vehicle kinematics,
  resource holds, overrun, and reversing bays.

All seven bespoke levels run on this one engine, so a fix to the "feel" or a signalling rule improves
every station at once. The engine is guarded by a small [XCTest regression harness](BeatTheRushTests).

See [`docs/DESIGN.md`](docs/DESIGN.md) for the full design canon.

## Project layout

```
BeatTheRush/               App target — SwiftUI
  RailGraph / RailSignals / RailSim   RailKit (the shared toolkit)
  <Station>Station.swift    Per-level model (game logic + geometry)
  <Station>View.swift       Per-level SwiftUI Canvas that draws it
  StationDef.swift          The station roster
  Station.swift, Carriage.swift, …    Shared primitives + drawing
BeatTheRushTests/          RailSim regression tests
docs/DESIGN.md             Design & reference (kept current with the code)
```

## Build & run

Requires **Xcode 16+**, targeting **iOS 17+**. Landscape only.

```bash
# Simulator
xcodebuild -scheme BeatTheRush -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build

# Tests (run after any change to RailSim.swift — it drives every level)
xcodebuild test -scheme BeatTheRush -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

The app is playable, localised in **English, German, French and Spanish**.

---

© Olive Game Studio.
