setup() {
  load helpers
  setup_stub
  REGISTER=$BATS_TEST_DIRNAME/../actions/register-revision/register-revision.sh
  ROLL=$BATS_TEST_DIRNAME/../actions/roll-service/roll-service.sh
  RUN=$BATS_TEST_DIRNAME/../actions/run-once/run-once.sh
  export CLUSTER=discordia-prd-cluster SERVICE=identity IMAGE=new@sha256:bbb
  export TASK_DEFINITION="" CONTAINER="" PREVIOUS="" ENVIRONMENT='{}'
  export COMMAND='["/messaging","migrate","up"]'
  OLD=837111420485.dkr.ecr.us-east-1.amazonaws.com/discordia/identity@sha256:$(printf 'b%.0s' {1..64})
}

rolls_td5_then() { # ROLLOUT_JSON -- a rollout of TD5 from TD4 whose later polls answer ROLLOUT_JSON
  export IMAGE="" TASK_DEFINITION=$TD5
  service ACTIVE "$TD4" | respond ecs.describe-services 1
  jq -n --argjson d "[$(deployment ecs-svc/2 PRIMARY "$TD5" IN_PROGRESS)]" '{service: {deployments: $d}}' |
    respond ecs.update-service -
  service ACTIVE "$TD4" "$1" | respond ecs.describe-services -
}

rolled_back() {
  rolls_td5_then "[$(deployment ecs-svc/3 PRIMARY "$TD4" IN_PROGRESS),$(deployment ecs-svc/2 ACTIVE "$TD5" FAILED)]"
}

platform_down() {
  respond_error ecs.describe-services - 254 \
    "An error occurred (ClusterNotFoundException) when calling the DescribeServices operation: Cluster not found."
}

registers_td5() {
  task_definition "$ONE_CONTAINER" | respond ecs.describe-task-definition -
  echo "{\"taskDefinition\":{\"taskDefinitionArn\":\"$TD5\"}}" | respond ecs.register-task-definition -
}

@test "register-revision: with the platform down, skips and says so" {
  platform_down
  run --separate-stderr "$REGISTER"
  [ "$status" -eq 0 ]
  grep -qx "skipped=true" "$GITHUB_OUTPUT"
  grep -qF "platform is down" "$GITHUB_STEP_SUMMARY"
  [ "$(wc -l <"$AWS_STUB_LOG")" -eq 1 ]
}

@test "register-revision: with the platform up, outputs the new revision" {
  service ACTIVE "$TD4" | respond ecs.describe-services -
  registers_td5
  run --separate-stderr "$REGISTER"
  [ "$status" -eq 0 ]
  grep -qx "skipped=false" "$GITHUB_OUTPUT"
  grep -qx "arn=$TD5" "$GITHUB_OUTPUT"
}

@test "register-revision: a permissions error fails, not skips" {
  respond_error ecs.describe-services - 254 "An error occurred (AccessDeniedException)"
  run --separate-stderr "$REGISTER"
  [ "$status" -ne 0 ]
  [[ $stderr == *AccessDeniedException* ]]
  ! grep -q "skipped" "$GITHUB_OUTPUT"
}

@test "roll-service: needs exactly one of image and task-definition" {
  IMAGE="" TASK_DEFINITION="" run --separate-stderr "$ROLL"
  [ "$status" -eq 2 ]
  IMAGE=new@sha256:bbb TASK_DEFINITION=$TD5 run --separate-stderr "$ROLL"
  [ "$status" -eq 2 ]
  [[ $stderr == *"exactly one of image and task-definition"* ]]
  [ ! -s "$AWS_STUB_LOG" ]
}

@test "roll-service: with the platform down, changes nothing and passes" {
  platform_down
  run --separate-stderr "$ROLL"
  [ "$status" -eq 0 ]
  grep -qF "next \`make up\` runs it" "$GITHUB_STEP_SUMMARY"
  ! grep -q "update-service\|register-task-definition" "$AWS_STUB_LOG"
}

@test "roll-service: a permissions error fails, not skips" {
  respond_error ecs.describe-services - 254 "An error occurred (AccessDeniedException)"
  run --separate-stderr "$ROLL"
  [ "$status" -ne 0 ]
  [[ $stderr == *AccessDeniedException* ]]
  ! grep -q "update-service" "$AWS_STUB_LOG"
}

