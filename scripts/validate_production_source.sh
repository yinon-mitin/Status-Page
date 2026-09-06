#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git -C "$ROOT" fetch origin main
head_sha="$(git -C "$ROOT" rev-parse HEAD)"
main_sha="$(git -C "$ROOT" rev-parse origin/main)"
[[ "$head_sha" == "$main_sha" ]] || {
  echo "Production mutation requires exact origin/main ($main_sha), got $head_sha." >&2
  exit 2
}

worktree_changes="$(git -C "$ROOT" status --porcelain --untracked-files=all)"
[[ -z "$worktree_changes" ]] || {
  echo "Production mutation requires a clean tracked and untracked worktree." >&2
  printf '%s\n' "$worktree_changes" >&2
  exit 2
}

shopt -s nullglob
implicit_var_files=(
  "$ROOT"/terraform/*.auto.tfvars
  "$ROOT"/terraform/*.auto.tfvars.json
)
[[ "${#implicit_var_files[@]}" -eq 0 ]] || {
  echo "Implicit *.auto.tfvars files are forbidden for production mutation:" >&2
  printf '  %s\n' "${implicit_var_files[@]}" >&2
  exit 2
}
