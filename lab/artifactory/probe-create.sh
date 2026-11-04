#!/usr/bin/env bash
cd /tmp; source /tmp/rtui.sh
until curl -fs http://localhost:8082/router/api/v1/system/health >/dev/null; do sleep 5; done
echo "login $(rt_login)"
rt_get ui/admin/repositories/defaultvalues | jq -c '.defaultModels | {localBasic, localAdvanced, maven, generic}' | head -c 1500; echo
echo "== Versuch: lokales Maven-Repo"
rt_send POST ui/admin/repositories '{
  "type":"localRepoConfig",
  "general":{"repoKey":"probe-maven"},
  "basic":{"layout":"maven-2-default","includesPattern":"**/*","excludesPattern":""},
  "advanced":{"blackedOut":false,"allowContentBrowsing":false,"propertySets":[]},
  "typeSpecific":{"repoType":"Maven","handleReleases":true,"handleSnapshots":false,"suppressPomConsistencyChecks":false,"maxUniqueSnapshots":0,"snapshotVersionBehavior":"UNIQUE","localChecksumPolicy":"CLIENT"}
}'
rt_get ui/admin/repositories/local/info | jq -c '[.[].repoKey]'