@test "roll-service: from an image, registers a revision and rolls to it" {
  service ACTIVE "$TD4" | respond ecs.describe-services 1
  service ACTIVE "$TD4" | respond ecs.describe-services 2
  registers_td5
  jq -n --argjson d "[$(deployment ecs-svc/2 PRIMARY "$TD5" IN_PROGRESS)]" '{service: {deployments: $d}}' |
    respond ecs.update-service -
  service ACTIVE "$TD5" "[$(deployment ecs-svc/2 PRIMARY "$TD5" COMPLETED)]" | respond ecs.describe-services 3

  run --separate-stderr "$ROLL"
  [ "$status" -eq 0 ]
  grep -qx "arn=$TD5" "$GITHUB_OUTPUT"
  grep -qF "\`identity\` → \`$TD5\`" "$GITHUB_STEP_SUMMARY"
}

@test "roll-service: from a revision, registers nothing" {
  export IMAGE="" TASK_DEFINITION=$TD5
  service ACTIVE "$TD4" | respond ecs.describe-services 1
  jq -n --argjson d "[$(deployment ecs-svc/2 PRIMARY "$TD5" IN_PROGRESS)]" '{service: {deployments: $d}}' |
    respond ecs.update-service -
  service ACTIVE "$TD5" "[$(deployment ecs-svc/2 PRIMARY "$TD5" COMPLETED)]" | respond ecs.describe-services 2

  run --separate-stderr "$ROLL"
  [ "$status" -eq 0 ]
  ! grep -q "register-task-definition\|describe-task-definition" "$AWS_STUB_LOG"
}

@test "roll-service: a rolled-back rollout says the recorded version still names it" {
  export IMAGE="" TASK_DEFINITION=$TD5
  service ACTIVE "$TD4" | respond ecs.describe-services 1
  jq -n --argjson d "[$(deployment ecs-svc/2 PRIMARY "$TD5" IN_PROGRESS)]" '{service: {deployments: $d}}' |
    respond ecs.update-service -
  service ACTIVE "$TD4" "[$(deployment ecs-svc/3 PRIMARY "$TD4" IN_PROGRESS),$(deployment ecs-svc/2 ACTIVE "$TD5" FAILED)]" |
    respond ecs.describe-services -

  run --separate-stderr "$ROLL"
  [ "$status" -ne 0 ]
  [[ $stderr == *"/discordia/prd/identity/image still names the version that failed"* ]]
  [[ $stderr == *"dispatch deploy.yml with the previous release tag"* ]]
  grep -qF "rolled back" "$GITHUB_STEP_SUMMARY"
}

@test "roll-service: a rolled-back rollout restores the previous version" {
  export PREVIOUS=$OLD
  rolled_back
  echo '{"Version":4,"Tier":"Standard"}' | respond ssm.put-parameter -

  run --separate-stderr "$ROLL"
  [ "$status" -ne 0 ]
  grep -qx -- "ssm put-parameter --name /discordia/prd/identity/image --type String --overwrite --value $OLD --output json" "$AWS_STUB_LOG"
  [[ $stderr == *"restored /discordia/prd/identity/image"* ]]
  grep -qF "restored" "$GITHUB_STEP_SUMMARY"
}

@test "roll-service: a restore that cannot be written says the failed version is still recorded" {
  export PREVIOUS=$OLD
  rolled_back
  respond_error ssm.put-parameter - 254 "An error occurred (AccessDeniedException)"

  run --separate-stderr "$ROLL"
  [ "$status" -ne 0 ]
  [[ $stderr == *AccessDeniedException* ]]
  [[ $stderr == *"still names the version that failed"* ]]
}

@test "roll-service: a rollout that times out restores nothing" {
  export PREVIOUS=$OLD ROLL_POLL_ATTEMPTS=2
  rolls_td5_then "[$(deployment ecs-svc/2 PRIMARY "$TD5" IN_PROGRESS)]"

  run --separate-stderr "$ROLL"
  [ "$status" -ne 0 ]
  [[ $stderr == *"ECS may still finish it"* ]]
  ! grep -q "ssm put-parameter" "$AWS_STUB_LOG"
}

@test "roll-service: a deployment something else replaced restores nothing" {
  export PREVIOUS=$OLD
  rolls_td5_then "[$(deployment ecs-svc/9 PRIMARY "$TD4" IN_PROGRESS)]"

  run --separate-stderr "$ROLL"
  [ "$status" -ne 0 ]
  [[ $stderr == *"no longer listed"* ]]
  ! grep -q "ssm put-parameter" "$AWS_STUB_LOG"
}

migrates() { # EXIT_CODE|null STOPPED_REASON [CONTAINER] -- messaging is up, its migration task stops so
  export SERVICE=messaging TASK_DEFINITION=$MESSAGING_TD
  service ACTIVE "$MESSAGING_TD" | respond ecs.describe-services -
  started_task | respond ecs.run-task -
  : | respond ecs.wait -
  stopped_task "${3:-messaging}" "$1" "$2" | respond ecs.describe-tasks -
}

