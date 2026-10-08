<div align="center">

# FPSOverlay

### iOS Game Performance Overlay for LiveContainer

Real-time performance telemetry for iOS gaming — designed for a clean, compact gaming HUD.

<p>
  <a href="https://github.com/fazilprogrmr-svg/FPSOverlay/releases">Download</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/fazilprogrmr-svg/FPSOverlay/issues">Issues</a>
  &nbsp;·&nbsp;
  <a href="https://fazilprogrmr-svg.github.io/FPSOverlay/">Website</a>
</p>

</div>

---

<div align="center">

**FPS** · **CPU** · **GPU** · **RAM** · **Battery** · **Frame Time** · **Hz** · **Thermal**

</div>

> FPSOverlay displays real-time FPS, CPU, GPU, RAM, battery, frame time, refresh rate, thermal state and a live FPS graph. fileciteturn1file0L3-L5

---

## Preview

<div align="center">

<img src="docs/assets/game-1.jpeg" width="900" alt="FPSOverlay gameplay preview">

</div>

<div align="center">

<img src="docs/assets/game-2.jpeg" width="900" alt="FPSOverlay gameplay preview">

</div>

---

## Installation

### 01 — Download

Download `FPSOverlay.dylib` from **Releases**.

### 02 — Create the tweak folder

Open **LiveContainer** and create:

```text
FPS
```

### 03 — Add FPSOverlay

Place:

```text
FPSOverlay.dylib
```

inside the `FPS` folder.

### 04 — Enable the tweak

Open your game's settings:

```text
Tweak Folder → FPS
Tweak Loading → ON
```

### 05 — Launch

Start the game.

> The `FPS` folder must be selected separately for each game.

---

## Touch Controls

| Gesture | Action | Result |
|---|---|---|
| **1 Finger — Drag** | Move HUD | Moves the overlay anywhere on screen |
| **1 Finger — Double Tap** | Compact / Full | Switches between compact and full HUD |
| **1 Finger — Triple Tap** | Hide / Show | Hides or shows the overlay |
| **1 Finger — Long Press** | Change Theme | Cycles through available themes |
| **2 Fingers — Single Tap** | Change Layout | Horizontal ↔ Vertical |
| **2 Fingers — Double Tap** | Change Display Mode | Full Performance → Text Only → FPS Only |

---

## Display Modes

| Mode | Shows |
|---|---|
| **Full Performance** | Complete performance HUD |
| **Text Only** | Performance information without the glass/decorative panel |
| **FPS Only** | FPS number only |

## Layouts

| Layout | Description |
|---|---|
| **Horizontal** | Performance information arranged left-to-right |
| **Vertical** | Performance information arranged top-to-bottom |

---

## HUD Controls

### Move

**Drag** the HUD to move it anywhere on the screen.

### Compact / Full

**Double-tap** the HUD to switch between compact and full display.

### Hide / Show

**Triple-tap** to hide the HUD.

**Triple-tap again** to show it.

### Theme

**Long-press** the HUD to cycle through the available themes.

### Layout

**Two-finger tap** switches between:

- Horizontal
- Vertical

### Display Mode

**Two-finger double-tap** cycles through:

- Full Performance
- Text Only
- FPS Only

---

## Themes

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

---

## Performance Information

<div align="center">

| Metric | Live Data |
|---|---|
| FPS | Real-time FPS |
| CPU | Usage + device name |
| GPU | GPU name |
| RAM | Current memory usage |
| Battery | Battery percentage |
| Frame Time | Frame presentation timing |
| Refresh Rate | Current display Hz |
| Thermal | Current thermal state |
| FPS Graph | Live frame-rate graph |

</div>

FPS and Frame Time are measured from actual Metal presentation events.

---

## Game Icon

The HUD can display the current game's icon automatically.

---

## Folder Structure

```text
LiveContainer
└── FPS
    └── FPSOverlay.dylib
```

---

## Website

The project has a dedicated interactive landing page with:

- Landscape gaming presentation
- Real FPSOverlay gameplay screenshots
- Automatic screenshot slider
- Touch-friendly mobile layout
- Mouse-follow ambient glow on desktop
- Responsive design

**Website:**  
https://fazilprogrmr-svg.github.io/FPSOverlay/

---

<div align="center">

### Built for iOS gaming with LiveContainer

**FPSOverlay**

</div>
