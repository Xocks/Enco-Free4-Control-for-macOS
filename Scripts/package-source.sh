#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
repo_dir=${script_dir:h}
version=${1:-0.1.0}
cd "$repo_dir"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "请先保存源码版本；归档仅包含 HEAD。" >&2
    exit 1
fi
mkdir -p dist
git archive --format=zip --prefix="Enco-Free4-Control-Source/" \
    -o "dist/Enco-Free4-Control-Source-$version.zip" HEAD
echo "$repo_dir/dist/Enco-Free4-Control-Source-$version.zip"
