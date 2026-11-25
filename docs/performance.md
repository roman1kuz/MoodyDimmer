[English](performance.md) | [Русский](performance.ru.md) | [Español](performance.es.md)

# Performance and energy

Moody Dimmer is meant to cost close to nothing while it runs. This note records how the app keeps its cost
low and what was measured. The app doesn't poll: everything reacts to events.

## Measurements

Measured on macOS 27.2 (Apple Silicon) with `top -stats cpu,idlew,power`, the same numbers Activity Monitor
shows. Samples were 5 s long, with the app idle in the background and the dim effect on. The figures vary from
sample to sample and between Macs, so they're approximate, not guarantees.

| State | CPU | Idle wakeups per 5 s | Energy impact |
|---|---|---|---|
| Effect on | ~0 % | ~1–3 | ~0 |
| Effect off | ~0 % | ~2 | ~0 |
| Switching windows by clicking every 0.4 s (dim + blur) | ~1 % | — | ~1 |
| Pointer moving all the time, 120 moves/s (effect on) | ~1.5 % | ~2 | ~1.5 |

The app has no timers of its own; the ~2 remaining wakeups are most likely AppKit housekeeping.
While the pointer moves, the app receives every mouse move for shake-to-toggle; it stops costing anything as soon
as the pointer stops, and turning shake-to-toggle off removes it entirely. The moves come from a listen-only
`CGEventTap`. The per-move analysis is a few comparisons; almost all of the cost is waking up to receive the event,
so it grows with the pointer's event rate (up to 120 moves/s on a ProMotion display).

For scale, in 3 s samples Finder had ~160 idle wakeups, Dock ~230 and WindowManager ~400. A typical browser
tab has an energy impact in the units or tens.

Physical memory footprint: ~15 MB (`footprint`).

## What is event-driven

Everything reacts to events and does nothing in between:

- Focus tracking: `NSWorkspace` notifications (app activation, termination, hiding, Space changes, wake) and an
  `AXObserver` on the active app (focused and main window changes, window created, destroyed, moved, resized).
  Bursts of events, such as dragging a window, are coalesced into one update per run loop pass.
- No active window (its last window was closed): the top window on screen stays bright. Other apps' windows can
  then change without any activation or AX event, so WindowServer's window shown / destroyed events (`1325`/`1326`,
  see below) trigger the update. The same happens while a just-launched app has no window yet: its first window
  can appear before the app answers AX, so no AX event announces it. Otherwise these events are ignored, except
  that the bright window being destroyed triggers an update at once.
- Short one-off rechecks (0.12 s and 0.4 s) follow some events, because WindowServer raises windows a little
  later than the events arrive. They run only after an event, never in the background.
- Mouse clicks and drags (Hide While Dragging) use global event monitors, the shake gesture a listen-only event
  tap. Each mouse event costs a couple of comparisons.
- The keyboard shortcut uses the Carbon hotkey API: the system calls the app only when the keys are pressed.
- The overlay is static Core Animation layers composited by WindowServer. The grain texture is generated once.
  Nothing animates while idle.
- The switch animation in the menu uses a timer only for its 0.2 s.

## Mission Control, App Exposé, Show Desktop

The effect is removed in these modes. macOS 27 has no public notification for them. These were checked:

- The Dock's Exposé AX notifications (`AXExposeShowAllWindows`, `AXExposeShowFrontWindows`,
  `AXExposeShowDesktop`, `AXExposeExit`). The subscription succeeds, but nothing arrives: the Dock no longer
  draws these modes.
- WindowManager, which draws them now, rejects AX notifications (`kAXErrorNotificationUnsupported`), including
  standard ones such as window created.
- No `NSWorkspace` or distributed notification is posted.
- The overlay window's occlusion state doesn't change.

What can be seen is a WindowManager window over the whole screen: `ExposeShieldWindow` (layer 19) in Mission
Control and App Exposé, `ShowDesktopOverlay` (layer 18) in Show Desktop. The titles of other apps' windows need
Screen Recording access, so the window is matched by owner, layer and full screen size.

To learn when that window appears without polling, `SystemModeWatcher` uses WindowServer's own notifications
(SkyLight, private API, loaded with `dlsym`). Registering for every event type from 0 to 2000 and opening the
modes showed that WindowServer is silent at idle and posts:

- `1325` when a window becomes visible, with the window number in the payload (`[UInt32 flags, 0, window]`).
  It fires for the shield windows when a mode opens, and occasionally for other apps' windows.
- `1326` when a window is destroyed (the shield, when the mode closes). A window that's only ordered out or
  minimized posts nothing.
- App switches post neither.

So the watcher registers for `1325` and `1326` only. On `1325` it looks up that one window and remembers it if
it's a shield; on `1326` it forgets it. While a mode is up, a mouse click rechecks that the shield is still on
screen, in case an event was missed.

If `SLSRegisterNotifyProc` disappears in a future macOS, the watcher falls back to polling: it checks
the on-screen window numbers 5 times a second (`CGWindowListCreate`, ~70 µs a call) and fetches descriptions
only when that set changes. That costs ~0.2–0.4 % CPU and ~14 wakeups per 5 s while the effect is on.

## What costs the most

Blur. WindowServer composites it on the GPU and recomputes it when the content underneath changes. Dim and grain
are static layers and cost almost nothing.

## How to measure

```sh
P=$(pgrep -x MoodyDimmer)
top -l 6 -s 5 -pid $P -stats pid,command,cpu,idlew,power   # CPU, idle wakeups, energy impact
footprint $P | grep phys_footprint                          # memory
sample $P 5                                                 # where the time goes
```
