#!/usr/bin/env python3
"""Create an encrypted vault file with fresh random secrets for one inventory.

Usage:
    tools/generate-vault.py inventories/<env>/group_vars/all/vault.yml

The vault password is read from ANSIBLE_VAULT_PASSWORD_FILE (default ~/.ansible/ak-vault-pass);
if that file does not exist, a random password is created there (mode 0600).
Only the Python standard library and ansible-vault are used, so it runs on a bare control node.
"""
import base64
import os
import secrets
import string
import subprocess
import sys

ALNUM = string.ascii_letters + string.digits


def pw(length):
    return "".join(secrets.choice(ALNUM) for _ in range(length))


def key32():
    # Base64 of exactly 32 random bytes - Artifact Keeper refuses to start otherwise.
    return base64.b64encode(secrets.token_bytes(32)).decode()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    target = sys.argv[1]
    if os.path.exists(target):
        sys.exit(f"{target} exists - refusing to overwrite (secrets would no longer match the cluster)")

    pass_file = os.path.expanduser(os.environ.get("ANSIBLE_VAULT_PASSWORD_FILE", "~/.ansible/ak-vault-pass"))
    if not os.path.exists(pass_file):
        os.makedirs(os.path.dirname(pass_file), mode=0o700, exist_ok=True)
        fd = os.open(pass_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as fh:
            fh.write(pw(40) + "\n")
        print(f"created vault password file {pass_file} - store it in your password manager")

    # Formats follow the requirements of the respective component (see role defaults).
    values = {
        "vault_patroni_superuser_password": pw(32),
        "vault_patroni_replication_password": pw(32),
        "vault_patroni_app_password": pw(32),
        "vault_garage_rpc_secret": secrets.token_hex(32),
        "vault_garage_admin_token": pw(40),
        "vault_garage_access_key_id": "GK" + secrets.token_hex(12),
        "vault_garage_secret_access_key": secrets.token_hex(32),
        "vault_keepalived_auth_pass": pw(8),
        "vault_artifact_keeper_admin_password": "Ak-" + pw(20) + "!",
        "vault_artifact_keeper_jwt_secret": pw(64),
        "vault_artifact_keeper_webhook_secret_key": key32(),
        "vault_artifact_keeper_migration_encryption_key": key32(),
        "vault_artifact_keeper_sso_encryption_key": key32(),
        # Standalone setup (inventories/standalone); unused values do no harm elsewhere.
        "vault_ak_standalone_db_password": pw(32),
        "vault_artifactory_oss_db_password": pw(32),
        "vault_artifactory_oss_admin_password": "Rt-" + pw(20) + "!",
        # Single sign-on test with Keycloak (playbooks/keycloak.yml).
        "vault_keycloak_admin_password": pw(24),
        "vault_keycloak_client_secret": pw(40),
        "vault_keycloak_test_password": pw(24),
    }
    plain = "---\n# Encrypted secrets, referenced from secrets.yml. Edit with: ansible-vault edit <file>\n"
    plain += "".join(f'{k}: "{v}"\n' for k, v in values.items())

    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    # Password file via environment (not --vault-password-file): passing both would make
    # ansible-vault see two vault IDs when the variable is already exported.
    subprocess.run(
        ["ansible-vault", "encrypt", "--output", target, "-"],
        input=plain.encode(), check=True,
        env=dict(os.environ, ANSIBLE_VAULT_PASSWORD_FILE=pass_file),
    )
    os.chmod(target, 0o600)
    print(f"wrote encrypted {target}")


if __name__ == "__main__":
    main()
