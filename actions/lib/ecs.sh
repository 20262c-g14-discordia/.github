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

# roll CLUSTER SERVICE TASK_DEFINITION_ARN
# Points the service at the revision and waits for that deployment's own outcome. Not
# `aws ecs wait services-stable`: a service the circuit breaker has rolled back is stable
# too, and would pass. ROLL_POLL_ATTEMPTS (60) and ROLL_POLL_SECONDS (10) bound the wait.
# Returns 3 when the circuit breaker rolled this deployment back, and 1 on any other
# failure, so the caller knows when the previous revision is what is serving.
roll() {
  local cluster=$1 service=$2 td=$3 out deployment state i
  local attempts=${ROLL_POLL_ATTEMPTS:-60} interval=${ROLL_POLL_SECONDS:-10}
  out=$(aws ecs update-service --cluster "$cluster" --service "$service" \
    --task-definition "$td" --output json) || return 1
  deployment=$(jq -r --arg td "$td" '[.service.deployments[]
      | select(.status == "PRIMARY" and .taskDefinition == $td) | .id][0] // empty' <<<"$out")
  if [ -z "$deployment" ]; then
    echo "::error::ECS started no deployment of $td for $service" >&2
    return 1
  fi
  for ((i = 0; i < attempts; i++)); do
    out=$(aws ecs describe-services --cluster "$cluster" --services "$service" \
      --output json) || return 1
    state=$(jq -r --arg id "$deployment" '[.services[0].deployments[]?
        | select(.id == $id) | .rolloutState][0] // "GONE"' <<<"$out")
    case $state in
      COMPLETED) return 0 ;;
      FAILED)
        echo "::error::$service: deployment $deployment failed; ECS rolled back to the previous revision" >&2
        return 3
        ;;
      GONE)
        echo "::error::$service: deployment $deployment is no longer listed; something replaced it" >&2
        return 1
        ;;
    esac
    sleep "$interval"
  done
  echo "::error::$service: deployment $deployment did not settle within $((attempts * interval))s; ECS may still finish it" >&2
  return 1
}
