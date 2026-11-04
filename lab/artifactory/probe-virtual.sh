#!/usr/bin/env bash
source /tmp/rtui.sh; rt_login >/dev/null
rt_send POST ui/admin/repositories '{"type":"virtualRepoConfig","general":{"repoKey":"maven-all"},
 "basic":{"layout":"maven-2-default","includesPattern":"**/*","excludesPattern":"","selectedRepositories":[
   {"repoName":"maven-releases","type":"local"},{"repoName":"maven-snapshots","type":"local"},{"repoName":"maven-central","type":"remote"}],
   "defaultDeploymentRepo":"maven-releases"},
 "advanced":{"retrieveRemoteArtifacts":true,"hideUnauthorizedResources":false,"signedUrlTtl":90,"priorityResolution":false},
 "typeSpecific":{"repoType":"Maven","pomCleanupPolicy":"discard_active_reference","forceMavenAuthentication":false}}' | tr -d '\n'; echo
for p in junit/junit/4.13.2/junit-4.13.2.jar org/apache/commons/commons-lang3/3.17.0/commons-lang3-3.17.0.jar \
         org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar com/example/core/1.0.0/core-1.0.0.pom; do
  echo "   $(curl -s -o /dev/null -w '%{http_code}' -u admin:password "http://localhost:8082/artifactory/maven-all/$p")  maven-all/$p"
done
