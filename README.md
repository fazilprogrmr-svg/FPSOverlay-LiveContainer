# FPSOverlay V7

A compact **iOS game performance overlay** designed for games running through **LiveContainer**.

The project is inspired by the compact, information-dense style of emulator performance HUDs such as ARMSX2, while using only metrics that are practical to display from an iOS tweak.

> **Important:** FPSOverlay is an independent project and is not affiliated with, endorsed by, or copied from ARMSX2.

---

## Features

### Performance

- **FPS** — current measured frames per second
- **AVG** — rolling average FPS
- **1% LOW** — low-end FPS percentile
- **0.1% LOW** — very-low FPS percentile
- **FT** — current frame time in milliseconds
- **MIN** — rolling minimum FPS
- **MAX** — rolling maximum FPS
- **HZ** — display refresh rate
- **RAM** — memory currently used by the game process

### Device information

- Device model / identifier
- Apple GPU family
- Battery percentage

### Live graph

V7 includes a compact live FPS graph showing recent frame-rate behavior.

The graph keeps a rolling history instead of growing indefinitely.

### LiveContainer compatibility

V7 is designed for dynamic loading through LiveContainer's TweakLoader.

The overlay:

- waits until the application is active before creating its UI
- does not access game data files
- does not create or modify game save files
- does not require network access
- periodically checks for the active game window
- automatically reattaches when a game replaces its `UIWindow`

This window reattachment is useful for games that change their rendering/UI window after startup.

---

## Overlay layout

The V7 layout uses a compact upper-right HUD with two information columns.

Example:

```text
                         FPS : 59.8     FT : 16.72 ms
                         AVG : 59.5     MIN:  55.1
                         1% LOW: 52.4   MAX:  60.0
                         0.1% LOW:49.8  HZ :  60
                         RAM : 842 MB

                         iPhone 13 | GPU : Apple GPU | BAT : 78%

                         ───╱╲──╱╲────╲╱╲───
                         ─╱  ╲╱  ╲╱╲╱  ╲──
```

The overlay intentionally has:

- no solid background panel
- white monospaced text
- black text shadow for readability
- compact spacing
- right-side placement
- automatic positioning through safe-area constraints

---

## Metrics that are intentionally NOT included

Some values visible in emulator overlays cannot be obtained reliably from a normal iOS game tweak.

V7 therefore does **not** fake or invent these values.

Examples include:

- EE utilization
- GS utilization
- VU utilization
- emulator VBlank timing
- emulator VPS
- emulation speed percentage
- emulator VRAM counters
- emulator draw-call counters
- emulator hardware performance counters
- GPU utilization percentage when a reliable public API is unavailable
- shader compilation counters when they are not exposed by the game/runtime

The project reports real available information instead of displaying made-up numbers.

---

# Project structure

```text
FPSOverlay-V7/
├── FPSOverlay.m
├── FPSOverlay.plist
├── Makefile
├── control
├── README.md
└── .github/
    └── workflows/
        └── build.yml
```

---

# Requirements

## Build

The GitHub Actions workflow uses:

- macOS runner
- Theos
- Clang
- ARM64 target
- iOS SDK

The target architecture is:

```text
arm64
```

## Runtime

You need:

- an iOS device
- LiveContainer
- LiveContainer TweakLoader
- a signed `FPSOverlay.dylib`

---

# Building with GitHub Actions

The repository contains:

```text
.github/workflows/build.yml
```

The workflow is manually triggered.

### Steps

1. Push the project files to your GitHub repository.
2. Open the repository.
3. Open **Actions**.
4. Select **Build and Release FPSOverlay**.
5. Click **Run workflow**.
6. Wait for the build to finish.
7. Open the generated GitHub Release.
8. Download:

```text
FPSOverlay.dylib
```

The workflow verifies the generated ARM64 dylib before creating the release.

---

# Installing in LiveContainer

After downloading the release:

1. Obtain `FPSOverlay.dylib`.
2. Sign the dylib using the signing method required by your LiveContainer setup.
3. Open LiveContainer.
4. Open the target game's settings.
5. Open its **Tweak Folder**.
6. Place:

```text
FPSOverlay.dylib
```

inside that folder.
7. Enable the tweak.
8. Launch the game.

The exact folder/file-transfer method can vary between LiveContainer versions.

---

# Signing

A dylib normally needs to be signed appropriately before LiveContainer can load it.

For example, if you are using `zsign` on Windows:

```text
zsign.exe -a FPSOverlay.dylib
```

Then verify:

```text
zsign.exe FPSOverlay.dylib
```

The exact signing requirements depend on the way LiveContainer and the device are configured.

---

# Troubleshooting

## Overlay does not appear

Check:

- The dylib is inside the correct Tweak Folder.
- The tweak is enabled.
- The dylib is signed.
- The game was completely closed and relaunched.
- LiveContainer's TweakLoader is enabled.
- The GitHub Actions build completed successfully.

---

## FPS appears and then disappears

V7 periodically searches for the active normal-level game window and reattaches the overlay.

This is specifically intended for games that replace their window during startup or after an intro.

---

## Game asks to download its data again

If a game works normally with the tweak disabled but requests its data again when the tweak is enabled, do **not** immediately delete the game's existing data.

That behavior can indicate a compatibility issue between the game, LiveContainer, TweakLoader, and injected dylib.

Test:

1. Disable FPSOverlay.
2. Confirm the original game data still works.
3. Enable FPSOverlay again.
4. Compare the behavior.

---

## FPS number looks wrong

FPSOverlay measures frames observed by `CADisplayLink`.

It is therefore a display/update-loop measurement and should not be interpreted as an internal engine FPS counter for every game.

Games with unusual rendering pipelines may report values differently.

---

# Performance history

V7 keeps a rolling history of recent samples.

Samples are collected approximately every **0.5 seconds**.

The history is limited to approximately **2 minutes**.

This keeps:

- memory usage low
- the graph responsive
- AVG relevant to recent gameplay
- 1% LOW and 0.1% LOW responsive to recent performance

---

# Privacy

FPSOverlay does not intentionally collect or transmit gameplay data.

It does not require:

- internet access
- an external server
- analytics
- telemetry
- game save access

The overlay only reads runtime information needed to display its performance statistics.

---

# Development

Main source:

```text
FPSOverlay.m
```

The overlay uses:

- UIKit
- QuartzCore
- Mach task information
- system device information

No third-party runtime library is required by the tweak.

---

# Version history

## V7.0

Major performance HUD redesign.

Added:

- compact two-column layout
- FPS
- AVG FPS
- 1% LOW
- 0.1% LOW
- frame time
- MIN / MAX
- display HZ
- RAM
- battery
- device information
- Apple GPU family
- live FPS graph
- rolling performance history
- improved window reattachment
- delayed UI initialization for better game compatibility
- automatic GitHub Release publishing

## V6

Added:

- FPS statistics
- frame time
- average/minimum/maximum
- 1% LOW
- 0.1% LOW
- RAM
- battery
- window reattachment

## V5

Introduced the clean text-only overlay design.

## V1–V4

Initial FPS measurement and LiveContainer compatibility development.

---

Use tweaks and modified software only with software and devices you are permitted to modify.

---

# License

This repository does not grant permission to redistribute proprietary game files, assets, or copyrighted content.

FPSOverlay source code is provided for the project author's intended use unless a separate license is added to this repository.
