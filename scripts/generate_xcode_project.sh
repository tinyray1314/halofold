#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
XCODEGEN="$PROJECT_DIR/.tools/xcodegen/xcodegen/bin/xcodegen"

if [[ ! -x "$XCODEGEN" ]]; then
  echo "缺少本地 XcodeGen。请从官方 GitHub Release 下载 2.46.0 到 .tools/xcodegen。" >&2
  exit 1
fi

cd "$PROJECT_DIR"
"$XCODEGEN" generate --spec project.yml
