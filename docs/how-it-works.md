[English](how-it-works.md) | [Русский](how-it-works.ru.md) | [Español](how-it-works.es.md)

# How it works

## The overlay

- Each screen gets one transparent overlay window that lets clicks through. It's placed directly below the window
  that stays bright (`NSWindow.order(.below, relativeTo:)`), so everything above it is bright and everything below
  it gets the effect.
- With several displays each one has its own bright window: the active window on its display, and on every other
  display the top window mostly on it. Each overlay goes below its own display's window, and the window list is read
  once for all of them.
- In *All App Windows* mode the overlay has holes cut out for the app's other windows (a `CAShapeLayer` mask). Another
  app's window lying over one of those windows (between the app's windows) gets a hole too, for its whole visible
  part, so it doesn't sit like a dark patch on the bright windows.
- On a focus change the overlay isn't swapped or faded as a whole: only its mask animates, in the areas of the
  windows that brighten or dim. The rest of the screen keeps exactly the same dimming and blur throughout.
- Before the overlay is moved below a window, the app checks that the window is still on screen. Ordering below a
  window that's gone would put the overlay below every window.
- *Highlight Window Under Pointer* moves the overlay below the window under the pointer, so it and every window above
  it are bright; the reveal and the return use the same mask animation as a focus change. The 1.5 seconds count while
  the pointer stays over windows of the same app, since many apps draw one window as several. Once the effect is
  lowered, moving to another window applies after 0.3 s, so passing over gaps and background windows on the way
  doesn't count. When finding the window under the pointer, floating windows of other apps on other levels (such as a
  notch utility's mostly transparent panel) are ignored; only macOS's own UI, like the Dock and the menu bar, blocks
  it. The pointer is checked against the bright area and a cached list of window frames; the window list itself is
  read only when the pointer enters a dimmed area, a few times a second at most while it moves there, and when a delay
  ends.

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
- Screenshots (*Hide in Screenshots*): the overlay windows have `sharingType = .none`, so WindowServer leaves them out
  of captured images while they stay on screen. While the screenshot interface is up (⌘⇧4, ⌘⇧5), the `screencapture`
  process shows a `touchshield` window (layer 1498) over the screen, and the effect steps aside while it's there (see
  [performance.md](performance.md)).

## Effects

- Blur is an `NSVisualEffectView`; its radius is set on the internal `CABackdropLayer`. It's fully hidden when
  unused.
- Dim is a black layer; grain is a noise tile generated once and tiled.

## Haptic feedback

The taps drive the trackpad's Force Touch actuator directly, through private MultitouchSupport functions loaded
with `dlsym` (the way HapticKey does): unlike `NSHapticFeedbackManager`, they can vary in strength and work while
the system haptic feedback is off. The actuator is opened on the first tap and closed after 3 seconds without
taps. If the functions are ever missing, the app falls back to `NSHapticFeedbackManager`. Whether input comes from
a trackpad is read from the event itself (its touch subtype; for scrolling, its gesture phase).

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
