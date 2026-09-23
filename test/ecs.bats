setup() {
  load helpers
  setup_stub
  # shellcheck source=../actions/lib/ecs.sh
  source "$BATS_TEST_DIRNAME/../actions/lib/ecs.sh"
}

@test "service_state: an ACTIVE service is ACTIVE" {
  service ACTIVE "$TD4" | respond ecs.describe-services -
  run --separate-stderr service_state discordia-prd-cluster identity
  [ "$status" -eq 0 ]
  [ "$output" = ACTIVE ]
}

@test "service_state: a service make down left INACTIVE is down" {
  service INACTIVE "$TD4" | respond ecs.describe-services -
  run --separate-stderr service_state discordia-prd-cluster identity
  [ "$status" -eq 0 ]
  [ "$output" = down ]
}

@test "service_state: a service that was never created is down" {
  echo '{"services":[],"failures":[{"arn":"arn:x","reason":"MISSING"}]}' |
    respond ecs.describe-services -
  run --separate-stderr service_state discordia-prd-cluster identity
  [ "$status" -eq 0 ]
  [ "$output" = down ]
}

@test "service_state: no cluster at all is down" {
  respond_error ecs.describe-services - 254 \
    "An error occurred (ClusterNotFoundException) when calling the DescribeServices operation: Cluster not found."
  run --separate-stderr service_state discordia-prd-cluster identity
  [ "$status" -eq 0 ]
  [ "$output" = down ]
}

@test "service_state: a permissions error fails instead of reading as down" {
  respond_error ecs.describe-services - 254 \
    "An error occurred (AccessDeniedException) when calling the DescribeServices operation: not authorized"
  run --separate-stderr service_state discordia-prd-cluster identity
  [ "$status" -ne 0 ]
  [ "$output" = "" ]
  [[ $stderr == *AccessDeniedException* ]]
}

@test "register_revision: swaps only the image and drops what ECS computes" {
  service ACTIVE "$TD4" | respond ecs.describe-services -
  task_definition "$ONE_CONTAINER" | respond ecs.describe-task-definition -
  echo "{\"taskDefinition\":{\"taskDefinitionArn\":\"$TD5\"}}" | respond ecs.register-task-definition -

  run --separate-stderr register_revision discordia-prd-cluster identity new@sha256:bbb
  [ "$status" -eq 0 ]
  [ "$output" = "$TD5" ]

  run jq -c '{family, cpu, executionRoleArn, containerDefinitions,
              gone: [.taskDefinitionArn, .revision, .status, .requiresAttributes,
                     .compatibilities, .registeredAt, .registeredBy]}' \
    "$RUNNER_TEMP/task-definition.json"
  [ "$output" = '{"family":"identity","cpu":"256","executionRoleArn":"arn:aws:iam::837111420485:role/discordia-prd-identity-execution","containerDefinitions":[{"name":"identity","image":"new@sha256:bbb","environment":[{"name":"PORT","value":"8080"}]}],"gone":[null,null,null,null,null,null,null]}' ]

  grep -qx "ecs describe-task-definition --task-definition $TD4 --output json" "$AWS_STUB_LOG"
  grep -qx "ecs register-task-definition --cli-input-json file://$RUNNER_TEMP/task-definition.json --output json" "$AWS_STUB_LOG"
}

@test "register_revision: two containers and no name registers nothing" {
  service ACTIVE "$TD4" | respond ecs.describe-services -
  task_definition "$TWO_CONTAINERS" | respond ecs.describe-task-definition -

  run --separate-stderr register_revision discordia-prd-cluster identity new@sha256:bbb
  [ "$status" -ne 0 ]
  [[ $stderr == *"runs 2 containers (app,log-router)"* ]]
  ! grep -q register-task-definition "$AWS_STUB_LOG"
}

@test "register_revision: a container name that is not there registers nothing" {
  service ACTIVE "$TD4" | respond ecs.describe-services -
  task_definition "$TWO_CONTAINERS" | respond ecs.describe-task-definition -

  run --separate-stderr register_revision discordia-prd-cluster identity new@sha256:bbb identity
  [ "$status" -ne 0 ]
  [[ $stderr == *"no container named 'identity' (it has: app,log-router)"* ]]
  ! grep -q register-task-definition "$AWS_STUB_LOG"
}

