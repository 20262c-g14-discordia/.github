#!/usr/bin/env bash
# The roll-service action. Reads CLUSTER, SERVICE, CONTAINER (optional), and exactly one
# of IMAGE (register a revision with it first) or TASK_DEFINITION (roll to that revision)
# from the environment. Rolls SERVICE and fails if ECS rolls it back. With the platform
# down it changes nothing and passes: the recorded image is what `make up` starts.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/ecs.sh
. "$(dirname "$0")/../lib/ecs.sh"
# Inputs, set by action.yml; fail here, not deep in an AWS call, if one is missing.
: "${CLUSTER:?}" "${SERVICE:?}"

given=0
if [ -n "${IMAGE:-}" ]; then given=$((given + 1)); fi
if [ -n "${TASK_DEFINITION:-}" ]; then given=$((given + 1)); fi
if [ "$given" -ne 1 ]; then
  echo "::error::roll-service needs exactly one of image and task-definition" >&2
  exit 2
fi

state=$(service_state "$CLUSTER" "$SERVICE")
if [ "$state" != ACTIVE ]; then
  echo "- \`$SERVICE\`: platform is down; nothing rolled, the next \`make up\` runs it" >>"$GITHUB_STEP_SUMMARY"
  exit 0
fi

td=${TASK_DEFINITION:-}
if [ -z "$td" ]; then
  td=$(register_revision "$CLUSTER" "$SERVICE" "$IMAGE" "${CONTAINER:-}")
fi
# The version was recorded before the rollout, so a rollout ECS rolled back leaves the
# parameter naming the release that failed, and the next `make up` would start it.
if ! roll "$CLUSTER" "$SERVICE" "$td"; then
  echo "::error::/discordia/prd/image/$SERVICE still names the version that failed, so the next \`make up\` starts it; dispatch deploy.yml with the previous release tag" >&2
  echo "- \`$SERVICE\`: rolled back by ECS; \`/discordia/prd/image/$SERVICE\` still names the failed version, redeploy the previous tag" >>"$GITHUB_STEP_SUMMARY"
  exit 1
fi
echo "arn=$td" >>"$GITHUB_OUTPUT"
echo "- \`$SERVICE\` → \`$td\`" >>"$GITHUB_STEP_SUMMARY"
