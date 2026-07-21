#!/bin/zsh
# Stop when compilation or a resource copy fails.
set -euo pipefail
# Resolve the project root from this script's stable location.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
# Keep the generated bundle inside the repository's ignored build folder.
app_root="$project_root/build/Teyvat Virtuoso.app"
# Recreate only the generated app bundle for a clean build.
rm -rf "$app_root"
# Create the standard Finder-recognised bundle layout.
mkdir -p "$app_root/Contents/MacOS" "$app_root/Contents/Resources"
# Compile the native AppKit selector and keyboard performer.
swiftc "$project_root/player/MidiEngine.swift" "$project_root/player/UserScoreStore.swift" "$project_root/player/CommunityLibrary.swift" "$project_root/player/GenshinLyrePlayerApp.swift" -o "$app_root/Contents/MacOS/TeyvatVirtuoso" -framework AppKit -framework CoreGraphics
# Copy the regular macOS application metadata.
cp "$project_root/player/Info.plist" "$app_root/Contents/Info.plist"
# Copy the compiled multi-resolution Finder and Dock icon.
cp "$project_root/assets/AppIcon.icns" "$app_root/Contents/Resources/AppIcon.icns"
# Bundle the open-source-safe public score manifest.
cp "$project_root/scores/public-domain/library.json" "$app_root/Contents/Resources/library.json"
# Bundle only community metadata and remote identifiers, never community note data.
cp "$project_root/scores/community/catalog.json" "$app_root/Contents/Resources/community-catalog.json"
# Bundle every score listed by that manifest.
cp "$project_root/scores/public-domain/"*.json "$app_root/Contents/Resources/"
# Ad-hoc sign the complete bundle under one stable identifier so Accessibility approval survives rebuilds.
codesign --force --deep --sign - --identifier "com.philippsyrov.teyvat-virtuoso" "$app_root"
# Print the exact app path Finder can open.
echo "Built $app_root"
