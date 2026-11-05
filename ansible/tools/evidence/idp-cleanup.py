#!/usr/bin/env python3
"""Removes migrated local users and groups before an identity provider takes over.

A local user blocks the federated login with the same name (HTTP 409), and a local group
blocks the federated membership. Only names given on the command line are removed. The built-in
admin account is refused. Rules of removed principals are listed before anything is deleted.

    AK_URL=http://10.0.10.250 AK_ADMIN_PASSWORD=... idp-cleanup.py --users a,b --groups x,y [--apply]

Without --apply nothing is changed.
"""
import argparse
import json
import os
import urllib.error
import urllib.request

AK_URL = os.environ["AK_URL"].rstrip("/")


def api(path, token=None, body=None, method=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(AK_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            text = response.read().decode()
            return response.status, json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode(errors="replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--users", default="")
    parser.add_argument("--groups", default="")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    _, login = api("/api/v1/auth/login", body={"username": "admin", "password": os.environ["AK_ADMIN_PASSWORD"]})
    token = login["access_token"]
    users = {u["username"]: u["id"] for u in api("/api/v1/users?per_page=500", token)[1]["items"]}
    groups = {g["name"]: g["id"] for g in api("/api/v1/groups?per_page=500", token)[1]["items"]}
    rules = api("/api/v1/permissions?per_page=500", token)[1]["items"]

    for kind, wanted, known in (("users", args.users, users), ("groups", args.groups, groups)):
        for name in filter(None, wanted.split(",")):
            if name == "admin":
                raise SystemExit("the built-in admin account is not removed")
            if name not in known:
                print(f"{kind} {name}: not present")
                continue
            attached = [r for r in rules if r["principal_id"] == known[name]]
            print(f"{kind} {name}: {len(attached)} rules attached")
            if args.apply:
                # Artifact Keeper keeps the rules of a deleted user or group (found in the lab),
                # so they are removed first and created again for the federated group.
                for rule in attached:
                    api(f"/api/v1/permissions/{rule['id']}", token, method="DELETE")
                status, result = api(f"/api/v1/{kind}/{known[name]}", token, method="DELETE")
                print(f"  deleted: {status} {result if status >= 400 else ''}")

    remaining = api("/api/v1/permissions?per_page=500", token)[1]["items"]
    known_ids = {u["id"] for u in api("/api/v1/users?per_page=500", token)[1]["items"]}
    known_ids |= {g["id"] for g in api("/api/v1/groups?per_page=500", token)[1]["items"]}
    orphans = [r for r in remaining if r["principal_id"] not in known_ids]
    print(f"rules now: {len(remaining)}, without an existing principal: {len(orphans)}")


if __name__ == "__main__":
    main()
