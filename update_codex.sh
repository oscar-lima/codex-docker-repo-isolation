#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

echo "The following commands will be run:"
echo "  npm install -g @openai/codex"
printf '  %q\n' "${project_dir}/install.sh"
printf 'Continue? [y/N] '
read -r response

case "${response}" in
    y|Y|yes|YES|Yes)
        ;;
    *)
        echo "Aborted."
        exit 0
        ;;
esac

npm install -g @openai/codex
"${project_dir}/install.sh"
