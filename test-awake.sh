#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
test_dir=$(mktemp -d)
inhibitor_pid=""
sleep_pid=""

cleanup() {
  if [[ -n "$sleep_pid" ]]; then kill "$sleep_pid" 2>/dev/null || true; fi
  if [[ -n "$inhibitor_pid" ]]; then
    kill "$inhibitor_pid" 2>/dev/null || true
    wait "$inhibitor_pid" 2>/dev/null || true
  fi
  rm -rf "$test_dir"
}
trap cleanup EXIT

check_duration() {
  local expected=$1 input=$2 reason=$3
  shift 3

  "$repo_root/bin/awake" "$@" <<<"$input" >"$test_dir/out" 2>"$test_dir/err" &
  inhibitor_pid=$!
  sleep_pid=""
  for _ in {1..100}; do
    sleep_pid=$(pgrep -P "$inhibitor_pid" -x sleep || true)
    [[ -n "$sleep_pid" ]] && break
    if ! kill -0 "$inhibitor_pid" 2>/dev/null; then
      wait "$inhibitor_pid" || true
      cat "$test_dir/err" >&2
      echo "awake exited before starting sleep" >&2
      exit 1
    fi
    sleep 0.05
  done
  [[ -n "$sleep_pid" ]] || { echo "sleep did not start" >&2; exit 1; }

  local -a sleep_args
  mapfile -d '' -t sleep_args <"/proc/$sleep_pid/cmdline"
  [[ ${sleep_args[1]} == "$expected" ]] || {
    echo "Expected sleep $expected, got ${sleep_args[*]}" >&2
    exit 1
  }
  local inhibitors
  inhibitors=$(gnome-session-inhibit --list)
  [[ "$inhibitors" == *"$reason (suspend, idle)"* ]] || {
    echo "Expected GNOME inhibitor for $reason, got: $inhibitors" >&2
    exit 1
  }
  kill "$sleep_pid"
  sleep_pid=""
  wait "$inhibitor_pid"
  inhibitor_pid=""
  inhibitors=$(gnome-session-inhibit --list)
  [[ "$inhibitors" != *"$reason (suspend, idle)"* ]] || {
    echo "Inhibitor for $reason was not released" >&2
    exit 1
  }
}

check_invalid() {
  local output
  if output=$("$repo_root/bin/awake" "$@" </dev/null 2>&1); then
    echo "Expected failure for: $*" >&2
    exit 1
  fi
  [[ "$output" == *"Usage:"* ]] || {
    echo "Expected usage error for: $*: $output" >&2
    exit 1
  }
}

check_duration 1m "" "Keep awake" 1m
check_duration 2m "" "Keep awake" 2min
check_duration 3h "" "Keep awake" 3h
check_duration 10h "" "Keep awake" 10hr
check_duration 1h "" "Keep awake" 1
check_duration 2h "" "Long-running script" --reason "Long-running script" 2hr
check_duration 9h "" "Keep awake" 9
check_duration 10m "" "Keep awake" 10
check_duration 8h "" "Keep awake" 08
check_duration 10m "" "Keep awake" 010
check_duration 15m "15min" "Keep awake"
[[ $(cat "$test_dir/err") == *"How long"* ]] || {
  echo "Expected a prompt for the duration" >&2
  exit 1
}
check_duration 1h "1" "Prompted reason" --reason "Prompted reason"
check_duration 1m "" "After duration" 1m --reason "After duration"

for invalid in 0 0m 0hr 1.5 1.5h -1 5seconds 2hrs ""; do
  check_invalid "$invalid"
done
check_invalid --reason
check_invalid --reason ""
check_invalid --unknown
check_invalid 1m 2m
check_invalid
if output=$(printf '1.5h\n' | "$repo_root/bin/awake" 2>&1); then
  echo "Expected failure for a decimal entered at the prompt" >&2
  exit 1
fi
[[ "$output" == *"How long"*"Usage:"* ]] || {
  echo "Expected a prompt and usage error for a decimal: $output" >&2
  exit 1
}

output=$("$repo_root/bin/awake" --help 2>&1)
[[ "$output" == *"Usage:"* ]] || {
  echo "Expected usage information from --help: $output" >&2
  exit 1
}

status=0
timeout --signal=INT 1 "$repo_root/bin/awake" --reason "awake interrupt test" 1m \
  >"$test_dir/out" 2>"$test_dir/err" || status=$?
[[ $status == 124 && ! -s "$test_dir/out" && ! -s "$test_dir/err" ]] || {
  echo "Interrupt test failed with status $status" >&2
  cat "$test_dir/out" "$test_dir/err" >&2
  exit 1
}
inhibitors=$(gnome-session-inhibit --list)
[[ "$inhibitors" != *"awake interrupt test"* ]] || {
  echo "Inhibitor was not released after interruption" >&2
  exit 1
}

echo "Awake tests passed."
