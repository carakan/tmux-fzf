#!/usr/bin/env bash
# Test runner: executes every test/cases/*.t.sh in its own sandbox and
# summarizes. No live tmux server and no real fzf required — both are
# stubbed (test/lib.sh).
#
#   test/run.sh          run everything
#   test/run.sh mru      run cases matching a substring

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pattern="${1:-}"
pass=0; fail=0; failed_names=""

for case_file in "$here"/cases/*.t.sh; do
    name="$(basename "$case_file" .t.sh)"
    [ -n "$pattern" ] && case "$name" in *"$pattern"*) ;; *) continue ;; esac
    if bash "$case_file"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1)); failed_names="$failed_names $name"
    fi
done

echo
echo "cases: $pass passed, $fail failed${failed_names:+ ($failed_names)}"
[ "$fail" -eq 0 ]
