# FPSOverlay

A lightweight performance overlay tweak for iOS games running through LiveContainer.

## Features

- Real-time FPS
- CPU name and usage
- GPU name
- RAM usage / total RAM
- Battery percentage
- Frame time
- Screen refresh rate (HZ)
- Thermal State
- Small live FPS graph
- Compact one-line HUD
- Transparent black background
- Steam Deck / MangoHud-inspired design
- Designed for LiveContainer compatibility

## Example

`FPS 60 | CPU A15 Bionic 7%/6C | GPU Apple GPU | RAM 470M/3.6G | BATT 28% | FT 16.7ms | HZ 60 | Thermal State: Normal | ▂▃▅▇█`

## Installation

1. Build `FPSOverlay.dylib`.
2. Sign the dylib if required by your LiveContainer setup.
3. Place it in your LiveContainer Tweak folder.
4. Enable the tweak for the desired game.
5. Launch the game.

## Notes

The overlay only displays metrics that can be obtained from the device/runtime. It does not intentionally generate or estimate unsupported GPU usage or power-consumption values.

Compatibility can vary between games because LiveContainer injects the tweak into different applications.

## Build

The project can be built with Theos and packaged as an ARM64 `.dylib`.

## License

Use and modify this project at your own risk.
