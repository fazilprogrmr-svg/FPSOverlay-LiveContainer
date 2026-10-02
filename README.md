# FPSOverlay

A lightweight iOS game performance overlay for games running through **LiveContainer**.

FPSOverlay provides real-time FPS and performance information directly on top of the game using a compact HUD inspired by the information-dense style of emulator performance overlays.

## Features

### FPS Performance

- **FPS** — Current frames per second
- **AVG** — Rolling average FPS
- **1% LOW** — Low FPS percentile
- **0.1% LOW** — Very-low FPS percentile
- **FT** — Frame time in milliseconds
- **MIN** — Rolling minimum FPS
- **MAX** — Rolling maximum FPS
- **HZ** — Display refresh rate
- **RAM** — Memory currently used by the game process

### Device Information

- Device model
- Apple GPU family
- Battery percentage

### Live FPS Graph

A compact real-time FPS graph shows recent frame-rate behavior and helps identify:

- FPS drops
- Stuttering
- Sudden performance changes
- Frame-rate instability

The graph uses a rolling history and does not grow indefinitely.

## Overlay Design

The overlay uses a compact two-column layout near the upper-right side of the screen.

Example:

```text
                         FPS : 59.8     FT  : 16.72 ms
                         AVG : 59.5     MIN : 55.1
                         1% LOW : 52.4  MAX : 60.0
                         0.1% LOW:49.8  HZ  : 60
                                         RAM : 842 MB

                         iPhone 13 | GPU : Apple GPU | BAT : 78%

                         ───╱╲──╱╲────╱╲╱╲───
                         ─╱  ╲╱  ╲╱╲╱  ╲──
```

The HUD is:

- Compact
- Transparent
- White monospaced text
- Black shadow for readability
- Free of a solid background panel
- Designed for landscape games
- Automatically positioned using the safe area

## LiveContainer Support

FPSOverlay is designed to work with **LiveContainer's TweakLoader**.

The tweak:

- Loads as a `.dylib`
- Does not modify game files
- Does not access game save data
- Does not require network access
- Does not use an external server
- Waits for the application to become active
- Searches for the active game window
- Reattaches when a game replaces its window

Compatibility can vary between games.

## Installation

### Requirements

You need:

- iPhone or iPad
- LiveContainer
- LiveContainer TweakLoader
- Compatible ARM64 iOS device
- `FPSOverlay.dylib`

### 1. Download

Open the **Releases** section of this repository and download:

```text
FPSOverlay.dylib
```

### 2. Add to LiveContainer

1. Open LiveContainer.
2. Open the settings for the game.
3. Open its **Tweak Folder**.
4. Place `FPSOverlay.dylib` inside the folder.
5. Enable the tweak.
6. Completely close the game.
7. Launch the game again.

### 3. Signing

The GitHub Actions workflow automatically ad-hoc signs the release dylib with ZSign.

If your particular LiveContainer setup requires additional signing, use the signing method required by your setup.

> Ad-hoc signing is not an Apple Developer certificate or provisioning profile. LiveContainer's own loading/signing environment determines whether a particular dylib can be used on a device.

## GitHub Actions

The repository automatically builds, signs, verifies, and releases the tweak.

Workflow:

```text
Source Code
    ↓
Theos
    ↓
ARM64 FPSOverlay.dylib
    ↓
ZSign
    ↓
Ad-Hoc Signature
    ↓
Signature Verification
    ↓
GitHub Release
```

Workflow file:

```text
.github/workflows/build.yml
```

Workflow name:

```text
Build, Sign and Release FPSOverlay
```

To run it manually:

1. Open the repository on GitHub.
2. Open **Actions**.
3. Select **Build, Sign and Release FPSOverlay**.
4. Select **Run workflow**.
5. Wait for the workflow to complete.
6. Open the generated Release.
7. Download `FPSOverlay.dylib`.

## Manual Build

A manual build requires:

- macOS
- Theos
- Xcode command-line tools
- iOS SDK

Build:

```bash
make clean
make FINALPACKAGE=1
```

The ARM64 output is normally:

```text
.theos/obj/arm64/FPSOverlay.dylib
```

## Automatic Signing

GitHub Actions builds ZSign on the macOS runner and signs the generated dylib using ad-hoc signing:

```bash
zsign -a FPSOverlay.dylib
```

The signed file is then published as:

```text
FPSOverlay.dylib
```

in the GitHub Release.

## Performance Measurement

FPSOverlay uses:

```text
CADisplayLink
```

to measure frames observed by the display/update loop.

The displayed FPS should therefore be understood as a display-loop measurement.

Different games may use different rendering pipelines, frame-pacing systems, and synchronization methods. As a result, FPSOverlay's value may not always exactly match an internal FPS counter implemented by the game.

## FPS History

FPSOverlay keeps a rolling history of approximately:

```text
240 samples
```

Samples are collected approximately every:

```text
0.5 seconds
```

This provides approximately:

```text
2 minutes
```

of recent performance history.

The history is used for:

- AVG
- MIN
- MAX
- 1% LOW
- 0.1% LOW
- FPS graph

The history is stored using primitive numeric arrays to keep the tweak lightweight and avoid unnecessary object allocations.

## 1% LOW and 0.1% LOW

The low-percentile values are calculated from the recent rolling FPS history.

For example:

```text
FPS       : 60.0
AVG       : 59.5
1% LOW    : 48.2
0.1% LOW  : 42.1
```

These values help show performance drops that may not be obvious from average FPS alone.

## RAM

RAM represents memory currently resident for the game process.

Example:

