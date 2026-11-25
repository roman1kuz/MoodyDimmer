[English](building.md) | [Русский](building.ru.md) | [Español](building.es.md)

# Building

## Build and install

The Command Line Tools are enough to build. With Xcode installed, the app icon is compiled in the new Icon Composer
format.

```sh
./scripts/make-cert.sh             # once: local code signing certificate
./scripts/build-app.sh --install   # build, copy to /Applications and relaunch
```

Each build produces `build/MoodyDimmer-<version>.dmg` (the app plus an Applications shortcut). Without
`--install`, only the DMG is built. The `.app` is assembled in a temporary folder and removed afterwards, so macOS
sees only one Moody Dimmer, the one in /Applications.

## Code signing and Accessibility access

`scripts/make-cert.sh` creates a self-signed certificate, *Moody Dimmer Local Signing*, in the login keychain. The
build script signs with it, so the signature stays the same across builds and macOS keeps Accessibility access.

Without the certificate the app is ad-hoc signed, and access is reset after every rebuild: remove Moody Dimmer from
*System Settings → Privacy & Security → Accessibility* and grant access again.

On the first signing, macOS may ask to let `codesign` use the key. Choose *Always Allow* so it doesn't ask again;
until you answer, the build waits.

## App icon

The app icon (dark) is generated from code. After editing `scripts/make-icon.swift`, regenerate it:

```sh
swift scripts/make-icon.swift "$PWD"                                 # → Resources/AppIcon.icon and AppIcon.icns
swift scripts/make-icon.swift "$PWD" --preview "$PWD/Design/AppIcon"  # previews of every variant
```

The generator keeps several variants (cascade, veil, dimmer), each in a light and a dark theme. Their previews are in
`Design/AppIcon`.

The shipped icon, `Resources/AppIcon.icon`, follows the macOS 27 guidelines: square vector layers (the dimmed back
window and the bright front window) on a gradient fill, with no baked-in shadows, glows or texture. macOS adds Liquid
Glass and derives the clear and tinted looks. The build compiles it with Xcode's `actool`; without Xcode it uses
`AppIcon.icns` (the system rendering of the same icon).
