# shellcheck shell=bash
# Shared by every test: a fresh fake `aws` (test/stub/aws), fresh GitHub output files,
# and no waiting between polls.
bats_require_minimum_version 1.5.0

setup_stub() {
  export AWS_STUB_DIR="$BATS_TEST_TMPDIR/aws" AWS_STUB_LOG="$BATS_TEST_TMPDIR/aws.log"
  mkdir -p "$AWS_STUB_DIR"
  : >"$AWS_STUB_LOG"
  export PATH="$BATS_TEST_DIRNAME/stub:$PATH"
  export RUNNER_TEMP="$BATS_TEST_TMPDIR"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github-output"
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/github-summary"
  : >"$GITHUB_OUTPUT"
  : >"$GITHUB_STEP_SUMMARY"
  export ROLL_POLL_SECONDS=0
}

# respond OPERATION N -- stdin answers the Nth call of OPERATION, e.g. ecs.describe-services.
# respond OPERATION - -- stdin answers every call that has no numbered answer.
respond() {
  local file=$AWS_STUB_DIR/$1
  [ "$2" = - ] || file=$file.$2
  cat >"$file.json"
}

# respond_error OPERATION N|- CODE MESSAGE -- that call exits CODE with MESSAGE on stderr.
respond_error() {
  local file=$AWS_STUB_DIR/$1
  [ "$2" = - ] || file=$file.$2
  echo "$3" >"$file.rc"
  printf '%s\n' "$4" >"$file.err"
}

# service STATUS TASK_DEFINITION [DEPLOYMENTS_JSON] -- a describe-services answer for a
# Fargate service named $SERVICE (identity when unset), on its own subnets.
service() {
  jq -n --arg name "${SERVICE:-identity}" --arg status "$1" --arg td "$2" \
    --argjson deployments "${3:-[]}" \
    '{services: [{serviceName: $name, status: $status, taskDefinition: $td,
                  launchType: "FARGATE", platformVersion: "LATEST",
                  networkConfiguration: {awsvpcConfiguration: {
                    subnets: ["subnet-0a1b2c3d", "subnet-4e5f6a7b"],
                    securityGroups: ["sg-0123abcd"], assignPublicIp: "ENABLED"}},
                  deployments: $deployments}], failures: []}'
}

# deployment ID STATUS TASK_DEFINITION ROLLOUT_STATE -- one of a service's deployments.
deployment() {
  jq -nc --arg id "$1" --arg status "$2" --arg td "$3" --arg rollout "$4" \
    '{id: $id, status: $status, taskDefinition: $td, rolloutState: $rollout}'
}

# task_definition CONTAINERS_JSON -- a describe-task-definition answer, at revision 4.
task_definition() {
  jq -n --argjson containers "$1" '{taskDefinition: {
    taskDefinitionArn: "arn:aws:ecs:us-east-1:837111420485:task-definition/identity:4",
    family: "identity", revision: 4, status: "ACTIVE",
    requiresAttributes: [{name: "ecs.capability.execution-role-awslogs"}],
    compatibilities: ["EC2", "FARGATE"], registeredAt: "2026-09-23T10:00:00-03:00",
    registeredBy: "arn:aws:iam::837111420485:user/admin", cpu: "256", memory: "512",
    executionRoleArn: "arn:aws:iam::837111420485:role/discordia-prd-identity-execution",
    containerDefinitions: $containers}}'
}

# shellcheck disable=SC2034 # used by the tests that load this file
ONE_CONTAINER='[{"name":"identity","image":"old@sha256:aaa","environment":[{"name":"PORT","value":"8080"}]}]'
# shellcheck disable=SC2034
TWO_CONTAINERS='[{"name":"app","image":"app@sha256:aaa"},{"name":"log-router","image":"fluent@sha256:ccc"}]'
# shellcheck disable=SC2034
TD4=arn:aws:ecs:us-east-1:837111420485:task-definition/identity:4
# shellcheck disable=SC2034
TD5=arn:aws:ecs:us-east-1:837111420485:task-definition/identity:5
# shellcheck disable=SC2034
MESSAGING_TD=arn:aws:ecs:us-east-1:837111420485:task-definition/messaging:7
# shellcheck disable=SC2034
TASK=arn:aws:ecs:us-east-1:837111420485:task/discordia-prd-cluster/0f1e2d3c4b5a69788796a5b4c3d2e1f0

# started_task -- a run-task answer that started TASK.
started_task() {
  jq -n --arg task "$TASK" '{tasks: [{taskArn: $task, lastStatus: "PROVISIONING"}], failures: []}'
}

# stopped_task CONTAINER EXIT_CODE|null STOPPED_REASON -- a describe-tasks answer: TASK
# stopped, and CONTAINER exited EXIT_CODE (null when it never started).
stopped_task() {
  jq -n --arg task "$TASK" --arg c "$1" --argjson code "$2" --arg reason "$3" \
    '{tasks: [{taskArn: $task, lastStatus: "STOPPED", stopCode: "EssentialContainerExited",
               stoppedReason: $reason,
               containers: [{name: $c, lastStatus: "STOPPED", exitCode: $code}]}],
      failures: []}'
}
