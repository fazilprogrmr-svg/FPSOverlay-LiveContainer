# FPSOverlay

A lightweight iOS game performance overlay for games running through LiveContainer.

Displays real-time FPS, CPU, GPU, RAM, battery, frame time, refresh rate, thermal state and a live FPS graph.

## Installation

1. Download `FPSOverlay.dylib` from **Releases**.
2. Open **LiveContainer**.
3. Create a folder named `FPS`.
4. Put `FPSOverlay.dylib` inside the `FPS` folder.
5. Open the settings for your game.
6. Set **Tweak Folder** to `FPS`.
7. Enable **Tweak Loading**.
8. Launch the game.

> The `FPS` folder must be selected separately for each game.

## How to Use

### Move the Overlay

**Drag** the HUD to move it anywhere on the screen.

### Compact / Full

**Double-tap** the HUD to switch between compact and full display.

### Hide / Show

**Triple-tap** to hide the HUD.

**Triple-tap again** to show it.

### Change Theme

**Long-press** the HUD to cycle through the available themes.

Themes:

- iPhone Liquid Glass
- PlayStation
- Xbox
- Windows Fluent
- Steam Deck
- Cyber Neon
- ROG Gaming
- Minimal
- MangoHUD
- Nintendo

### Change Layout

**Two-finger tap** to switch between:

- Horizontal
- Vertical

### Change Display Mode

**Two-finger double-tap** to cycle through:

- Full Performance
- Text Only
- FPS Only

### Game Icon

The HUD can display the current game's icon automatically.

## Performance Information

- FPS
- CPU usage
- CPU/device name
- GPU name
- RAM usage
- Battery
- Frame Time
- Refresh Rate
- Thermal State
- Live FPS graph

FPS and Frame Time are measured from actual Metal presentation events.

## Folder Structure

```text
LiveContainer
└── FPS
    └── FPSOverlay.dylib
