setup() {
  load helpers
  setup_stub
  REGISTER=$BATS_TEST_DIRNAME/../actions/register-revision/register-revision.sh
  ROLL=$BATS_TEST_DIRNAME/../actions/roll-service/roll-service.sh
  export CLUSTER=discordia-prd-cluster SERVICE=identity IMAGE=new@sha256:bbb
  export TASK_DEFINITION="" CONTAINER="" PREVIOUS=""
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