@test "register_revision: a named container changes and its neighbour does not" {
  service ACTIVE "$TD4" | respond ecs.describe-services -
  task_definition "$TWO_CONTAINERS" | respond ecs.describe-task-definition -
  echo "{\"taskDefinition\":{\"taskDefinitionArn\":\"$TD5\"}}" | respond ecs.register-task-definition -

  run --separate-stderr register_revision discordia-prd-cluster identity new@sha256:bbb app
  [ "$status" -eq 0 ]
  run jq -c '[.containerDefinitions[] | {name, image}]' "$RUNNER_TEMP/task-definition.json"
  [ "$output" = '[{"name":"app","image":"new@sha256:bbb"},{"name":"log-router","image":"fluent@sha256:ccc"}]' ]
}

updated() { # the update-service answer: our new PRIMARY deployment beside the old one
  jq -n --argjson d "[$(deployment ecs-svc/2 PRIMARY "$TD5" IN_PROGRESS),$(deployment ecs-svc/1 ACTIVE "$TD4" COMPLETED)]" \
    '{service: {deployments: $d}}'
}

@test "roll: passes once this deployment completes" {
  updated | respond ecs.update-service -
  service ACTIVE "$TD5" "[$(deployment ecs-svc/2 PRIMARY "$TD5" IN_PROGRESS)]" | respond ecs.describe-services 1
  service ACTIVE "$TD5" "[$(deployment ecs-svc/2 PRIMARY "$TD5" COMPLETED)]" | respond ecs.describe-services 2

  run --separate-stderr roll discordia-prd-cluster identity "$TD5"
  [ "$status" -eq 0 ]
  grep -qx "ecs update-service --cluster discordia-prd-cluster --service identity --task-definition $TD5 --output json" "$AWS_STUB_LOG"
  [ "$(grep -c "ecs describe-services" "$AWS_STUB_LOG")" -eq 2 ]
}

@test "roll: fails when the circuit breaker rolled this deployment back" {
  updated | respond ecs.update-service -
  service ACTIVE "$TD4" "[$(deployment ecs-svc/3 PRIMARY "$TD4" IN_PROGRESS),$(deployment ecs-svc/2 ACTIVE "$TD5" FAILED)]" |
    respond ecs.describe-services -

  run --separate-stderr roll discordia-prd-cluster identity "$TD5"
  [ "$status" -eq 3 ]
  [[ $stderr == *"deployment ecs-svc/2 failed; ECS rolled back"* ]]
}

@test "roll: fails when this deployment is no longer listed" {
  updated | respond ecs.update-service -
  service ACTIVE "$TD4" "[$(deployment ecs-svc/3 PRIMARY "$TD4" COMPLETED)]" | respond ecs.describe-services -

  run --separate-stderr roll discordia-prd-cluster identity "$TD5"
  [ "$status" -eq 1 ]
  [[ $stderr == *"ecs-svc/2 is no longer listed"* ]]
}

@test "roll: gives up after the configured number of polls" {
  export ROLL_POLL_ATTEMPTS=3
  updated | respond ecs.update-service -
  service ACTIVE "$TD5" "[$(deployment ecs-svc/2 PRIMARY "$TD5" IN_PROGRESS)]" | respond ecs.describe-services -

  run --separate-stderr roll discordia-prd-cluster identity "$TD5"
  [ "$status" -eq 1 ]
  [[ $stderr == *"did not settle"* ]]
  [[ $stderr == *"ECS may still finish it"* ]]
  [ "$(grep -c "ecs describe-services" "$AWS_STUB_LOG")" -eq 3 ]
}

@test "roll: fails when ECS started no deployment of the revision" {
  echo '{"service":{"deployments":[]}}' | respond ecs.update-service -

  run --separate-stderr roll discordia-prd-cluster identity "$TD5"
  [ "$status" -ne 0 ]
  [[ $stderr == *"ECS started no deployment"* ]]
  ! grep -q "ecs describe-services" "$AWS_STUB_LOG"
}
