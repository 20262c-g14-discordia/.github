#!/usr/bin/env bash
# The register-revision action. Reads CLUSTER, SERVICE, IMAGE and CONTAINER (optional)
# from the environment. Registers a revision of SERVICE's task definition with only the
# image changed, and outputs its `arn`; with the platform down it registers nothing and
# outputs skipped=true.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/ecs.sh
. "$(dirname "$0")/../lib/ecs.sh"
# Inputs, set by action.yml; fail here, not deep in an AWS call, if one is missing.
: "${CLUSTER:?}" "${SERVICE:?}" "${IMAGE:?}"

state=$(service_state "$CLUSTER" "$SERVICE")
if [ "$state" != ACTIVE ]; then
  echo "skipped=true" >>"$GITHUB_OUTPUT"
  echo "- \`$SERVICE\`: platform is down; the image is recorded and the next \`make up\` runs it" >>"$GITHUB_STEP_SUMMARY"
  exit 0
fi
arn=$(register_revision "$CLUSTER" "$SERVICE" "$IMAGE" "${CONTAINER:-}")
{
  echo "skipped=false"
  echo "arn=$arn"
} >>"$GITHUB_OUTPUT"
