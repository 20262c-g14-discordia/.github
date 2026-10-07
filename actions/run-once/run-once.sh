#!/usr/bin/env bash
# The run-once action. Reads CLUSTER, SERVICE, TASK_DEFINITION, COMMAND (a JSON array),
# ENVIRONMENT (a JSON object, optional) and CONTAINER (optional; SERVICE when empty) from the
# environment. Runs one task of TASK_DEFINITION on SERVICE's network configuration with that
# command and environment, and fails unless CONTAINER exits 0. With the platform down it runs
# nothing and passes: register-revision then outputs no revision, and nothing will serve
# until the next `mise run up`, which migrates on its own.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/ecs.sh
. "$(dirname "$0")/../lib/ecs.sh"
# Inputs, set by action.yml; fail here, not deep in an AWS call, if one is missing.
: "${CLUSTER:?}" "${SERVICE:?}" "${COMMAND:?}"
environment=${ENVIRONMENT:-}
[ -n "$environment" ] || environment='{}'
container=${CONTAINER:-$SERVICE}

if ! jq -e 'type == "array" and length > 0 and all(type == "string")' \
  <<<"$COMMAND" >/dev/null 2>&1; then
  echo "::error::run-once: command must be a JSON array of strings, e.g. [\"/messaging\",\"migrate\",\"up\"]" >&2
  exit 2
fi
if ! jq -e 'type == "object"' <<<"$environment" >/dev/null 2>&1; then
  echo "::error::run-once: environment must be a JSON object, e.g. {\"MONGO_URI\":\"mongodb://...\"}" >&2
  exit 2
fi
shown=$(jq -r 'join(" ")' <<<"$COMMAND")

state=$(service_state "$CLUSTER" "$SERVICE")
if [ "$state" != ACTIVE ]; then
  echo "- \`$SERVICE\`: platform is down; \`$shown\` did not run" >>"$GITHUB_STEP_SUMMARY"
  exit 0
fi
# Required only now: with the platform down, register-revision outputs an empty arn.
if [ -z "${TASK_DEFINITION:-}" ]; then
  echo "::error::run-once needs a task-definition while $SERVICE is running" >&2
  exit 2
fi

result=$(run_task "$CLUSTER" "$SERVICE" "$TASK_DEFINITION" "$container" "$COMMAND" "$environment")
code=$(jq -r '.exitCode // "none"' <<<"$result")
reason=$(jq -r '.stoppedReason' <<<"$result")
if [ "$code" != 0 ]; then
  echo "::error::$SERVICE: \`$shown\` in $container exited $code; ECS stopped the task with: $reason" >&2
  echo "- \`$SERVICE\`: \`$shown\` **failed**, exit code $code; stop reason: $reason" >>"$GITHUB_STEP_SUMMARY"
  exit 1
fi
echo "- \`$SERVICE\`: \`$shown\` exited 0; stop reason: $reason" >>"$GITHUB_STEP_SUMMARY"
