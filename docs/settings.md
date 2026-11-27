[English](settings.md) | [Русский](settings.ru.md) | [Español](settings.es.md)

# Settings

Everything is in the menu behind the Moody Dimmer icon in the menu bar. Changes apply at once and are remembered. The
menu is available in English, Russian and Spanish. Checkmark items switch without closing the menu, so you can change
several in a row.

## Defaults

| Setting | Default |
|---|---|
| Effect on/off | on |
| Keep Bright | All App Windows |
| Hide While Dragging | on |
| Hide in Screenshots | on |
| Dim Menu Bar | on |
| Keep Tiled Windows Bright | on |
| Dim Active Display Only | off |
| Highlight Window Under Pointer | off |
| Trackpad Haptics | on |
| Dim / Blur / Grain | 50 % / off / off |
| Animation | 150 ms |
| Keyboard Shortcut | ⌃⌥⌘D |
| Shake Pointer to Toggle | on |
| Menu Bar Icon | Cascade, Match System theme |
| Language | Match System |
| Launch at Login | off |

## Moody Dimmer switch

The switch at the top of the menu turns the effect on or off. While it's off, the menu bar icon is dimmed and the
app does nothing except wait for the switch, the keyboard shortcut or a pointer shake to turn it back on.

## Grant Accessibility Access…

Shown only while Moody Dimmer has no Accessibility access. Opens *System Settings → Privacy & Security →
Accessibility*. Without access the effect still follows switches between apps, but not window changes within one
app (dialogs, a second window, windows being moved).

## Keep Bright

What stays bright while everything else is dimmed:

- **Active Window Only**: only the front window of the active app. Strict focus on one window.
- **All App Windows**: every visible window of the active app, so a dialog or panel doesn't dim the app's main window.
  Another app's window lying between the app's windows is shown bright as a whole, so it doesn't sit like a dark patch
  on them.

When the active app has no windows (you closed its last one, or an app quit and focus went nowhere), the top window
left on screen stays bright with the same rule, so the remaining windows don't sit in the dimmed background. On the
desktop (you clicked it, so Finder is active without windows) and on an empty screen there's no effect. Closing or
minimizing Finder's last window (a folder, the Trash) doesn't count as the desktop: the effect stays on the other
windows.

## Several displays

Each display works on its own:

- The display with the active window keeps it bright. Every other display keeps its own top window bright: the window
  mostly on that display that's in front of the others there. The same *Keep Bright* rule and *Keep Tiled Windows
  Bright* apply on each display.
- A window reaching onto another display from the active one stays bright there too.
- A display without windows gets no effect. A full screen video or app on one display removes the effect only there.
- *Highlight Window Under Pointer* works on every display, for the windows below that display's top window.
- *Hide While Dragging* removes the effect only from the display under the pointer.
- With *Dim Active Display Only* the other displays get no effect at all.

Clicking the desktop (Finder active without windows) removes the effect from every display, and so do Mission
Control, App Exposé and Show Desktop.

## Behavior

- **Hide While Dragging**: when something you drag (a file, a clip, text) leaves the windows of the app you drag it
  from, the effect fades out so you can see where to drop it. It comes back when you release the mouse button. With
  several displays only the one under the pointer loses the effect, and it follows the pointer to another display.
- **Hide in Screenshots**: screenshots, screen recordings and screen sharing don't show the effect, while it stays on
  your screen. How it behaves:
  - ⌘⇧3 (the whole screen at once): the effect stays on screen, and the screenshot is taken without it.
  - ⌘⇧4, ⌘⇧4 Space and ⌘⇧5: the effect steps aside while you pick what to capture, so you see what you'll get, and
    comes back when the capture is taken or cancelled.
  - Other screenshot apps (Shottr, Vorsaint and the like) with screen freezing on: the frozen picture is already
    without the effect, so you select on what you'll get.
  - The same apps without screen freezing: **the effect stays on screen while you select, but the screenshot is
    without it**, so what you see differs from what you get in brightness (the windows are the same). Moody Dimmer
    can't tell when another app starts selecting. To see the result while selecting, turn on screen freezing in the
    app's settings.
  - Screen recording and screen sharing go through the same capture, so others see your screen without the effect.
  - Apps capture the screen through macOS, which leaves the effect out; an app that captures it some other way would
    show it. Checked with the macOS screenshot tool, Shottr and Vorsaint.

  Turn it off when you want the effect in a screenshot, for example to show how it looks.
- **Dim Menu Bar**: the effect covers the menu bar too. The menu bar is translucent in macOS 26 and later, so with
  strong dimming it gets dark while its icons may stay dark. Turn this off to stop the effect at the bottom edge of
  the menu bar. With an auto-hiding menu bar the effect always covers the whole screen.
- **Keep Tiled Windows Bright**: windows laid out side by side with the active one (snapped to halves, thirds or
  quarters of the screen by macOS, Rectangle, Magnet and the like) stay bright with it, so switching between them
  doesn't flash. macOS doesn't tell which windows are tiled, so it's judged by their alignment: they don't overlap,
  touch each other along an edge, and each is snapped to the edges of the screen (without the menu bar and the Dock),
  in a corner or across its whole height or width. The layout doesn't have to fill the screen: three quarters with the
  fourth left empty count too. Windows that just stand next to each other don't count. A tiled window of another app that's resized on its own is picked up at the
  next click or window switch.
