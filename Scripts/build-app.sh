#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
app_dir="$repo_dir/dist/Enco Free4 控制.app"
contents_dir="$app_dir/Contents"

cd "$repo_dir"
swift build -c release -debug-info-format none

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$repo_dir/.build/release/OppoPodsMac" "$contents_dir/MacOS/OppoPodsMac"
cp "$repo_dir/AppBundle/Info.plist" "$contents_dir/Info.plist"
cp "$repo_dir/AppBundle/Assets/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$repo_dir/Resources/device_models.json" "$contents_dir/Resources/device_models.json"
cp "$repo_dir/Resources/eq_mode_names.json" "$contents_dir/Resources/eq_mode_names.json"
cp "$repo_dir/Resources/eq_mode_names.en.json" "$contents_dir/Resources/eq_mode_names.en.json"

cp "$repo_dir/LICENSE" "$contents_dir/Resources/LICENSE"
cp "$repo_dir/THIRD_PARTY_NOTICES.md" "$contents_dir/Resources/THIRD_PARTY_NOTICES.md"
mkdir -p "$contents_dir/Resources/Documentation/docs"
cp "$repo_dir/README.md" "$repo_dir/README.en.md" "$repo_dir/PRIVACY.md" "$repo_dir/THIRD_PARTY_NOTICES.md" "$contents_dir/Resources/Documentation/"
for doc in Feature_Status Acceptance Protocol_Notes Prompt_Tones; do
    cp "$repo_dir/docs/$doc.md" "$contents_dir/Resources/Documentation/docs/"
done
xattr -cr "$app_dir"
codesign --force --sign - \
    --entitlements "$repo_dir/AppBundle/OppoPodsMac.entitlements" \
    "$app_dir"

echo "$app_dir"
