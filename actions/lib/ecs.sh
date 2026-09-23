# shellcheck shell=bash
# ECS helpers shared by the register-revision and roll-service actions.
#
# Every AWS call asks for the full JSON and reads it with jq rather than --query, so the
# tests' fake `aws` (test/stub/aws) answers with the API's real response shapes. The
# functions return non-zero on failure with ::error:: lines on stderr; they never exit,
# so the caller decides what a failure means.

# service_state CLUSTER SERVICE
# Prints ACTIVE, or `down` when the cluster or the service does not exist or is not ACTIVE,
# which is what a destroyed platform looks like. Any other error (credentials, permissions,
# throttling) fails: a deploy that cannot tell must not report the platform down and pass.
service_state() {
  local cluster=$1 service=$2 out err
  err=$(mktemp)
  if ! out=$(aws ecs describe-services --cluster "$cluster" --services "$service" \
    --output json 2>"$err"); then
    if grep -q ClusterNotFoundException "$err"; then
      rm -f "$err"
      echo down
      return 0
    fi
    echo "::error::cannot tell whether $service is running:" >&2
    cat "$err" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  if [ "$(jq -r '.services[0].status // "MISSING"' <<<"$out")" = ACTIVE ]; then
    echo ACTIVE
  else
    echo down
  fi
}

# register_revision CLUSTER SERVICE IMAGE [CONTAINER]
# Registers a new revision of the service's current task definition in which only
# CONTAINER's image becomes IMAGE, and prints its ARN. CONTAINER may be omitted only when
# the task definition has exactly one container. Everything else Terraform set -- the
# environment, secrets, roles, sizing -- is carried over unchanged. The JSON registered is
# left in $RUNNER_TEMP/task-definition.json.
register_revision() {
  local cluster=$1 service=$2 image=$3 container=${4:-} out current td names count file
  out=$(aws ecs describe-services --cluster "$cluster" --services "$service" \
    --output json) || return 1
  current=$(jq -r '.services[0].taskDefinition' <<<"$out")
  td=$(aws ecs describe-task-definition --task-definition "$current" --output json) || return 1
  names=$(jq -r '.taskDefinition.containerDefinitions[].name' <<<"$td")
  count=$(grep -c . <<<"$names" || true)
  if [ -z "$container" ]; then
    if [ "$count" -ne 1 ]; then
      echo "::error::$service runs $count containers ($(paste -sd, <<<"$names")); name the one to update with 'container'" >&2
      return 1
    fi
    container=$names
  elif ! grep -qxF -- "$container" <<<"$names"; then
    echo "::error::$service has no container named '$container' (it has: $(paste -sd, <<<"$names"))" >&2
    return 1
  fi
  file=${RUNNER_TEMP:-$(mktemp -d)}/task-definition.json
  jq --arg c "$container" --arg image "$image" '
    .taskDefinition
    | .containerDefinitions |= map(if .name == $c then .image = $image else . end)
    | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
          .registeredAt, .registeredBy, .deregisteredAt)' <<<"$td" >"$file"
  out=$(aws ecs register-task-definition --cli-input-json "file://$file" --output json) || return 1
  jq -r '.taskDefinition.taskDefinitionArn' <<<"$out"
}
