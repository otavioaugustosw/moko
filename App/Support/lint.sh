#!/bin/zsh
# zsh lint.sh [--format] — strict SwiftLint pass; --format also reformats the views.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$project_dir"
lint_binary="$(command -v swiftlint || true)"
if [[ -z "$lint_binary" ]]; then
  brew_binary="$(command -v brew || true)"
  if [[ -z "$brew_binary" ]]; then
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [[ -x "$candidate" ]]; then brew_binary="$candidate"; break; fi
    done
  fi
  if [[ -n "$brew_binary" ]]; then
    lint_prefix="$("$brew_binary" --prefix swiftlint 2>/dev/null || true)"
    lint_binary="$lint_prefix/bin/swiftlint"
  fi
fi
if [[ -z "$lint_binary" || ! -x "$lint_binary" ]]; then
  print 'SwiftLint is not installed; skipping lint. Install it with: brew install swiftlint'; exit 0
fi
if (( $# > 1 )) || [[ ${1:-} != '' && ${1:-} != '--format' ]]; then
  print -u2 'usage: zsh lint.sh [--format]'; exit 2
fi
if [[ ${1:-} == '--format' ]]; then
  xcrun swift-format format --in-place --configuration .swift-format --recursive 'App/Sources/Views'
  view_files=("$project_dir/App/Sources/Views/"**/*.swift)
  export SCRIPT_INPUT_FILE_COUNT=${#view_files}
  for (( index = 1; index <= ${#view_files}; index++ )); do
    export "SCRIPT_INPUT_FILE_$((index - 1))=${view_files[$index]}"
  done
  "$lint_binary" lint --fix --quiet --no-cache --config .swiftlint-format.yml --use-script-input-files
fi
"$lint_binary" lint --strict --quiet --no-cache --config .swiftlint.yml
print "SwiftLint $($lint_binary version): strict pass completed."
