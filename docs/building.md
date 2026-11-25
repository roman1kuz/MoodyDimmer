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

## Releases

Releases are built by GitHub Actions (`.github/workflows/release.yml`) and signed with the same *Moody Dimmer Local
Signing* certificate, so Accessibility access survives updates.

1. Set the new version in `Resources/Info.plist` (`CFBundleShortVersionString`) and commit.
2. Tag the commit with an annotated tag and push it; the tag's message becomes the release notes:
   ```sh
   git tag -a v1.0.1 -m "Fixes …"
   git push origin v1.0.1
   ```
3. The workflow checks that the tag matches the version, builds and signs the DMG, checks the signature and publishes
   the release.
4. Point the Homebrew cask at the new release: `./scripts/update-tap.sh 1.0.1`. It needs `gh` signed in with push
   access to `roman1kuz/homebrew-tap`.

Running the workflow by hand (*Actions → Release → Run workflow*) builds the DMG without publishing anything and
attaches it to the run.

The workflow needs two repository secrets: `CERT_P12_BASE64`, the certificate exported with its private key as a .p12
file, base64-encoded, and `CERT_P12_PASSWORD`, the password of that file. Keep a copy of the .p12 somewhere safe: with
another certificate macOS treats the app as a different one, and every user has to grant Accessibility access again.

A fork that publishes its own builds uses its own certificate and its own name and icon (see
[TRADEMARK.md](../TRADEMARK.md)).
