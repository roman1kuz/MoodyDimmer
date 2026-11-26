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
| Dim Menu Bar | on |
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
- **All App Windows**: every visible window of the active app, so a dialog or panel doesn't dim the app's main
  window. Other apps' windows that lie on top of them stay dimmed.

When the active app has no windows (you closed its last one, or an app quit and focus went nowhere), the top window
left on screen stays bright with the same rule, so the remaining windows don't sit in the dimmed background. On the
desktop (Finder active without windows) and on an empty screen there's no effect.

## Behavior

- **Hide While Dragging**: when something you drag (a file, a clip, text) leaves the windows of the app you drag it
  from, the effect fades out so you can see where to drop it. It comes back when you release the mouse button.
- **Dim Menu Bar**: the effect covers the menu bar too. The menu bar is translucent in macOS 26 and later, so with
  strong dimming it gets dark while its icons may stay dark. Turn this off to stop the effect at the bottom edge of
  the menu bar. With an auto-hiding menu bar the effect always covers the whole screen.

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
- **Shake Pointer to Toggle**: shake the pointer in place, quickly and not too wide: about three quick left-right
  wiggles within a second, each a few centimeters at most. Wide sweeps, slow back-and-forth moves, vertical or
  diagonal moves, a zigzag that travels across the screen, pointing with an overshoot and dragging don't trigger it.
  Turn it off if you don't use it: then the app stops receiving pointer moves altogether.

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
- while dragging outside the source app (if *Hide While Dragging* is on).
