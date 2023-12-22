# start with a random sleep to prevent hitting the api too hard.
: "${DELAY:=30}"
: "${JITTER:=30}"
while true; do
    if [ -z "$CHECK" ] && [ -z "$STATUS" ]; then (>&2 echo "Neither STATUS _or_ CHECK provided. Please provide one!"); exit 1; fi
    if [ -n "$CHECK" ] && [ -n "$STATUS" ]; then (>&2 echo "STATUS _and_ CHECK provided. Please provide only one!"); exit 1; fi
    # Note: we need --paginate because there are so many statuses
    if [ -n "$CHECK" ]; then
        # For GitHub Apps (checks)
        HYDRA_JOB="$CHECK"
        echo "Querying: gh api repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/check-runs --paginate --jq '.check_runs[] | select(.name == \"$CHECK\") | .conclusion'"
        conclusion=$(gh api "repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/check-runs" --paginate --jq ".check_runs[] | select(.name == \"$CHECK\") | .conclusion")
    else
        # For GitHub Statuses
        HYDRA_JOB="$STATUS"
        echo "Querying: gh api repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/status --paginate --jq '.statuses[] | select(.context == \"$STATUS\") | .state'"
        conclusion=$(gh api "repos/$GITHUB_REPOSITORY/commits/$RELEVANT_SHA/status" --paginate --jq ".statuses[] | select(.context == \"$STATUS\") | .state")
    fi
    case "$conclusion" in
        success)
            echo "$HYDRA_JOB succeeded"
            exit 0;;
        failure)
            echo "$HYDRA_JOB failed"
            exit 1;;
        *)
            echo "conclusion is: '$conclusion'"
            WAIT=$((DELAY + RANDOM % JITTER))
        echo "$HYDRA_JOB pending. Waiting ${WAIT}s..."
        sleep $WAIT;;
    esac
done
