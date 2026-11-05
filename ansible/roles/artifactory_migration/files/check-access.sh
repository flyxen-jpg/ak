#!/bin/bash
# Tries one registry operation as one user and prints ALLOW or DENY.
#   CHECK_PASSWORD=... check-access.sh <registry> <user> <pull|push> <repository/image:tag> <archive> <work directory>
# A push sends a small local image to a tag of its own, so existing images stay untouched.
set -uo pipefail
registry=$1 user=$2 action=$3 ref=$4 archive=$5 work=$6

auth=$(mktemp -p "$work")
trap 'rm -f "$auth"' EXIT
printf '{"auths":{"%s":{"auth":"%s"}}}' "$registry" "$(printf '%s:%s' "$user" "$CHECK_PASSWORD" | base64 -w0)" > "$auth"

if [ "$action" = pull ]; then
  output=$(skopeo inspect --raw --tls-verify=false --authfile "$auth" "docker://$registry/$ref" 2>&1 >/dev/null)
else
  output=$(skopeo copy --quiet --retry-times=0 --dest-tls-verify=false --dest-authfile "$auth" \
    "oci-archive:$archive" "docker://$registry/$ref" 2>&1)
fi
if [ $? -eq 0 ]; then
  echo ALLOW
else
  echo "DENY ${output: -110}"
fi
