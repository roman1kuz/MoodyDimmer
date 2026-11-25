#!/bin/zsh
# Points the Homebrew cask in roman1kuz/homebrew-tap at a published release.
#
#   ./scripts/update-tap.sh 1.0.1
#
# Downloads the release DMG, computes its checksum, writes Casks/moody-dimmer.rb from packaging/moody-dimmer.rb
# and pushes it to the tap. Run it after the release workflow has published the GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: update-tap.sh <version>, e.g. 1.0.1}"
REPO="roman1kuz/MoodyDimmer"
TAP="roman1kuz/homebrew-tap"
DMG="MoodyDimmer-$VERSION.dmg"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gh release download "v$VERSION" --repo "$REPO" --pattern "$DMG" --dir "$TMP"
SHA256="$(shasum -a 256 "$TMP/$DMG" | awk '{print $1}')"
echo "$DMG: $SHA256"

gh repo clone "$TAP" "$TMP/tap" -- --quiet
mkdir -p "$TMP/tap/Casks"
# The template's first line is a note for this repository, not for the tap.
sed -e '1d' -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA256/" packaging/moody-dimmer.rb > "$TMP/tap/Casks/moody-dimmer.rb"

cd "$TMP/tap"
if git diff --quiet -- Casks/moody-dimmer.rb && git ls-files --error-unmatch Casks/moody-dimmer.rb >/dev/null 2>&1; then
    echo "The cask is already at $VERSION."
    exit 0
fi
git add Casks/moody-dimmer.rb
git commit -q -m "moody-dimmer $VERSION"
git push -q
echo "Pushed moody-dimmer $VERSION to $TAP."
