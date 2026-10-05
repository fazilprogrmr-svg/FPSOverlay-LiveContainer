# FPSOverlay

> **A lightweight performance overlay for iOS games running through LiveContainer.**

A compact, Steam Deck / MangoHud-inspired HUD that displays real-time gaming performance information without covering the gameplay.

## Features

-  **FPS**
-  **CPU name & usage**
-  **GPU name**
-  **RAM usage / total RAM**
-  **Battery percentage**
-  **Frame Time**
-  **Screen HZ**
-  **Thermal State**
-  **Small live FPS graph**
-  **Transparent black HUD**
-  **LiveContainer compatible**
-  **Compact one-line design**
-  **Drag to reposition**
-  **Double-tap compact/full toggle**
-  **Triple-tap hide/show overlay**

##  Installation

1. Download **`FPSOverlay.dylib`** from **Releases**.
2. Open **LiveContainer** and create a folder named **`FPS`**.
3. Put **`FPSOverlay.dylib`** inside the **`FPS`** folder.
4. Open the **Settings** for the game you want to use FPSOverlay with.
5. Set the game's **Tweak Folder** to the **`FPS`** folder.
6. Make sure **Tweak Loading** is enabled for the game.
7. Launch your game. 

> **Note:** The `FPS` folder must be selected in the **Tweak Folder** setting for each game you want to use FPSOverlay with.

## Quick Controls

- Drag the overlay to reposition it anywhere on the screen.
- Double-tap the overlay to switch between full and compact mode.
- Triple-tap the overlay to hide or show the HUD.

## 📁 Folder Structure

```text
LiveContainer
└── FPS
    └── FPSOverlay.dylib
```

## 🎮 Per-Game Setup

```text
Game Settings
      ↓
Tweak Folder
      ↓
FPS
      ↓
FPSOverlay.dylib
```

##  Tested Games

- ✅ Amazing Spider-Man
- ✅ Bully
- ✅ Alien: Isolation
- ✅ Other LiveContainer games

⭐ **Like FPSOverlay? Drop a star on GitHub! It helps a lot.** ❤️


## 📊 HUD

```text
FPS 60 | CPU A15 Bionic 7%/6C | GPU Apple GPU | RAM 470M/3.6G | BATT 28% | FT 16.7ms | HZ 60 | Thermal State: Normal | ▂▃▅▇█
```
