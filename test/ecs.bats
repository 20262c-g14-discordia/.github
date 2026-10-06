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

MIGRATE='["/messaging","migrate","up"]'
MONGO_URI=mongodb://10.0.1.23:27017/messaging?replicaSet=rs0

runs_and_stops() { # EXIT_CODE|null STOPPED_REASON -- messaging's task starts, then stops so
  SERVICE=messaging service ACTIVE "$MESSAGING_TD" | respond ecs.describe-services -
  started_task | respond ecs.run-task -
  : | respond ecs.wait -
  stopped_task messaging "$1" "$2" | respond ecs.describe-tasks -
}

@test "run_task: runs the revision on the service's network, with command and environment overridden" {
  runs_and_stops 0 "Essential container in task exited"
  run --separate-stderr run_task discordia-prd-cluster messaging "$MESSAGING_TD" messaging \
    "$MIGRATE" "{\"MONGO_URI\":\"$MONGO_URI\",\"MONGO_DATABASE\":\"messaging\"}"
  [ "$status" -eq 0 ]
  [ "$(jq -r .exitCode <<<"$output")" = 0 ]
  [ "$(jq -r .task <<<"$output")" = "$TASK" ]
  [ "$(jq -r .stoppedReason <<<"$output")" = "Essential container in task exited" ]
  request=$BATS_TEST_TMPDIR/run-task.json
  [ "$(jq -r .cluster "$request")" = discordia-prd-cluster ]
  [ "$(jq -r .taskDefinition "$request")" = "$MESSAGING_TD" ]
  [ "$(jq -r .count "$request")" = 1 ]
  [ "$(jq -r .launchType "$request")" = FARGATE ]
  [ "$(jq -r .platformVersion "$request")" = LATEST ]
  [ "$(jq -c .networkConfiguration "$request")" = '{"awsvpcConfiguration":{"subnets":["subnet-0a1b2c3d","subnet-4e5f6a7b"],"securityGroups":["sg-0123abcd"],"assignPublicIp":"ENABLED"}}' ]
  [ "$(jq -c .overrides.containerOverrides "$request")" = "[{\"name\":\"messaging\",\"command\":[\"/messaging\",\"migrate\",\"up\"],\"environment\":[{\"name\":\"MONGO_URI\",\"value\":\"$MONGO_URI\"},{\"name\":\"MONGO_DATABASE\",\"value\":\"messaging\"}]}]" ]
  grep -qx -- "ecs run-task --cli-input-json file://$request --output json" "$AWS_STUB_LOG"
  grep -qx -- "ecs wait tasks-stopped --cluster discordia-prd-cluster --tasks $TASK" "$AWS_STUB_LOG"
}

@test "run_task: an empty environment overrides no variable" {
  runs_and_stops 0 "Essential container in task exited"
  run --separate-stderr run_task discordia-prd-cluster messaging "$MESSAGING_TD" messaging \
    "$MIGRATE" '{}'
  [ "$status" -eq 0 ]
  [ "$(jq -c '.overrides.containerOverrides[0].environment' "$BATS_TEST_TMPDIR/run-task.json")" = '[]' ]
}

@test "run_task: a service on a capacity provider strategy runs on it, not on a launch type" {
  SERVICE=messaging service ACTIVE "$MESSAGING_TD" |
    jq '.services[0] |= (del(.launchType, .platformVersion)
          + {capacityProviderStrategy: [{capacityProvider: "FARGATE", weight: 1, base: 0}]})' |
    respond ecs.describe-services -
  started_task | respond ecs.run-task -
  : | respond ecs.wait -
  stopped_task messaging 0 "Essential container in task exited" | respond ecs.describe-tasks -
  run --separate-stderr run_task discordia-prd-cluster messaging "$MESSAGING_TD" messaging \
    "$MIGRATE" '{}'
  [ "$status" -eq 0 ]
  request=$BATS_TEST_TMPDIR/run-task.json
  [ "$(jq -r 'has("launchType")' "$request")" = false ]
  [ "$(jq -c .capacityProviderStrategy "$request")" = '[{"capacityProvider":"FARGATE","weight":1,"base":0}]' ]
}

@test "run_task: a container that never started has no exit code" {
  runs_and_stops null "CannotPullContainerError: pull image manifest has been retried 1 time(s)"
  run --separate-stderr run_task discordia-prd-cluster messaging "$MESSAGING_TD" messaging \
    "$MIGRATE" '{}'
  [ "$status" -eq 0 ]
  [ "$(jq -r .exitCode <<<"$output")" = null ]
  [[ $(jq -r .stoppedReason <<<"$output") == CannotPullContainerError* ]]
}

@test "run_task: a task ECS would not start fails with its reasons, and waits for nothing" {
  SERVICE=messaging service ACTIVE "$MESSAGING_TD" | respond ecs.describe-services -
  echo '{"tasks":[],"failures":[{"arn":"arn:aws:ecs:us-east-1:837111420485:container-instance/x","reason":"RESOURCE:MEMORY"}]}' |
    respond ecs.run-task -
  run --separate-stderr run_task discordia-prd-cluster messaging "$MESSAGING_TD" messaging \
    "$MIGRATE" '{}'
  [ "$status" -ne 0 ]
  [[ $stderr == *"ECS started no task"*"RESOURCE:MEMORY"* ]]
  ! grep -q "ecs wait" "$AWS_STUB_LOG"
}

@test "run_task: a task that outlasts the waiter fails, and reads no exit code" {
  SERVICE=messaging service ACTIVE "$MESSAGING_TD" | respond ecs.describe-services -
  started_task | respond ecs.run-task -
  respond_error ecs.wait - 255 "Waiter TasksStopped failed: Max attempts exceeded"
  run --separate-stderr run_task discordia-prd-cluster messaging "$MESSAGING_TD" messaging \
    "$MIGRATE" '{}'
  [ "$status" -ne 0 ]
  [[ $stderr == *"Max attempts exceeded"* ]]
  [[ $stderr == *"may still be running"* ]]
  ! grep -q "ecs describe-tasks" "$AWS_STUB_LOG"
}
