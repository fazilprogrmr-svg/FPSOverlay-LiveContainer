# FPSOverlay for LiveContainer

A lightweight in-game FPS and frame-time overlay for iOS games running through **LiveContainer**.

FPSOverlay is packaged as a `.dylib` tweak and loaded using LiveContainer's TweakLoader.

## Features

- 📊 Live FPS counter
- ⏱️ Frame time in milliseconds
- 🪶 Lightweight and simple
- 👻 No background box — text only
- 👤 White text with a subtle black shadow for readability
- 📱 Designed for ARM64 iPhones
- 🎮 Intended for games running inside LiveContainer
- 🔌 Uses `CADisplayLink` for frame timing
- 🚫 Does not download or modify game assets

## Screenshot

The overlay displays information similar to:

```text
FPS 32.7
30.57 ms
```

## Requirements

- iPhone/iPad with ARM64 support
- iOS 16 or later
- [LiveContainer](https://github.com/LiveContainer/LiveContainer)
- LiveContainer TweakLoader
- A way to install/load `.dylib` tweaks through LiveContainer

## Installation

### 1. Build the tweak

Download the latest GitHub Actions artifact:

**`FPSOverlay-V5-LiveContainer`**

Inside the artifact you will find:

```text
FPSOverlay.dylib
```

### 2. Add the tweak to LiveContainer

Open LiveContainer and add `FPSOverlay.dylib` to your tweak folder.

You can use either:

- The global **Tweaks** folder, or
- An app-specific tweak folder

For an app-specific setup, assign the folder to the game using the game's **Tweak Folder** setting.

### 3. Enable the tweak

Make sure:

```text
FPSOverlay.dylib → ON
```

Launch the game through LiveContainer.

The FPS counter should appear after the game finishes launching.

## Building from Source

This project uses **Theos** and GitHub Actions.

The repository contains:

```text
FPSOverlay.m
FPSOverlay.plist
Makefile
control
README.md
.github/
└── workflows/
    └── build.yml
```

The GitHub Actions workflow automatically:

1. Checks out the repository.
2. Installs Theos.
3. Builds the tweak for ARM64.
4. Verifies the generated Mach-O dylib.
5. Packages `FPSOverlay.dylib`.
6. Uploads the finished dylib as a GitHub Actions artifact.

### Manual build

If Theos is already installed:

```bash
make clean
make FINALPACKAGE=1
```

The resulting ARM64 dylib is generated under:

```text
.theos/obj/arm64/FPSOverlay.dylib
```

## How It Works

FPSOverlay creates a small text label inside the game's existing normal `UIWindow`.

It uses:

```objc
CADisplayLink
```

to measure frame presentation timing.

The overlay calculates:

```text
FPS = frames / elapsed time
```

and:

```text
Frame Time = 1000 / FPS
```

The displayed result is updated approximately twice per second to keep the overlay lightweight.

## V5 Changes

### V5

- Removed the semi-transparent black FPS background.
- Added white text with a subtle black shadow.
- Displays FPS and frame time.
- Uses the game's existing window instead of creating a separate alert-level window.
- Added a delayed startup so the game has time to initialize its UI.
- Added retry logic if the game window is not immediately available.

## Important Notes

FPSOverlay is a display-only tweak.

It does **not** intentionally:

- Download game files
- Delete game files
- Modify game assets
- Modify save data
- Change network settings
- Unlock FPS
- Change the game's graphics settings

If a game starts downloading its resources after enabling the tweak, that behavior should be investigated separately from the FPS calculation.

## Troubleshooting

### FPS counter does not appear

Check:

1. `FPSOverlay.dylib` is enabled.
2. The tweak is assigned to the correct game.
3. The game is launched through LiveContainer.
4. LiveContainer successfully signs/loads the tweak.
5. Restart the game after changing the tweak.

### Game behaves differently with the tweak enabled

Disable the tweak and test again.

If the game works normally with the tweak disabled but behaves differently when enabled, collect the LiveContainer error/log information before rebuilding the tweak.

## Project Structure

```text
FPSOverlay-LiveContainer/
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

## License

This project is provided for educational and personal-use purposes.

Use it only with applications and games you are authorized to modify or run with tweaks.

## Credits

Built for use with:

- [LiveContainer](https://github.com/LiveContainer/LiveContainer)
- [Theos](https://theos.dev/)

FPSOverlay is an independent project and is not affiliated with or endorsed by the LiveContainer or Theos projects.
