# MonoGame rebuild: design and architecture

## Direction

Top-down 2D. Saltash is the first playable station; Dawlish is the next reuse test. Preserve the prototype's automatic trains, signals, boarding, queues, and station-specific operational challenges. The Swift source in `prototype/` remains the behavioural reference.

**Composition is the default.** The MonoGame Game subclass adapts the framework lifecycle and delegates to components. Partial classes are reserved for source-generated JSON contexts, not used to conceal a large behavioural class. Systems have explicit constructor dependencies; there is no global service locator, inheritance hierarchy of station models, or general-purpose ECS.

## Components

- `StationSimulation`: constructs the systems, exposes their state, and orders each fixed update.
- `StationState`, `TrainState`, `PlatformState`: simulation data with no rendering types.
- `TrackGraph` / `TrackPath`: validate the station graph, resolve named routes, and sample distance along polylines.
- `TrafficScheduler`: seeded passenger/train arrival scheduling and entrance admission.
- `TrainMovement`: acceleration, braking, same-route following, and movement ceilings.
- `PassengerService`: boarding, dwell, crowd pressure, and outcomes.
- `BridgeInterlocking` / `ExclusiveSection`: selected direction, physical ownership, and tail clearance.
- `BlockSignals`: occupancy-based aspect queries.
- `GameSession`: briefing/pause/retry state and player commands.
- `PlayerInput`: buffered keyboard commands composed with a desktop MousePointer or mobile TouchPointer; SignalTapRouter maps clicks through the camera to map signals.
- `CanvasViewport` / `GameLayout`: safe-area fit, shared camera transform and inverse, and overlay hit regions.
- `GameRenderer`: graphics resources, render target, clipping, and composition of render passes.
- `StationRenderer`: explicit scene draw order through scenery, track, platform, train, and signal renderers.
- `HudRenderer` / `OverlayRenderer`: header and modal screens.
- `Painter`: low-level shapes and an embedded bitmap font.

## Station authoring

`src/BeatTheRush.Core/Stations/saltash.json` owns graph nodes, undirected edges, optional shaping points, named train routes, platform rectangles, signal anchors, section entry/exit anchors, spawn ranges, and tuning. The graph is used for both drawing and train movement; missing nodes/edges fail explicitly.

This slice supports one exclusive section, and each route has one platform stop. Do not pretend this already models arbitrary junctions. Dawlish should extend the composition with loop/through service routes and conflict resources when those requirements are concrete.

Scenery placement is still a small hand-authored Saltash backdrop. There is no visual station editor yet. Editing layout data is the starting workflow.

## Saltash behaviour

Eastbound trains board at platform 1 before crossing the bridge. Westbound trains cross first, then board at platform 2. Both local and fast trains stop, matching the existing Saltash implementation.

The selected direction is player intent. A train acquires the protected section at its hold point only if that direction is selected and the section has no owner. It retains that reservation after any signal change, until its tail is eight design units past the far throat. The next train in either direction must wait. No collision priority is inferred from unrelated route distances.

Following uses a shared position snapshot each tick, train length, and a 30-unit gap. Stock cannot spawn into an occupied entrance. Movement accelerates toward a speed cap and brakes toward the nearest following, boarding, or interlocking limit.

Train carriage length is 38 design units, capacity three passengers per carriage. Boarding rate is six passengers/second; minimum dwell is 2.6 seconds. Platforms hold 16 people. A full platform gets 18 seconds of grace. Board 30 people to win. Stars follow the prototype's carried milestones: first passenger, halfway, goal.

Approach signals display red for an occupied block and amber for occupancy in the following block. Same-route following enforces spacing. Portal amber means the player's direction is selected but the protected section is reserved; the owning train continues.

## Presentation and input

Train carriages do not display passenger occupancy dots. Boarding, onboard capacity, platform crowds, and the boarded counter continue to be simulated.

The main map fills the space below the header. There is no bottom control strip. Direct map signals accept desktop mouse clicks or mobile touch input. Platform destination labels, bridge-status messages, and the River Tamar annotation are omitted. The map is framed more closely than the initial pass. Large signal hit areas and a shared inverse camera transform keep input aligned with drawing.

Rendering uses a 1600x900 virtual canvas, fitted within the window or iOS safe area. Other aspect ratios letterbox without stretching. The game loop uses fixed 60 Hz simulation updates; the framework's initial zero-duration update is ignored. Focus loss/backgrounding pauses the shift; resuming is explicit.

## Current limits

Windows builds, unit tests, and real graphics startup are validated during development. The iOS managed code compiles against the installed Windows iOS workload; a complete Mac build and physical iPhone/iPad validation are still required. Font metrics use source-generated JSON for AOT compatibility; graphics are created procedurally or loaded from embedded PNG data, so the first slice does not require MGCB.

Audio, haptics, persistence, release icons, a visual editor, larger network layouts, additional resource types, and Dawlish are subsequent work. Do not couple them into the framework lifecycle adapter.


DesktopGL buffers window-specific SDL2 button and motion events through SdlMouseEvents; it does not rely on TouchPanel mouse emulation or per-frame button polling. Press/release pairs are retained even if both happen between simulation updates. The event observer leaves MonoGame's own queue intact and is detached when the input component is disposed. Mouse client coordinates are converted to back-buffer pixels before canvas and world transforms, including resized, high-DPI, and letterboxed windows. Pending pointer gestures are cancelled on focus loss.


## Title and station-selection extraction

AppFlow owns navigation and screen lifetimes; gameplay remains in GameSession. ScreenInputRouter dispatches mouse/touch taps and keyboard commands according to the current screen. MenuLayout shares hit regions with the renderers. StationCatalog contains the seven bespoke prototype stations, with only Saltash available in the rebuild. Disabled entries cannot instantiate gameplay.

SplitFlapAnimation is a pure elapsed-time sampler using the prototype character set, 0.05-second flips, 0.04-second column delay, and 0.09-second tile delay. SplitFlapRenderer draws clipped upper/lower glyphs and hinged leaves. TitleScreenRenderer repeats the reveal every 22 seconds and draws a pulsing Play control. StationSelectRenderer composes departure-board cards. MenuRailway and MenuRailwayRenderer independently own the decorative train/signalling animation; they never step the playable Saltash simulation.

The title leads to selection, then a fresh station briefing. A Stations action on briefing/pause/outcome overlays returns to the board; the board Back action returns to the title. Best stars are in memory for the current app session, recorded on a completed or failed shift. Audio/haptics and persistent progress from the Swift app are not copied into this extraction.

SDL event observer reference: https://wiki.libsdl.org/SDL2/SDL_AddEventWatch . The adapter is desktop-only and excluded from the iOS compilation.


