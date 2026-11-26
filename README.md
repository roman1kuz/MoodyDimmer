# Moody Dimmer

**English** · [Русский](README.ru.md) · [Español](README.es.md)

_**M**y **O**ccasionally **O**dd **D**immer **Y**ields **D**arkness, **I**f **M**acOS **M**ostly **E**xecutes **R**equests._

A macOS menu bar app that dims, blurs or adds film grain to everything except the active window.

- Dim, blur or both, with optional film grain, each with its own strength.
- Keeps either the active window or all of the active app's windows bright.
- Smooth transitions on focus changes; the background never flickers.
- Steps aside in full screen, Mission Control, Show Desktop and while dragging files to another app.
- Quick toggle with a keyboard shortcut (⌃⌥⌘D) or by shaking the pointer.
- Close to zero cost when idle: event-driven, no polling timers.
- English, Russian and Spanish.

## Install

Requires macOS 26 or later (developed and tested on macOS 27).

- **Homebrew:** `brew install --cask roman1kuz/tap/moody-dimmer`; to update, `brew upgrade moody-dimmer`.
- **Download:** the DMG from [Releases](https://github.com/roman1kuz/MoodyDimmer/releases/latest);
  drag the app to Applications.

Moody Dimmer isn't notarized by Apple (that takes a paid developer account), so macOS blocks its first launch, and the
first launch after each update. To open it, go to *System Settings → Privacy & Security* and click *Open Anyway*.
Accessibility access stays granted across updates.

### Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`). A build you make yourself opens without the warning.

```sh
git clone https://github.com/roman1kuz/MoodyDimmer.git && cd MoodyDimmer
./scripts/make-cert.sh             # once: local code signing certificate
./scripts/build-app.sh --install   # build, copy to /Applications and launch
```

The build also produces a DMG in `build/`. Details: [docs/building.md](docs/building.md).

## Permissions

- **Accessibility**: needed to follow windows within one app (dialogs, second windows, moving windows). Without it the
  effect only follows switches between apps. The menu shows *Grant Accessibility Access…* until it's granted.
- **Screen Recording**: not needed.

## Use

Click the icon in the menu bar to open the settings. Turn the effect on or off with the switch at the top of the
menu, with ⌃⌥⌘D, or by shaking the pointer quickly in place.

## Privacy

Moody Dimmer doesn't go online on its own: no telemetry, no analytics, no background update checks. The only request
is when you choose *Check for Updates…*: the app asks GitHub for the number of the latest version, and downloads
nothing. Accessibility access is used only to find the active window and where it is on screen.

## Documentation

- [Settings](docs/settings.md): every setting and what it does.
- [Building](docs/building.md): building, code signing, the app icon.
- [How it works](docs/how-it-works.md): the overlay, focus tracking, troubleshooting, limitations.
- [Performance and energy](docs/performance.md): what it costs and how that was measured.

## License

Copyright © 2026 roman1kuz. Moody Dimmer is free software under the [GNU General Public License v3.0](LICENSE): you
may use, study, change and share it, and any version you distribute must stay open under the same license. The name
"Moody Dimmer" and the app icon aren't covered by the license, see [TRADEMARK.md](TRADEMARK.md).

This is a personal project, provided as is, without any warranty. It relies on undocumented macOS internals, so a
future macOS update may break it (see [limitations](docs/how-it-works.md#limitations)).

---

Built with the help of [Claude](https://claude.ai) by Anthropic.
