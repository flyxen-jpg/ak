-- Shows from the running database what the migration job really did. Run on the Patroni leader:
--   sudo -u postgres psql -d artifact_keeper -f database-check.sql
-- The INSERT statements are copied from migration_worker.rs. They run in a transaction that
-- is rolled back and each one is expected to fail, so nothing is changed.
\set ON_ERROR_STOP off
\pset pager off

\echo '1. Columns of users that the dead code would write (role, status, metadata): none exist'
SELECT column_name FROM information_schema.columns
 WHERE table_name = 'users' AND column_name IN ('role', 'status', 'metadata');

\echo '2. User insert of migrate_users'
BEGIN;
INSERT INTO users (username, email, role, status, metadata)
VALUES ('evidence', 'evidence@lab.local', 'user', 'active', '{}');
ROLLBACK;

\echo '3. Group insert of migrate_groups'
BEGIN;
INSERT INTO groups (name, description, metadata) VALUES ('evidence', 'evidence', '{}');
ROLLBACK;

\echo '4. Target table of migrate_permissions: NULL means it does not exist'
SELECT to_regclass('public.repository_permissions') AS repository_permissions;

\echo '5. Item types of all migration jobs: only artifact items were ever created'
SELECT item_type, status, count(*) FROM migration_items GROUP BY 1, 2 ORDER BY 1, 2;

\echo '6. Options stored with the jobs compared with what they did'
SELECT j.id, j.status, j.config->>'include_users' AS users, j.config->>'include_groups' AS groups,
       j.config->>'include_permissions' AS permissions, j.total_items
  FROM migration_jobs j ORDER BY j.created_at;

\echo '7. Rules: the effective model of Artifact Keeper'
SELECT p.principal_type, coalesce(g.name, u.username) AS principal, r.key AS repository, p.actions
  FROM permissions p
  LEFT JOIN groups g ON p.principal_type = 'group' AND g.id = p.principal_id
  LEFT JOIN users u ON p.principal_type = 'user' AND u.id = p.principal_id
  LEFT JOIN repositories r ON r.id = p.target_id
 WHERE r.key LIKE 'docker-%' ORDER BY 3, 2;

\echo '8. Visibility of the migrated repositories'
SELECT key, repo_type, visibility FROM repositories ORDER BY key;