```text
RAM : 842 MB
```

This is process memory and should not be interpreted as the total physical RAM installed in the device.

## Refresh Rate

The overlay displays the maximum refresh rate reported by the active display.

Example:

```text
HZ : 60
```

or:

```text
HZ : 120
```

Display refresh rate is not the same as guaranteed game FPS.

## GPU Information

FPSOverlay can display the device GPU family:

```text
GPU : Apple GPU
```

FPSOverlay intentionally does **not** display a fabricated GPU utilization percentage.

A normal iOS tweak does not have a reliable public API for obtaining per-game GPU utilization in the same way that desktop monitoring tools or an emulator can expose internal GPU counters.

## Emulator-Specific Metrics

FPSOverlay is inspired by the compact presentation of emulator performance overlays, but it is not an emulator.

The following emulator-specific metrics are intentionally excluded:

- EE
- GS
- VU
- VU0
- VU1
- VPS
- Emulation Speed
- VBlank
- Emulator VRAM
- Emulator draw counters
- Emulator-specific shader counters
- Emulator-specific hardware counters
- Emulator-specific performance percentages

These values are not applicable to a normal iOS game.

## Battery

FPSOverlay can display the current battery percentage:

```text
BAT : 78%
```

Battery monitoring is enabled after the application becomes active.

## Compatibility

FPSOverlay is intended for:

- ARM64 iOS devices
- LiveContainer
- LiveContainer TweakLoader
- Games that allow dynamic tweak loading

Compatibility can vary between games.

Some games may:

- Replace their main UIWindow
- Use unusual rendering pipelines
- Detect injected libraries
- Detect LiveContainer
- Have their own overlay systems
- Behave differently when a tweak is loaded

Successful operation in one game does not guarantee identical behavior in every game.

## Troubleshooting

### Overlay does not appear

Check:

1. FPSOverlay is enabled in LiveContainer.
2. `FPSOverlay.dylib` is inside the correct Tweak Folder.
3. The dylib is signed.
4. The game was completely closed before testing.
5. LiveContainer's TweakLoader is enabled.
6. The GitHub Actions build completed successfully.
7. You downloaded the `.dylib` from the GitHub Release.

### Game crashes when FPSOverlay is enabled

First test the game with the tweak disabled.

If:

```text
Tweak OFF → Game works
Tweak ON  → Game crashes
```

the game may have compatibility issues with the injected tweak or LiveContainer's tweak-loading environment.

Do not immediately delete the game's existing data.

Disable the tweak and confirm that the original game data still works.

### FPS disappears after startup

Some games replace their main window after:

- Splash screen
- Intro
- Loading screen
- Renderer initialization

FPSOverlay periodically searches for the active game window and attempts to reattach itself.

If the overlay still disappears, that game may use a rendering/window architecture requiring additional compatibility work.

### FPS differs from another FPS counter

Different FPS counters can measure different stages of rendering.

A game may use:

- Engine frame timing
- Render completion
- GPU completion
- Internal frame counters
- Presentation timing

Therefore two FPS counters can legitimately show different values.

## Privacy

FPSOverlay does not intentionally collect or transmit gameplay information.

It does not require:

- Analytics
- Telemetry servers
- Cloud services
- External databases
- Internet access
- Game save access
- Game file modification

Performance information is generated locally on the device.

## Project Structure

```text
FPSOverlay/
│
├── FPSOverlay.m
├── FPSOverlay.plist
├── Makefile
├── control
├── README.md
│
└── .github/
    └── workflows/
        └── build.yml
```

## Development

The main implementation is:

```text
FPSOverlay.m
```

Technologies used:

- Objective-C
- UIKit
- QuartzCore
- CADisplayLink
- Mach task information
- sysctl device information
- Theos
- GitHub Actions
- ZSign

The performance history uses primitive numeric storage for lightweight operation and compatibility with the manual-reference-counting build environment.

## Version

### V1.0 — First Public Release

This is the **first public release of FPSOverlay**.

Included:

- FPS counter
- Average FPS
- 1% LOW
- 0.1% LOW
- Frame time
- Minimum FPS
- Maximum FPS
- Display refresh rate
- Process RAM
- Battery percentage
- Device information
- Apple GPU family
- Live FPS graph
- Compact two-column HUD
- Upper-right placement
- Automatic window reattachment
- ARM64 build
- GitHub Actions build
- Automatic ad-hoc signing
- Automatic GitHub Release

Earlier development builds were internal and are not part of the public version history.

## Roadmap

Possible future improvements:

- Custom overlay positions
- Font-size controls
- Overlay opacity
- Graph scaling
- Color customization
- Per-game configuration
- Compact/full HUD modes
- Additional frame-pacing statistics
- More device information

Features will only be added when meaningful and reliable measurements are available on iOS.

## Disclaimer

FPSOverlay is an independent community project.

ARMSX2 is referenced only as inspiration for compact performance-overlay presentation.

FPSOverlay does not include ARMSX2 code, assets, emulator components, or proprietary game files.

Users are responsible for ensuring that they have permission to modify and run software on their own devices.

## License

Unless a separate license is added to this repository, the source code is provided for the project's intended use.

This repository does not grant permission to redistribute:

- Commercial games
- Game assets
- Copyrighted game files
- Proprietary binaries
- DRM-protected content

Only the FPSOverlay project source and binaries are covered by this repository.

## Credits

**FPSOverlay**

Independent iOS performance overlay project.

Built for experimentation with:

- iOS
- LiveContainer
- Objective-C
- Theos
- GitHub Actions
- ZSign
