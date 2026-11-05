#!/usr/bin/env python3
"""Runs a real OpenID Connect login against Artifact Keeper without a browser.

It performs what a browser does: authorization request, login form of the identity provider,
callback to Artifact Keeper and exchange of the one-time code. Then it prints who Artifact
Keeper thinks the user is, including groups, and tries registry pulls with an API token.

    AK_URL=http://10.0.10.250 AK_PUBLIC_URL=http://localhost:30090 IDP_PASSWORD=... \
        oidc-login.py <user> [repository/image:tag ...]

AK_PUBLIC_URL is replaced by AK_URL in redirects, because the configured external address may
only exist on another machine. Only the Python standard library is used.
"""
import html
import http.cookiejar
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

AK_URL = os.environ["AK_URL"].rstrip("/")
PUBLIC_URL = os.environ.get("AK_PUBLIC_URL", AK_URL).rstrip("/")
PASSWORD = os.environ["IDP_PASSWORD"]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(
    NoRedirect, urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
)


def call(url, data=None, headers=None, method=None):
    """Returns status, headers and body. Error statuses are results here, not exceptions."""
    request = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with OPENER.open(request, timeout=60) as response:
            return response.status, response.headers, response.read().decode(errors="replace")
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read().decode(errors="replace")


def api(path, token=None, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    status, _, text = call(AK_URL + path, data, headers)
    try:
        return status, json.loads(text)
    except ValueError:
        return status, text


def local(url):
    return url.replace(PUBLIC_URL, AK_URL, 1)


def login(user):
    status, providers = api("/api/v1/auth/sso/providers")
    oidc = [p for p in providers if p.get("provider_type", p.get("type")) == "oidc"]
    if not oidc:
        sys.exit(f"no OIDC provider enabled: {status} {providers}")
    print("provider:", oidc[0].get("name"))

    status, headers, _ = call(f"{AK_URL}/api/v1/auth/sso/oidc/{oidc[0]['id']}/login")
    if status not in (302, 303, 307):
        sys.exit(f"login start failed: {status}")
    status, _, page = call(headers["Location"])
    form = re.search(r'action="([^"]+)"', page)
    if not form:
        sys.exit(f"no login form from the identity provider: {status} {page[:200]}")

    fields = urllib.parse.urlencode({"username": user, "password": PASSWORD}).encode()
    status, headers, page = call(html.unescape(form.group(1)), fields)
    if status not in (302, 303):
        sys.exit(f"identity provider refused the login: {status}")

    status, headers, body = call(local(headers["Location"]))
    target = headers.get("Location", "")
    print("callback:", status, re.sub(r"(code|token)=[^&]+", r"\1=***", target)[:150])
    if status not in (302, 303, 307):
        sys.exit(f"callback failed: {body[:300]}")
    query = urllib.parse.parse_qs(urllib.parse.urlparse(target).query)
    if "error" in query or "code" not in query:
        sys.exit(f"login refused by Artifact Keeper: {query}")
    status, tokens = api("/api/v1/auth/sso/exchange", body={"code": query["code"][0]})
    if status != 200:
        sys.exit(f"exchange failed: {status} {tokens}")
    return tokens["access_token"]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    user = sys.argv[1]
    token = login(user)
    _, me = api("/api/v1/auth/me", token)
    print("user:", {k: me.get(k) for k in ("id", "username", "email", "is_admin", "auth_provider", "must_change_password")})
    for name in ("groups", "permissions"):
        if name in me:
            print(name + ":", me[name])

    status, created = api(
        f"/api/v1/users/{me['id']}/tokens", token,
        {"name": "oidc-test-" + str(os.getpid()), "scopes": ["read:artifacts", "write:artifacts"], "expires_in_days": 1},
    )
    print("api token:", status, created.get("token", "")[:6] + "***" if status in (200, 201) else created)
    if status in (200, 201):
        with open(os.path.expanduser(f"~/.oidc-token-{user}"), "w", opener=lambda p, f: os.open(p, f, 0o600)) as fh:
            fh.write(created["token"])


if __name__ == "__main__":
    main()