@test "run-once: a command that exits 0 passes and says so" {
  migrates 0 "Essential container in task exited"
  run --separate-stderr "$RUN"
  [ "$status" -eq 0 ]
  grep -qF -- "- \`messaging\`: \`/messaging migrate up\` exited 0; stop reason: Essential container in task exited" "$GITHUB_STEP_SUMMARY"
}

@test "run-once: a command that exits non-zero fails, with its exit code and stop reason in the summary" {
  migrates 1 "Essential container in task exited"
  run --separate-stderr "$RUN"
  [ "$status" -eq 1 ]
  [[ $stderr == *"exited 1"* ]]
  grep -qF -- "- \`messaging\`: \`/messaging migrate up\` **failed**, exit code 1; stop reason: Essential container in task exited" "$GITHUB_STEP_SUMMARY"
}

@test "run-once: a container that never ran fails, with no exit code" {
  migrates null "CannotPullContainerError: pull image manifest has been retried 1 time(s)"
  run --separate-stderr "$RUN"
  [ "$status" -eq 1 ]
  grep -qF "**failed**, exit code none; stop reason: CannotPullContainerError" "$GITHUB_STEP_SUMMARY"
}

@test "run-once: passes the environment through as the container's overrides" {
  export ENVIRONMENT='{"MONGO_URI":"mongodb://10.0.1.23:27017/messaging?replicaSet=rs0"}'
  migrates 0 "Essential container in task exited"
  run --separate-stderr "$RUN"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.overrides.containerOverrides[0].environment' "$BATS_TEST_TMPDIR/run-task.json")" = '[{"name":"MONGO_URI","value":"mongodb://10.0.1.23:27017/messaging?replicaSet=rs0"}]' ]
  [ "$(jq -c '.overrides.containerOverrides[0].command' "$BATS_TEST_TMPDIR/run-task.json")" = '["/messaging","migrate","up"]' ]
}

@test "run-once: with no container named, overrides the one named after the service" {
  export CONTAINER="" ENVIRONMENT=""
  migrates 0 "Essential container in task exited"
  run --separate-stderr "$RUN"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.overrides.containerOverrides[0].name' "$BATS_TEST_TMPDIR/run-task.json")" = messaging ]
  [ "$(jq -c '.overrides.containerOverrides[0].environment' "$BATS_TEST_TMPDIR/run-task.json")" = '[]' ]
}

@test "run-once: a named container is the one overridden and whose exit code counts" {
  export CONTAINER=app
  migrates 0 "Essential container in task exited" app
  run --separate-stderr "$RUN"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.overrides.containerOverrides[0].name' "$BATS_TEST_TMPDIR/run-task.json")" = app ]
}

@test "run-once: with the platform down, runs nothing and passes" {
  # register-revision outputs no arn with the platform down, so task-definition is empty.
  export SERVICE=messaging TASK_DEFINITION=""
  platform_down
  run --separate-stderr "$RUN"
  [ "$status" -eq 0 ]
  grep -qF "\`messaging\`: platform is down; \`/messaging migrate up\` did not run" "$GITHUB_STEP_SUMMARY"
  [ "$(wc -l <"$AWS_STUB_LOG")" -eq 1 ]
  ! grep -q "run-task" "$AWS_STUB_LOG"
}

@test "run-once: a permissions error fails, not skips" {
  export SERVICE=messaging TASK_DEFINITION=$MESSAGING_TD
  respond_error ecs.describe-services - 254 "An error occurred (AccessDeniedException)"
  run --separate-stderr "$RUN"
  [ "$status" -ne 0 ]
  [[ $stderr == *AccessDeniedException* ]]
  ! grep -q "run-task" "$AWS_STUB_LOG"
}

@test "run-once: a running service and no task-definition runs nothing" {
  export SERVICE=messaging TASK_DEFINITION=""
  service ACTIVE "$MESSAGING_TD" | respond ecs.describe-services -
  run --separate-stderr "$RUN"
  [ "$status" -eq 2 ]
  [[ $stderr == *"needs a task-definition"* ]]
  ! grep -q "run-task" "$AWS_STUB_LOG"
}

@test "run-once: a command or environment that is not the right JSON calls nothing" {
  export SERVICE=messaging TASK_DEFINITION=$MESSAGING_TD
  COMMAND='/messaging migrate up' run --separate-stderr "$RUN"
  [ "$status" -eq 2 ]
  [[ $stderr == *"command must be a JSON array of strings"* ]]
  ENVIRONMENT='["MONGO_URI=x"]' run --separate-stderr "$RUN"
  [ "$status" -eq 2 ]
  [[ $stderr == *"environment must be a JSON object"* ]]
  [ ! -s "$AWS_STUB_LOG" ]
}
