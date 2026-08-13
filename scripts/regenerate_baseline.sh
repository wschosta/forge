#!/usr/bin/env bash
# Regenerate every state's matrix outputs under the reproducible TF-IDF classifier.
#
# Writes to baseline/{STATE}/outputs/ rather than data/{STATE}/outputs/. The
# committed MATLAB outputs are irreproducible — the classifier that made them no
# longer exists — and the golden test suite diffs against them, so they are kept
# as a historical reference rather than overwritten.
#
# Indiana needs its curated House roster seeded into the baseline tree; without
# it the run silently falls back to LegiScan's 104-member roster for a 100-seat
# chamber (see runner._load_indiana_house_people).
set -uo pipefail

STATES=(CA NY WI OH OR VT KY IN ME MT US)
OUT=baseline
LOGDIR="${OUT}/_logs"

mkdir -p "$LOGDIR" "${OUT}/IN/undergrad"
cp -n data/IN/undergrad/people_2013-2014.xlsx "${OUT}/IN/undergrad/" 2>/dev/null || true

printf '%-4s %-10s %-8s %s\n' STATE STATUS SECONDS BILLS
for s in "${STATES[@]}"; do
    start=$SECONDS
    if forge run "$s" --recompute --classifier tfidf --data-dir "$OUT" \
            >"${LOGDIR}/${s}.log" 2>&1; then
        status=ok
    else
        status=FAILED
    fi
    elapsed=$(( SECONDS - start ))
    bills=$(grep -c 'Chamber vote processing complete' "${LOGDIR}/${s}.log" 2>/dev/null || echo 0)
    printf '%-4s %-10s %-8s %s\n' "$s" "$status" "$elapsed" "$bills"
done
