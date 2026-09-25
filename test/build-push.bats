setup() {
  load helpers
  setup_stub
  SCRIPT=$BATS_TEST_DIRNAME/../actions/build-push/build-push.sh
  REGISTRY=837111420485.dkr.ecr.us-east-1.amazonaws.com
  DIGEST=sha256:$(printf 'a%.0s' {1..64})
}

@test "check-tag accepts release-please tags" {
  for tag in identity-v0.4.0 api-gateway-v1.10.0 messaging-centrifugo-v0.1.12; do
    run "$SCRIPT" check-tag "$tag"
    [ "$status" -eq 0 ] || { echo "refused $tag"; return 1; }
  done
}

@test "check-tag refuses anything that is not a release tag" {
  for tag in main v0.4.0 identity-v0.4 refs/tags/identity-v0.4.0 'identity-v0.4.0;id' 'Identity-v0.4.0' ''; do
    run --separate-stderr "$SCRIPT" check-tag "$tag"
    [ "$status" -ne 0 ] || { echo "accepted '$tag'"; return 1; }
  done
  [[ $stderr == *"not a release tag"* ]]
}

previous_is() { # the get-parameter answer: what the parameter named before this release
  jq -n --arg v "$1" '{Parameter: {Name: "/discordia/prd/identity/image", Type: "String", Value: $v}}'
}

@test "record writes the digest reference to the image's parameter" {
  previous_is "$REGISTRY/discordia/identity@sha256:$(printf 'b%.0s' {1..64})" | respond ssm.get-parameter -
  echo '{"Version":3,"Tier":"Standard"}' | respond ssm.put-parameter -
  ref=$REGISTRY/discordia/identity@$DIGEST

  run --separate-stderr "$SCRIPT" record identity "$REGISTRY" "$DIGEST" identity-v0.4.0
  [ "$status" -eq 0 ]
  grep -qx -- "ssm put-parameter --name /discordia/prd/identity/image --type String --overwrite --value $ref --output json" "$AWS_STUB_LOG"
  grep -qx "image=$ref" "$GITHUB_OUTPUT"
  grep -qF "identity-v0.4.0" "$GITHUB_STEP_SUMMARY"
}

@test "record writes nothing without a well-formed digest" {
  for digest in "" sha256:abc "sha256:$(printf 'A%.0s' {1..64})" "md5:$(printf 'a%.0s' {1..64})"; do
    run --separate-stderr "$SCRIPT" record identity "$REGISTRY" "$digest" identity-v0.4.0
    [ "$status" -ne 0 ] || { echo "accepted '$digest'"; return 1; }
    [[ $stderr == *"no usable digest"* ]] || { echo "wrong failure for '$digest': $stderr"; return 1; }
  done
  [ ! -s "$AWS_STUB_LOG" ]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "record fails when the parameter cannot be written" {
  previous_is unreleased | respond ssm.get-parameter -
  respond_error ssm.put-parameter - 254 "An error occurred (AccessDeniedException)"
  run --separate-stderr "$SCRIPT" record identity "$REGISTRY" "$DIGEST" identity-v0.4.0
  [ "$status" -ne 0 ]
  [[ $stderr == *AccessDeniedException* ]]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "record outputs the value it replaced, so a rollback can restore it" {
  old=$REGISTRY/discordia/identity@sha256:$(printf 'b%.0s' {1..64})
  previous_is "$old" | respond ssm.get-parameter -
  echo '{"Version":3,"Tier":"Standard"}' | respond ssm.put-parameter -

  run --separate-stderr "$SCRIPT" record identity "$REGISTRY" "$DIGEST" identity-v0.4.0
  [ "$status" -eq 0 ]
  grep -qx -- "ssm get-parameter --name /discordia/prd/identity/image --output json" "$AWS_STUB_LOG"
  grep -qx "previous=$old" "$GITHUB_OUTPUT"
}

@test "record with no parameter yet outputs an empty previous" {
  respond_error ssm.get-parameter - 254 \
    "An error occurred (ParameterNotFound) when calling the GetParameter operation: "
  echo '{"Version":1,"Tier":"Standard"}' | respond ssm.put-parameter -

  run --separate-stderr "$SCRIPT" record identity "$REGISTRY" "$DIGEST" identity-v0.4.0
  [ "$status" -eq 0 ]
  grep -qx "previous=" "$GITHUB_OUTPUT"
  grep -q "ssm put-parameter" "$AWS_STUB_LOG"
}

@test "record writes nothing when it cannot read what it replaces" {
  respond_error ssm.get-parameter - 254 "An error occurred (AccessDeniedException)"

  run --separate-stderr "$SCRIPT" record identity "$REGISTRY" "$DIGEST" identity-v0.4.0
  [ "$status" -ne 0 ]
  [[ $stderr == *AccessDeniedException* ]]
  ! grep -q "ssm put-parameter" "$AWS_STUB_LOG"
  [ ! -s "$GITHUB_OUTPUT" ]
}
