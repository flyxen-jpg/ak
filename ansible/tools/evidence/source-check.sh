#!/bin/bash
# Shows from the public source code why the migration job of Artifact Keeper does not transfer
# users, groups and permissions. Needs git and network access, changes nothing.
#   tools/evidence/source-check.sh [tag] [work directory]
set -euo pipefail
tag=${1:-v1.11.11}
dir=${2:-/var/tmp/ak-source}

if [ ! -d "$dir/.git" ]; then
  git clone --quiet --filter=blob:none --no-checkout https://github.com/artifact-keeper/artifact-keeper.git "$dir"
fi
cd "$dir"
git checkout --quiet "$tag"
echo "Source: $tag, commit $(git rev-parse --short HEAD)"

echo
echo "1. Every occurrence of the three functions. Only the definitions exist, there is no caller."
grep -rnE 'migrate_(users|groups|permissions)\(' --include=*.rs . || true

echo
echo "2. Where the options are read. The server only stores them (models), the CLI only lists."
grep -rnE 'include_(users|groups|permissions)' --include=*.rs backend/src | grep -vE 'assert|test' | cut -d: -f1 | sort | uniq -c

echo
echo "3. The CLI path stops at a placeholder."
grep -nE 'TODO: Create (user|group|permission)' backend/src/cli/migrate_runner.rs

echo
echo "4. The dead code writes to columns and a table that the schema does not define."
grep -nE 'INSERT INTO (users \(username, email, role|groups \(name, description, metadata|repository_permissions)' \
  backend/src/services/migration_worker.rs
grep -rlE 'CREATE TABLE (IF NOT EXISTS )?repository_permissions' backend/migrations || echo "no migration creates repository_permissions"

echo
echo "5. Permission names. The API v2 of Artifactory reports write and manage, which map to nothing."
grep -nA10 'pub fn map_permission' backend/src/services/migration_service.rs

echo
echo "6. REST calls of the client. They answer 400 on JFrog Container Registry and OSS."
grep -nE 'api/(v2/)?security/(users|groups|permissions)"' backend/src/services/artifactory_client.rs

echo
echo "7. Rule model: principal, target and actions, no path pattern."
sed -n '/CREATE TABLE IF NOT EXISTS permissions/,/);/p' backend/migrations/018_groups_permissions.sql

echo
echo "8. Identity provider: a group name outside its namespace is refused."
grep -nE 'ON CONFLICT \(name\) DO UPDATE|WHERE groups.external_source = EXCLUDED' backend/src/api/handlers/sso.rs

echo
echo "9. Identity provider: users are matched by external ID and provider, not by name or e-mail."
grep -nE 'WHERE external_id = \$1 AND auth_provider = \$2' backend/src/services/auth_service.rs
