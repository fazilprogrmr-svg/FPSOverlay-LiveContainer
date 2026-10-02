# FPSOverlay for LiveContainer

A lightweight FPS and frame-time overlay for iOS games running through LiveContainer.

## Download

### Latest Release

Download the latest **`FPSOverlay.dylib`** from the Releases section.

The release contains the ready-to-use `.dylib` file. No source build is required.

## Features

- Live FPS counter
- Frame time in milliseconds
- Text-only overlay
- No background box
- White text with subtle black shadow
- Lightweight
- ARM64
- Designed for LiveContainer TweakLoader

## Display

The overlay looks like:

FPS 32.7  
30.57 ms

## Installation

1. Download `FPSOverlay.dylib` from the latest Release.
2. Open LiveContainer.
3. Add the `.dylib` to your Tweak folder.
4. Enable `FPSOverlay.dylib`.
5. Assign the tweak folder to your game if using an app-specific folder.
6. Launch the game.

The FPS overlay should appear after the game starts.

## Build

This project uses Theos and GitHub Actions.

To create a new release:

1. Open the **Actions** tab.
2. Select **Build and Release FPSOverlay**.
3. Click **Run workflow**.
4. GitHub automatically builds the ARM64 `.dylib`.
5. A new GitHub Release is automatically created.
6. `FPSOverlay.dylib` is attached directly to the Release.

## V5.1 Changes

- Removed the black background.
- Added text-only FPS display.
- Added subtle text shadow.
- Uses the game's existing normal window.
- Removed deprecated `UIApplication.windows` API usage.
- Improved compatibility with modern iOS SDKs.

## Important

FPSOverlay is a display-only tweak.

It does not intentionally:

- Download game files
- Delete game files
- Modify game assets
- Modify save data
- Change network settings
- Unlock FPS
- Change graphics settings

## Credits

Built for use with:

- LiveContainer
- Theos

FPSOverlay is an independent project and is not affiliated with or endorsed by LiveContainer or Theos.
