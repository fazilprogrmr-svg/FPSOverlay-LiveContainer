# FPSOverlay for LiveContainer

A lightweight Game Performance Monitor for iOS games running through LiveContainer.

## Features
- Live FPS and frame time
- Average, minimum and maximum FPS
- 1% low and 0.1% low FPS
- Guest-process RAM usage
- Battery percentage
- Automatic reattachment when a game changes windows
- Text-only HUD
- ARM64

## Example
```text
FPS  59.8   16.72 ms
AVG  59.5  MIN  55.1
MAX  60.0  1% LOW  52.4
0.1% LOW 49.8
RAM  842 MB  BAT  78%
```

## Download
Download the latest `FPSOverlay.dylib` directly from GitHub Releases.

## Installation
1. Download `FPSOverlay.dylib`.
2. Add it to the LiveContainer Tweak folder.
3. Enable it.
4. Assign the folder to the game.
5. Launch the game.

## Notes
FPS is estimated from `CADisplayLink`. RAM is the guest process resident memory. Battery uses Apple's public `UIDevice` battery API. GPU usage, CPU temperature, and internal renderer FPS are not guessed because iOS does not provide one reliable public API for them.

## Build
GitHub Actions → **Build and Release FPSOverlay** → **Run workflow**.

The release contains the actual `FPSOverlay.dylib` file.

## License
MIT. Independent project; not affiliated with LiveContainer or Theos.
