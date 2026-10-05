#!/usr/bin/env bash
# Picks the best locale for an Accept-Language header.
set -euo pipefail

declare -A LOCALES=(
  ["en"]="English"
  ["pt-BR"]="Português"
)

find_locale() {
  local code="${1,,}"
  for known in "${!LOCALES[@]}"; do
    if [[ "${known,,}" == "$code" ]]; then
      echo "$known"
      return 0
    fi
  done
  return 1
}

requested_locale() {
  local header="$1" tag
  IFS=',' read -ra tags <<<"$header"
  for tag in "${tags[@]}"; do
    tag="$(echo "${tag%%;*}" | tr -d '[:space:]')"
    find_locale "$tag" || find_locale "${tag%%-*}" || continue
    return 0
  done
  return 1
}

if match="$(requested_locale "${1:-pt-BR,pt;q=0.9,en;q=0.8}")"; then
  printf '%s\n' "${LOCALES[$match]}"
else
  echo "no match" >&2
  exit 1
fi
