# Beat the Rush

A top-down 2D railway signalling game in C# and MonoGame, targeting iPhone/iPad with Windows as the development host. The original SwiftUI game is preserved in `prototype/`.

## Run on Windows

Install the .NET 10 SDK. MonoGame 3.8.6 is pinned through NuGet; no global MonoGame template or content-tool installation is required.

```powershell
dotnet restore BeatTheRush.slnx
dotnet run --project src/BeatTheRush.Windows
```

Open `BeatTheRush.slnx` in a .NET 10 capable IDE, or use the included VS Code launch configuration. DesktopGL supplies the Windows development window; it is not the iOS backend.

## Title and station selection

The game opens on an animated title screen: staggered split-flap lettering, a pulsing Play button, and background trains obeying their own signals. Play opens departure-board station tiles. Saltash is playable; the six other bespoke stations from the prototype are shown as not in service until rebuilt. The briefing, pause, and outcome screens include a return to station selection. Best stars are retained for the current app session; persistence is still future work.

Mouse buttons use a buffered SDL event stream, independent of simulation frames. Mobile input uses its own touch component. Both feed the same screen routing and camera transforms.

## Saltash, first playable build

- Two platforms and a single-track Royal Albert Bridge.
- Trains follow the same track graph the renderer draws.
- Automatic same-route following, acceleration, braking, and approach indicators.
- Local and longer fast trains; both stop to board, as in the Swift prototype's Saltash.
- Boarding, passenger capacity, platform pressure, an 18-second overflow grace period, and a 30-passenger objective.
- A bridge reservation covering both throats. Changing a signal never releases a train's reservation early; its tail must clear.
- Briefing, pause/resume, retry, and outcome screens.
- One enlarged operational view, with signals controlled directly on the map.

Click or tap an **E** or **W** signal to select that direction. Tap the selected signal again to hold both approaches. Green means selected and available; amber means selected while a train owns the protected section; red means held. Automatic approach lights have no tap controls.

Menu shortcuts: **Enter** Play/select, **arrow keys** choose a station, **Escape** back. Windows game shortcuts: **Enter** start/resume, **E** east, **W** west, **H** hold both, **Space/Escape** pause/resume, **R** restart. Losing focus pauses the shift.

This is an initial playable rebuild. Audio, haptics, saved progression, bespoke final art, and Dawlish are not implemented yet.

## Build and test

```powershell
dotnet build BeatTheRush.slnx
dotnet test BeatTheRush.slnx
# Start the real graphics backend, run briefly, save an optional preview, then exit:
dotnet run --project src/BeatTheRush.Windows -- --smoke-test --screen saltash --screenshot saltash.png
# --screen title or --screen stations previews the menu screens.
```

Tests exercise graph validation, path sampling, following, boarding, bridge ownership and tail clearance, overflow, victory, deterministic reset, a complete Saltash shift, mouse-to-signal coordinates across window sizes and DPI scales, menu navigation, split-flap timing, and title-scene signal holds.

## iPhone and iPad

`BeatTheRush.iOS.slnx` loads the iOS host and the same simulation. It compiles the exact same game source files as the Windows host against `MonoGame.Framework.iOS`. Landscape orientations, iPhone/iPad device families, a launch storyboard, safe-area handling, and background pausing are configured.

A **Mac with a compatible Xcode and .NET 10 iOS toolchain is required** to build and deploy. On that Mac:

```sh
dotnet workload install ios maui
dotnet build src/BeatTheRush.iOS -f net10.0-ios -r iossimulator-arm64
# Physical device: configure your Apple signing identity/profile, then:
dotnet build src/BeatTheRush.iOS -f net10.0-ios -r ios-arm64
```

Use `iossimulator-x64` for an Intel Mac. The development bundle ID is `com.ogs.signalbox`, matching the prototype. Supply your own signing configuration; no certificates are stored here. App Store icons and release packaging remain to be added.

The default Windows solution deliberately excludes the iOS project so everyday builds and tests do not require mobile workloads. The iOS managed code compiles against the Windows iOS workload, but the app has not been packaged or tested on Apple hardware; safe areas, touch behaviour, lifecycle, and performance still need device validation.

## Structure

```text
src/BeatTheRush.Core/       Framework-free simulation, graph, and station data
src/BeatTheRush.Game/       Shared source: session, input, viewport, rendering components
src/BeatTheRush.Windows/    DesktopGL entry point
src/BeatTheRush.iOS/        .NET iOS entry point and Apple configuration
tests/BeatTheRush.Core.Tests/
docs/DESIGN.md              Current rebuild architecture and behaviour
prototype/                 Preserved SwiftUI reference
```

The shared game directory intentionally has no framework-bound class-library project. Both hosts compile those sources against their own MonoGame backend, avoiding a DesktopGL dependency in the iOS application.

The font atlas is generated from Barlow Medium under the SIL Open Font License. Its license is included in `src/BeatTheRush.Game/Assets/Barlow-OFL.txt`. No external art or font installation is required at runtime.

Official platform/toolchain references: [MonoGame platforms](https://docs.monogame.net/articles/getting_started/platforms.html), [Windows setup](https://docs.monogame.net/articles/getting_started/1_setting_up_your_os_for_development_windows.html).



