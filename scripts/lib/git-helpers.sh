#!/usr/bin/env bash
#
# Retried network helpers for transient upstream failures.
#

git_ls_remote_retry() {
  local attempt
  local output

  for attempt in 1 2 3; do
    if output="$(git ls-remote "$@" 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    fi

    echo "[!] git ls-remote attempt ${attempt}/3 failed: $output" >&2
    [[ "$attempt" -eq 3 ]] || sleep $((attempt * 2))
  done

  return 1
}

git_fetch_retry() {
  local repo_dir="$1"
  shift
  local attempt

  for attempt in 1 2 3; do
    if git -C "$repo_dir" fetch "$@"; then
      return 0
    fi

    echo "[!] git fetch attempt ${attempt}/3 failed in ${repo_dir}." >&2
    [[ "$attempt" -eq 3 ]] || sleep $((attempt * 2))
  done

  return 1
}