- **Dim Active Display Only**: with several displays, only the one with the active window gets the effect (the one
  holding most of the window); the others stay as they are, for reference material or a chat on a second display. The
  effect moves with the active window from display to display. Off by default: then each display works on its own,
  and its top window stays bright (the window mostly on that display that's in front of the others there), with the
  same Keep Bright rule; a display without windows gets no effect.
- **Highlight Window Under Pointer**: when the pointer rests on a dimmed window for 1.5 seconds, the effect moves
  below that window, so it and every window above it become visible; it doesn't become active. From then on, moving
  the pointer onto another window that isn't the active one moves the effect below that window, and moving it onto the
  active window, the desktop, the menu bar or the Dock brings the effect back. A window that's part of a layout (see
  *Keep Tiled Windows Bright*) is highlighted with all the windows of its layout. Only dimmed windows take part: not the
  desktop, the menu bar, the Dock or windows that are bright anyway. Off by default. While it's on, the app follows
  the pointer, at the same cost as *Shake Pointer to Toggle* (shared when both are on).
- **Trackpad Haptics**: soft taps of the Force Touch trackpad. While a slider is dragged, a tap at every 1 % step that
  grows with the value (none at 0, a slightly firmer one at the end); when shaking the pointer toggles the effect, a
  short buzz that swells when it comes on and fades when it goes off. Only for input from a trackpad: with a mouse
  there are none. It works even with *Force Click and haptic feedback* turned off in System Settings. On by default.

## Effect

Three sliders set the effects, and they combine: **Dim** (a black layer over the background), **Blur** (a blur of the
background) and **Grain** (static film grain). A slider at 0 turns its effect off.

## Sliders

Drag a slider, click anywhere on it, or scroll over it with a trackpad or mouse wheel. The current value is shown on
the right. The symbol inside the slider moves with the value.

| Slider | Range | How it maps to the effect |
|---|---|---|
| Dim | off–100 % | black layer opacity = x (linear; 100 % is fully black) |
| Blur | off–100 % | radius = 50 × x^1.6 pt: 10 % ≈ 1, 30 % ≈ 7, 50 % ≈ 17, 80 % ≈ 35, 100 % = 50 |
| Grain | off–100 % | static film grain, opacity = 0.5 × x^0.75 (low values are still visible) |
| Animation | instant–400 ms | how long focus changes and effect changes take; *instant* switches at once |

## Quick Toggle

Two ways to turn the effect on or off without opening the menu. Both work in any app and need no extra permission.

- **Keyboard Shortcut**: ⌃⌥⌘D by default. Click the item and press a new shortcut; it needs at least one of ⌘, ⌥ or
  ⌃. Esc cancels, Delete removes the shortcut. Letter keys are shown as in the Latin layout, whatever layout is
  active.
- **Shake Pointer to Toggle**: shake the pointer quickly back and forth in place, in any direction (left and right, up
  and down or diagonally), two or three fast back-and-forth moves. Quick strokes matter (about a tenth of a second
  each), not width: anything from a short wiggle to a swing of about a third of the screen works, and a slight arc is
  fine. One shake toggles once; to toggle again, hold the pointer still for a moment first. Slow back-and-forth moves,
  circling the pointer, a zigzag that travels across the screen, pointing with an overshoot and dragging don't trigger
  it. Turn it off if you don't use it: then the app stops receiving pointer moves altogether (unless *Highlight Window
  Under Pointer* is on).

## Menu Bar Icon

- **Style**: *Cascade* (a bright window in front of a dimmed one) or *Window* (a single window).
- **Theme**:
  - *Match System*: black in Light mode, white in Dark mode. Follows the system appearance, including Auto by time
    of day.
  - *Light*: always black, for a light menu bar.
  - *Dark*: always white, for a dark menu bar.

## Language

*Match System* picks the first of English, Russian or Spanish in your system's preferred languages, otherwise
English. You can also pick *English*, *Русский* or *Español*. The menu switches at once, without a relaunch.

## Launch at Login

Starts Moody Dimmer when you log in.

## Check for Updates…

Asks GitHub for the latest version, only when you choose this item: the app never checks in the background. While it
checks, the item shows a spinner and the menu stays open. If a newer version is out, the alert links to its release
page. If the app was installed with Homebrew, the alert also shows the upgrade command (`brew update && brew upgrade
moody-dimmer`) with a button to copy it. The app itself never downloads or installs anything.

## Quit

Quits Moody Dimmer.

## When the effect steps aside on its own

No setting needed for these:

- full screen Spaces (video, players, apps in full screen) and borderless windows covering the whole screen (games);
- Mission Control, App Exposé and Show Desktop;
- while dragging outside the source app (if *Hide While Dragging* is on);
- while you pick what to capture with ⌘⇧4 or ⌘⇧5 (if *Hide in Screenshots* is on).
