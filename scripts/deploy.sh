#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
args=()
case "${1:-}" in
  "") [[ $# -eq 0 ]] || exit 1 ;;
  --dry-run) [[ $# -eq 1 ]] || exit 1; args+=(--dry-run) ;;
  *) echo 'Использование: deploy.sh [--dry-run]' >&2; exit 1 ;;
esac
[[ -f site/index.html ]] || { echo 'Отсутствует site/index.html' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Рабочая копия содержит изменения' >&2; exit 1; }
rsync -avz --delete --chmod=D755,F644 "${args[@]}" -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' site/ devops:/var/www/devops-site/ || exit 1
[[ $# -eq 0 ]] || exit 0
curl --fail --silent --show-error --max-time 15 --cacert "$HOME/devops.crt" https://devops.local/ >/dev/null || exit 1
printf 'Доставлен коммит %s\n' "$(git rev-parse --short HEAD)"
