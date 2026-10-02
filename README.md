# FPSOverlay V7

Compact iOS game performance HUD for LiveContainer.

## Included metrics

- FPS
- AVG FPS
- 1% LOW
- 0.1% LOW
- Frame time
- Rolling MIN/MAX
- Display Hz
- Process RAM
- Battery
- Device
- GPU family
- Live FPS graph

The design is inspired by the compact information density of emulator performance overlays, but does not copy emulator-specific counters.

## Build

The GitHub Actions workflow builds:

`.theos/obj/arm64/FPSOverlay.dylib`

and publishes the raw `FPSOverlay.dylib` as a GitHub Release asset.

## LiveContainer

Download the release `.dylib`, sign it if required by your setup, then place it in the game's Tweak Folder.
