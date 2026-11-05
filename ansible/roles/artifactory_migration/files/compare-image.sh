#!/bin/bash
# Compares one image in the source registry with its copy in Artifact Keeper.
#   compare-image.sh <source reference> <target reference> <auth file> <work directory>
# The manifest digest proves the same content and tag. The full copy into a directory then
# makes the target deliver every platform and layer, and skopeo checks each blob against its
# digest. Prints one result line and always exits 0, so the caller can list all differences.
set -uo pipefail
source_ref=$1 target_ref=$2 auth=$3 work=$4

digest() {
  skopeo inspect --raw --tls-verify=false --authfile "$auth" "docker://$1" | sha256sum | cut -d' ' -f1
}

source_digest=$(digest "$source_ref")
target_digest=$(digest "$target_ref")
if [ "$source_digest" != "$target_digest" ]; then
  echo "DIFFERENT $target_ref source=$source_digest target=$target_digest"
  exit 0
fi

target_dir=$(mktemp -d -p "$work")
trap 'rm -rf "$target_dir"' EXIT
if error=$(skopeo copy --quiet --multi-arch=all --src-tls-verify=false --src-authfile "$auth" \
  "docker://$target_ref" "dir:$target_dir" 2>&1); then
  echo "IDENTICAL $target_ref sha256:$target_digest $(du -sm "$target_dir" | cut -f1)MB"
else
  echo "BROKEN $target_ref ${error:0:200}"
fi
