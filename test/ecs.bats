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
