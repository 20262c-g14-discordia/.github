setup() {
  load helpers
  setup_stub
}

@test "the stub answers a numbered call before the catch-all" {
  echo '{"n":1}' | respond ecs.describe-services 1
  echo '{"n":"any"}' | respond ecs.describe-services -
  run aws ecs describe-services --cluster c --services s --output json
  [ "$output" = '{"n":1}' ]
  run aws ecs describe-services --cluster c --services s --output json
  [ "$output" = '{"n":"any"}' ]
}

@test "the stub records every call's arguments" {
  echo '{}' | respond ssm.put-parameter -
  aws ssm put-parameter --name /x --value y
  [ "$(cat "$AWS_STUB_LOG")" = "ssm put-parameter --name /x --value y" ]
}

@test "the stub fails a call it has no answer for" {
  run --separate-stderr aws ecs update-service --service s
  [ "$status" -eq 97 ]
  [[ $stderr == *"no answer for call 1 of ecs.update-service"* ]]
}

@test "the stub returns an answer's exit code and stderr" {
  respond_error ecs.describe-services - 254 "An error occurred (ClusterNotFoundException)"
  run --separate-stderr aws ecs describe-services --cluster c --services s
  [ "$status" -eq 254 ]
  [ "$stderr" = "An error occurred (ClusterNotFoundException)" ]
}
