#!/usr/bin/env bash
# wait-for-hydra: Wait for a Hydra CI build to reach a terminal state.
#
# Supports two modes:
#   1. SSE mode (preferred): connects to hydra-github-bridge SSE endpoint
#      for real-time status updates. Requires HYDRA_STATUS_URL.
#   2. Poll mode (fallback): polls GitHub API with exponential backoff.
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
: "${HYDRA_STATUS_URL:=}"

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

# Determine the conclusion/state from a terminal status string.
# Returns: "success", "failure", or empty (pending/unknown).
classify_status() {
    local raw="$1"
    case "$raw" in
        success)  echo "success" ;;
        failure)  echo "failure" ;;
        *)        echo "" ;;
    esac
}

# Check if we've exceeded the timeout.
check_timeout() {
    if [ "$TIMEOUT" -gt 0 ] && [ "$SECONDS" -ge "$TIMEOUT" ]; then
        echo "::error::Timeout after ${SECONDS}s waiting for $HYDRA_JOB"
        exit 2
    fi
}

# --- SSE Mode ----------------------------------------------------------------

# Try to get the current status from the bridge's one-shot endpoint.
# The endpoint returns a JSON map keyed by check-run name:
#   { "required": { "conclusion": "success", ... }, "other-job": { ... } }
# Returns the conclusion string for HYDRA_JOB, or empty on failure.
sse_get_current_status() {
    local url="$1"
    local result
    result=$(curl -sf --max-time 10 "$url" 2>/dev/null) || return 1
    echo "$result" | jq -r --arg job "$HYDRA_JOB" '.[$job].conclusion // empty' 2>/dev/null || true
}

