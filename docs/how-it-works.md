[English](how-it-works.md) | [Русский](how-it-works.ru.md) | [Español](how-it-works.es.md)

# How it works

## The overlay

- Each screen gets one transparent overlay window that lets clicks through. It's placed directly below the window
  that stays bright (`NSWindow.order(.below, relativeTo:)`), so everything above it is bright and everything below
  it gets the effect.
- In *All App Windows* mode the overlay has holes cut out for the app's other windows (a `CAShapeLayer` mask). Areas
  covered by other apps' windows are subtracted from the holes.
- On a focus change the overlay isn't swapped or faded as a whole: only its mask animates, in the areas of the
  windows that brighten or dim. The rest of the screen keeps exactly the same dimming and blur throughout.
- Before the overlay is moved below a window, the app checks that the window is still on screen. Ordering below a
  window that's gone would put the overlay below every window.

## Tracking focus

- Everything is event-driven: `NSWorkspace` notifications, an `AXObserver` on the active app, and WindowServer's
  window notifications. No polling timers. Details and measurements: [performance.md](performance.md).
- A window being closed is noticed through Accessibility right away, so the effect moves on during the window's
  close animation rather than after it.
- When the active app has no windows, the top window on screen stays bright; when a just-launched app shows its first
  window before it answers Accessibility, WindowServer's window events pick it up.

## Where the effect steps aside

- Full screen Spaces (video, players, apps in full screen): the overlay uses the `.fullScreenNone` collection
  behavior, so WindowServer itself keeps it out of full screen Spaces, even during the transition animation. On a
  Space change the app also checks each display's Space type once, so it doesn't reorder the overlay there. This uses
  private SkyLight functions loaded with `dlsym`, with an `AXFullScreen` fallback. Borderless windows covering the
  whole display (games) are detected by their size.
- Mission Control, App Exposé and Show Desktop: detected from the WindowManager window shown over the screen in these
  modes (see [performance.md](performance.md)).
- Dragging: when a drag leaves the source app's windows (*Hide While Dragging*).

## Effects

- Blur is an `NSVisualEffectView`; its radius is set on the internal `CABackdropLayer`. It's fully hidden when
  unused.
- Dim is a black layer; grain is a noise tile generated once and tiled.

## Troubleshooting

If the effect sometimes doesn't work, check the log:

```sh
log stream --debug --style compact --predicate 'subsystem == "io.github.roman1kuz.moodydimmer"'
```

The line `accessibility not trusted` means Accessibility access was reset (usually after a rebuild without the
signing certificate, see [building.md](building.md)).

## Limitations

- The corner radius of the holes is approximate (`FocusTracker.holeCornerRadius`).
- The blur radius is set through the internal `CABackdropLayer` of `NSVisualEffectView` (the `gaussianBlur` filter).
  This structure is undocumented. If a future macOS changes it, the app falls back on its own to setting blur
  strength through layer opacity.
- In *Active Window Only* mode, floating panels and menus on non-standard window levels may end up under the effect.
- Running alongside Monocle or HazeOver conflicts: both apps place their overlays under the same window.
