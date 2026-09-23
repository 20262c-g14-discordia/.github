#!/usr/bin/env bash
# The build-push action's checks and bookkeeping; the build itself is
# docker/build-push-action in action.yml.
#
#   build-push.sh check-tag TAG
#       Exits 0 only for a release-please tag, <component>-v<major>.<minor>.<patch>.
#       Deploys run from releases, never from a branch (ADR-0009).
#   build-push.sh record IMAGE REGISTRY DIGEST TAG
#       Writes REGISTRY/discordia/IMAGE@DIGEST to /discordia/prd/image/IMAGE, the version
#       the platform runs, and to the step output `image`. Refuses a missing or malformed
#       digest, so the version can never point at nothing.
set -euo pipefail

case ${1:-} in
  check-tag)
    if ! [[ ${2:-} =~ ^[a-z0-9]+(-[a-z0-9]+)*-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "::error::'${2:-}' is not a release tag like identity-v1.2.3; deploys run from releases only (ADR-0009)" >&2
      exit 1
    fi
    ;;
  record)
    image=$2 registry=$3 digest=$4 tag=$5
    if ! [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
      echo "::error::no usable digest for $image:$tag ('$digest'); the version was not recorded" >&2
      exit 1
    fi
    ref=$registry/discordia/$image@$digest
    aws ssm put-parameter --name "/discordia/prd/image/$image" --type String --overwrite \
      --value "$ref" --output json >/dev/null
    echo "image=$ref" >>"$GITHUB_OUTPUT"
    echo "- \`$image\` $tag → \`$ref\`" >>"$GITHUB_STEP_SUMMARY"
    ;;
  *)
    echo "usage: build-push.sh check-tag TAG | record IMAGE REGISTRY DIGEST TAG" >&2
    exit 2
    ;;
esac
