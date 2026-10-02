# FPSOverlay for LiveContainer

A lightweight FPS and frame-time overlay tweak for iOS applications running through [LiveContainer](https://github.com/LiveContainer/LiveContainer).

The overlay displays the approximate display-link frame rate directly on top of the application.

## Features

- 📊 Real-time FPS display
- ⏱️ Approximate frame time in milliseconds
- 📱 Designed for iOS
- 🧩 Works as a `.dylib` tweak
- 📦 Designed for LiveContainer's TweakLoader
- 🎮 Useful for checking game performance
- 🔧 Lightweight and simple

Example:

```text
FPS 59.8
16.72 ms
```

## Requirements

- iPhone or iPad running a compatible iOS version
- LiveContainer
- TweakLoader enabled
- `FPSOverlay.dylib`

## Installation

### 1. Download FPSOverlay

Download the latest `FPSOverlay.dylib` from the Releases section of this repository.

### 2. Import into LiveContainer

Open LiveContainer and go to:

```text
Tweaks
```

Import:

```text
FPSOverlay.dylib
```

Enable the tweak.

### 3. Enable it for your game

You can use the global tweak folder or an app-specific tweak folder.

For game-specific use:

```text
LiveContainer
└── Tweaks
    └── Your Game
        └── FPSOverlay.dylib
```

### 4. Restart the game

Completely close the guest application and launch it again through LiveContainer.

The FPS overlay should appear in the top-left corner.

## How FPS Is Measured

FPSOverlay uses Apple's `CADisplayLink` to measure the rate of display-link callbacks received by the application.

The approximate FPS is calculated from:

```text
FPS = frames / elapsed time
```

Frame time is estimated using:

```text
Frame Time = 1000 / FPS
```

Examples:

```text
60 FPS ≈ 16.67 ms
30 FPS ≈ 33.33 ms
120 FPS ≈ 8.33 ms
```

## Important Limitations

FPSOverlay is a lightweight performance indicator, not a full graphics profiler.

The displayed value represents the display-link callback rate available to the application. It may not exactly equal the game's internal renderer or GPU frame rate.

Some games may:

- Use a custom rendering loop
- Use frame pacing
- Skip or duplicate frames
- Render internally at a different rate
- Use Metal or another rendering technology differently

Therefore, FPSOverlay should be considered an approximate FPS measurement.

## FPS Overlay vs FPS Unlocker

FPSOverlay does not unlock FPS.

It only displays the measured frame rate.

For example, if a game is limited to 30 FPS, FPSOverlay may show:

```text
FPS 30.0
33.33 ms
```

It will not automatically change the game to 60 FPS or 120 FPS.

## Troubleshooting

### FPSOverlay does not appear

Check the following:

1. Make sure `FPSOverlay.dylib` is enabled in LiveContainer.
2. Make sure TweakLoader is enabled.
3. Completely close the game.
4. Completely close LiveContainer.
5. Open LiveContainer again.
6. Launch the game again.

### FPSOverlay appears but FPS does not change

Some applications may not expose their rendering rate through `CADisplayLink` in a way that accurately represents their internal renderer.

### Game crashes after enabling FPSOverlay

Disable FPSOverlay and launch the game again.

If the problem disappears, report the issue with:

- iOS version
- Device model
- LiveContainer version
- Game name
- Game version
- Crash behavior

## Building

This project includes a GitHub Actions workflow.

```text
.github/
└── workflows/
    └── build.yml
```

The workflow builds the tweak and uploads:

```text
FPSOverlay.dylib
```

as a GitHub Actions artifact.

## Project Structure

```text
FPSOverlay-LiveContainer/
│
├── FPSOverlay.m
├── FPSOverlay.plist
├── Makefile
├── control
├── README.md
├── LICENSE
│
└── .github/
    └── workflows/
        └── build.yml
```

## Architecture

The current build targets:

```text
arm64
```

for compatible 64-bit ARM iOS devices.

## Contributing

Pull requests and improvements are welcome.

If you find a compatibility problem, please open an issue and provide:

- iOS version
- Device model
- LiveContainer version
- Game/application name
- Game/application version
- Description of the problem

## Disclaimer

This project is provided for educational and performance-monitoring purposes.

Use tweaks at your own risk. The author is not responsible for crashes, data loss, application instability, account restrictions, or other problems resulting from the use of this software.

## License

This project is licensed under the MIT License.

See [LICENSE](LICENSE) for details.

MIT License

Copyright (c) 2026 fazilprogrmr-svg

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
