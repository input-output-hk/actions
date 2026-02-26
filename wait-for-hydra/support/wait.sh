#!/usr/bin/env bash
# wait-for-hydra: Wait for a Hydra CI build to reach a terminal state.
#
# Polls the GitHub API with exponential backoff until the specified
# check-run or status reaches a terminal state.
#
# Exit codes:
#   0 - build succeeded
#   1 - build failed
#   2 - timeout exceeded
#
# Copyright (c) Moritz Angermann <moritz.angermann@iohk.io>, Input Output Group.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# --- Configuration -----------------------------------------------------------

: "${DELAY:=30}"
: "${JITTER:=30}"
: "${TIMEOUT:=3600}"
: "${MAX_DELAY:=300}"

# --- Validation --------------------------------------------------------------

if [ -z "$CHECK" ] && [ -z "$STATUS" ]; then
    echo "::error::Neither STATUS nor CHECK provided. Please provide one!" >&2
    exit 1
fi

if [ -n "$CHECK" ] && [ -n "$STATUS" ]; then
    echo "::error::Both STATUS and CHECK provided. Please provide only one!" >&2
    exit 1
fi

HYDRA_JOB="${CHECK:-$STATUS}"

# --- Helpers -----------------------------------------------------------------

# Check if we've exceeded the timeout.
check_timeout() {
    if [ "$TIMEOUT" -gt 0 ] && [ "$SECONDS" -ge "$TIMEOUT" ]; then
        echo "::error::Timeout after ${SECONDS}s waiting for $HYDRA_JOB"
        exit 2
    fi
}

# --- Poll Mode ---------------------------------------------------------------

poll_github() {
    if [ -n "$CHECK" ]; then
        # Debug output to stderr so it doesn't pollute the captured result.
        echo "Querying: gh api repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/check-runs --paginate --jq '...select(.name == \"$CHECK\")...'" >&2
        # Use tail -1 to handle paginated results that may concatenate
        # multiple values; take the last (most recent) non-empty line.
        gh api "repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/check-runs" \
            --paginate \
            --jq ".check_runs[] | select(.name == \"$CHECK\") | .conclusion" \
            | tail -1
    else
        # Debug output to stderr so it doesn't pollute the captured result.
        echo "Querying: gh api repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/status --paginate --jq '...select(.context == \"$STATUS\")...'" >&2
        gh api "repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/status" \
            --paginate \
            --jq ".statuses[] | select(.context == \"$STATUS\") | .state" \
            | tail -1
    fi
}

# --- Main --------------------------------------------------------------------

SECONDS=0
iteration=0
current_delay="$DELAY"

echo "Waiting for $HYDRA_JOB on $RELEVANT_SHA (timeout=${TIMEOUT}s, max-delay=${MAX_DELAY}s)"

while true; do
    check_timeout
    iteration=$((iteration + 1))

    conclusion=$(poll_github)

    case "$conclusion" in
        success)
            echo "$HYDRA_JOB succeeded (iteration $iteration, ${SECONDS}s elapsed)"
            exit 0
            ;;
        failure)
            echo "$HYDRA_JOB failed (iteration $iteration, ${SECONDS}s elapsed)"
            exit 1
            ;;
        *)
            wait_time=$((current_delay + RANDOM % (JITTER + 1)))
            echo "$HYDRA_JOB pending (conclusion='$conclusion'). Iteration $iteration, ${SECONDS}s elapsed. Waiting ${wait_time}s..."
            sleep "$wait_time"

            # Exponential backoff: double the delay, cap at MAX_DELAY.
            current_delay=$((current_delay * 2))
            if [ "$current_delay" -gt "$MAX_DELAY" ]; then
                current_delay="$MAX_DELAY"
            fi
            ;;
    esac
done
