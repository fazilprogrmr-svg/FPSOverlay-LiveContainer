# FPSOverlay for LiveContainer

A minimal iOS tweak that displays the current CADisplayLink frame rate and approximate frame time.

Example:

FPS 59.8
16.72 ms

## Build without a Mac

1. Create a GitHub repository.
2. Upload all files from this project.
3. Open **Actions**.
4. Run **Build FPSOverlay**.
5. Download the `FPSOverlay-LiveContainer` artifact.
6. If the artifact contains `FPSOverlay.dylib`, import that file into LiveContainer's Tweaks.
7. Assign the tweak folder to your game.

## LiveContainer

LiveContainer supports `.dylib` tweaks and can resign them automatically. Put the tweak in an app-specific tweak folder if you only want it active for one game.

## Notes

This measures the display-link callback rate seen by the app. It is a simple performance indicator, not a GPU profiler.

If a particular game does not create/use CADisplayLink in the expected way, the overlay may not accurately represent its internal renderer FPS.