# Connect to the SSE stream and wait for a terminal event.
# Exits with 0 on success, 1 on failure, or returns 1 on connection error
# to signal fallback to polling.
sse_wait() {
    local owner repo sha
    # Extract owner/repo from GITHUB_REPOSITORY (format: owner/repo)
    owner="${GITHUB_REPOSITORY%%/*}"
    repo="${GITHUB_REPOSITORY##*/}"
    sha="$RELEVANT_SHA"

    local base_url="${HYDRA_STATUS_URL%/}/status/${owner}/${repo}/${sha}"

    echo "SSE: Checking current status at ${base_url}"

    # One-shot check: build may already be done.
    local current_state
    current_state=$(sse_get_current_status "$base_url") || true
    if [ -n "$current_state" ]; then
        local result
        result=$(classify_status "$current_state")
        if [ "$result" = "success" ]; then
            echo "$HYDRA_JOB succeeded (from cached status)"
            exit 0
        elif [ "$result" = "failure" ]; then
            echo "$HYDRA_JOB failed (from cached status)"
            exit 1
        fi
        echo "SSE: Current status is '$current_state', connecting to event stream..."
    fi

    # Stream SSE events. curl -N disables buffering.
    # Each event carries a single check-run: {"name":"...","conclusion":"..."}
    # We only act on events matching HYDRA_JOB.
    #
    # We use process substitution (< <(curl ...)) instead of a pipe (curl |
    # while) so the while loop runs in the current shell — otherwise `exit`
    # inside the loop would only terminate the subshell, not the script.
    #
    # read -t 60: timeout each read after 60s so check_timeout fires even
    # when the SSE stream is idle (Cloudflare buffering, no new events).
    # Without this, read blocks indefinitely and the script's TIMEOUT is
    # never enforced. In bash, read -t returns >128 on timeout, 1 on EOF.
    # Cap the SSE stream time to leave room for one-shot re-check and
    # polling fallback if the stream ends without delivering our event.
    # Reserve 2 minutes for fallback; minimum SSE time is 60 seconds.
    local sse_max_time
    if [ "$TIMEOUT" -gt 0 ]; then
        sse_max_time=$((TIMEOUT - SECONDS - 120))
        [ "$sse_max_time" -lt 60 ] && sse_max_time=60
    else
        sse_max_time=86400  # no timeout: cap at 24h (matches cache TTL)
    fi

    # Track when we last did a one-shot re-check so we can poll the
    # cached endpoint periodically. CDN proxies (e.g. Cloudflare) may
    # buffer SSE events, so we re-check every 120s as a safety net.
    local last_recheck="$SECONDS"

    echo "SSE: Connecting to ${base_url}/events (max ${sse_max_time}s, filtering for '$HYDRA_JOB')"
    while true; do
        check_timeout

        # Periodic one-shot re-check: catch status changes that the SSE
        # stream failed to deliver (CDN buffering, lost events, etc.).
        if [ $((SECONDS - last_recheck)) -ge 120 ]; then
            last_recheck="$SECONDS"
            local poll_state
            poll_state=$(sse_get_current_status "$base_url") || true
            if [ -n "$poll_state" ]; then
                local poll_result
                poll_result=$(classify_status "$poll_state")
                if [ "$poll_result" = "success" ]; then
                    echo "$HYDRA_JOB succeeded (from periodic re-check at ${SECONDS}s)"
                    exit 0
                elif [ "$poll_result" = "failure" ]; then
                    echo "$HYDRA_JOB failed (from periodic re-check at ${SECONDS}s)"
                    exit 1
                fi
            fi
        fi

        local read_rc=0
        IFS= read -r -t 60 line || read_rc=$?
        if [ "$read_rc" -gt 128 ]; then
            # read timed out (no data for 60s). Loop to check_timeout.
            continue
        elif [ "$read_rc" -ne 0 ]; then
            # EOF — curl exited (connection drop or max-time reached).
            break
        fi
        case "$line" in
            "data: "*)
                local data="${line#data: }"
                local name conclusion
                name=$(echo "$data" | jq -r '.name // empty' 2>/dev/null) || continue
                # Skip events for other check-runs.
                [ "$name" = "$HYDRA_JOB" ] || continue
                conclusion=$(echo "$data" | jq -r '.conclusion // empty' 2>/dev/null) || continue
                echo "SSE event: $name conclusion=$conclusion (${SECONDS}s elapsed)"
                local result
                result=$(classify_status "$conclusion")
                if [ "$result" = "success" ]; then
                    echo "$HYDRA_JOB succeeded (via SSE)"
                    exit 0
                elif [ "$result" = "failure" ]; then
                    echo "$HYDRA_JOB failed (via SSE)"
                    exit 1
                fi
                ;;
        esac
    done < <(curl -Nsf --max-time "$sse_max_time" \
        "${base_url}/events" 2>/dev/null)

    # SSE stream ended without a terminal event for HYDRA_JOB. This can
    # happen on connection drop, Cloudflare buffering, or curl max-time.
    # Before falling back to polling, do one final one-shot check — the
    # status may have changed while we were connected but the event was
    # lost in transit.
    echo "SSE: Stream ended after ${SECONDS}s, re-checking one-shot endpoint..."
    local final_state
    final_state=$(sse_get_current_status "$base_url") || true
    if [ -n "$final_state" ]; then
        local result
        result=$(classify_status "$final_state")
        if [ "$result" = "success" ]; then
            echo "$HYDRA_JOB succeeded (from one-shot re-check)"
            exit 0
        elif [ "$result" = "failure" ]; then
            echo "$HYDRA_JOB failed (from one-shot re-check)"
            exit 1
        fi
    fi

    echo "SSE: Falling back to polling..."
    return 1
}

# --- Poll Mode ---------------------------------------------------------------

poll_github() {
    if [ -n "$CHECK" ]; then
        echo "Querying: gh api repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/check-runs --paginate --jq '.check_runs[] | select(.name == \"$CHECK\") | .conclusion'" >&2
        # Use tail -1 to handle paginated results that may concatenate
        # multiple values; take the last (most recent) non-empty line.
        gh api "repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/check-runs" \
            --paginate \
            --jq ".check_runs[] | select(.name == \"$CHECK\") | .conclusion" \
            | tail -1
    else
        echo "Querying: gh api repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/status --paginate --jq '.statuses[] | select(.context == \"$STATUS\") | .state'" >&2
        gh api "repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/status" \
            --paginate \
            --jq ".statuses[] | select(.context == \"$STATUS\") | .state" \
            | tail -1
    fi
}

poll_wait() {
    local iteration=0
    local current_delay="$DELAY"

    while true; do
        check_timeout
        iteration=$((iteration + 1))

        local conclusion
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
                local wait_time=$((current_delay + RANDOM % (JITTER + 1)))
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
}

# --- Main --------------------------------------------------------------------

SECONDS=0

echo "Waiting for $HYDRA_JOB on $RELEVANT_SHA (timeout=${TIMEOUT}s, max-delay=${MAX_DELAY}s)"

if [ -n "$HYDRA_STATUS_URL" ]; then
    # Try SSE mode first; fall back to polling on connection failure.
    sse_wait || poll_wait
else
    poll_wait
fi
