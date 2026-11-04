#!/usr/bin/env bash
source /tmp/rtui.sh; rt_login >/dev/null
for body in '{"groupName":"developers","description":"Entwickler","autoJoin":false,"adminPrivileges":false}' \
            '{"group_name":"developers","description":"Entwickler"}' \
            '{"group":{"name":"developers","description":"Entwickler"}}'; do
  echo "== Gruppe: $body"; rt_send POST access/api/ui/groups "$body" | tr -d '\n'; echo
done
for sel in '[{"repoKey":"maven-releases","type":"local"},{"repoKey":"maven-snapshots","type":"local"},{"repoKey":"maven-central","type":"remote"}]' \
           '["maven-releases","maven-snapshots","maven-central"]'; do
  echo "== Virtual: $sel"
  rt_send POST ui/admin/repositories "{\"type\":\"virtualRepoConfig\",\"general\":{\"repoKey\":\"maven-all\"},
   \"basic\":{\"layout\":\"maven-2-default\",\"includesPattern\":\"**/*\",\"excludesPattern\":\"\",\"selectedRepositories\":$sel,\"repositories\":$sel},
   \"advanced\":{\"retrieveRemoteArtifacts\":true,\"hideUnauthorizedResources\":false,\"signedUrlTtl\":90,\"priorityResolution\":false},
   \"typeSpecific\":{\"repoType\":\"Maven\",\"pomCleanupPolicy\":\"discard_active_reference\",\"forceMavenAuthentication\":false}}" | tr -d '\n'; echo
done
