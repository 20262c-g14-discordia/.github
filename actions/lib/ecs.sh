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
