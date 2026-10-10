#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
version=${1:-development}
app_path="$repo_dir/dist/Enco Free4 控制.app"
output_path="$repo_dir/dist/Enco-Free4-Control-$version.dmg"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/oppopods-dmg.XXXXXX")

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

if [[ ! -d "$app_path" ]]; then
    "$repo_dir/Scripts/build-app.sh" >&2
fi

ditto --norsrc --noextattr "$app_path" "$staging_dir/Enco Free4 控制.app"
codesign --verify --deep --strict "$staging_dir/Enco Free4 控制.app"
cp "$repo_dir/README.md" "$staging_dir/使用说明.md"
cp "$repo_dir/README.md" "$staging_dir/README.md"
cp "$repo_dir/docs/Feature_Status.md" "$staging_dir/功能状态.md"
cp "$repo_dir/THIRD_PARTY_NOTICES.md" "$repo_dir/LICENSE" "$staging_dir/"
mkdir -p "$staging_dir/docs"
for doc in Feature_Status Acceptance Protocol_Notes Prompt_Tones; do
    cp "$repo_dir/docs/$doc.md" "$staging_dir/docs/"
done
cp "$repo_dir/README.en.md" "$repo_dir/PRIVACY.md" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

rm -f "$output_path"
hdiutil create \
    -volname "Enco Free4 控制" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$output_path" >&2

hdiutil verify "$output_path" >&2
echo "$output_path"
