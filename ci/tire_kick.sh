#!/bin/bash

# Default to 1 core
N=${1:-1}

# Any setup needed for the job
echo "Running tire_kick"
make -C bp_top/syn tire_kick -j ${N}

# Check for failures in the report directory
grep -cr "FAIL" */syn/reports/ && echo "[CI CHECK] $0: FAILED" && exit 1
echo "[CI CHECK] $0: PASSED" && exit 0
