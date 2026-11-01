#!/usr/bin/env python3
"""
Convert a Keycloak user export into a CSV for Moodle's "Upload users" tool.

Standard library only — no pip install, runs anywhere Python 3.8+ does.

INPUT
-----
Accepts either shape of Keycloak JSON:

  1. Admin REST API:  GET /admin/realms/{realm}/users
     -> a bare JSON array of user objects.
     NOTE: this endpoint does NOT include group membership. Supply it
     separately with --groups.

  2. Offline export:  kc.sh export ...
     -> realm-users-0.json, shaped {"realm": "...", "users": [...]}.
     These user objects DO usually carry a "groups" list, so --groups is
     not needed.

The optional --groups file maps groups to members. Either shape works:

  {"staff": ["alice", "bob"], "students-2026": ["carol"]}

  [{"name": "staff", "members": [{"username": "alice"}, {"username": "bob"}]}]

The second is close to what you get from looping over
GET /admin/realms/{realm}/groups and then
GET /admin/realms/{realm}/groups/{id}/members

OUTPUT
------
CSV with: username, firstname, lastname, email, auth, cohort1..cohortN

Moodle matches an incoming OAuth2 login to an existing account by email, so
users without an email address are skipped — importing them would create
accounts that can never be linked.

USAGE
-----
  python keycloak_to_moodle_csv.py users.json -o moodle-users.csv
  python keycloak_to_moodle_csv.py users.json --groups groups.json -o out.csv
  python keycloak_to_moodle_csv.py users.json --group-mode path --include-disabled
"""

import argparse
import csv
import json
import re
import sys
from collections import defaultdict

# Moodle lowercases usernames and, unless extendedusernamechars is enabled,
# permits only these characters.
MOODLE_USERNAME_OK = re.compile(r"^[a-z0-9._@-]+$")


def load_users(path):
    """Return the list of user dicts from either accepted input shape."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    if isinstance(data, list):
        return data
    if isinstance(data, dict) and isinstance(data.get("users"), list):
        return data["users"]

    sys.exit(
        f"{path}: expected a JSON array of users, or an object with a "
        f'"users" array. Got {type(data).__name__}.'
    )


def load_group_map(path):
    """Return {username: [group, ...]} from either accepted --groups shape."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    by_user = defaultdict(list)

    if isinstance(data, dict):
        # {"staff": ["alice", "bob"], ...}
        for group, members in data.items():
            for m in members:
                username = m.get("username") if isinstance(m, dict) else m
                if username:
                    by_user[username].append(group)

    elif isinstance(data, list):
        # [{"name": "staff", "members": [{"username": "alice"}]}, ...]
        for entry in data:
            if not isinstance(entry, dict):
                continue
            group = entry.get("name") or entry.get("path") or entry.get("group")
            for m in entry.get("members", []):
                username = m.get("username") if isinstance(m, dict) else m
                if group and username:
                    by_user[username].append(group)
    else:
        sys.exit(f"{path}: unrecognised --groups format.")

    return by_user


def cohort_name(group_path, mode):
    """
    Turn a Keycloak group into a Moodle cohort name.

    Keycloak group paths look like "/staff" or "/staff/admins".
      mode=last  -> "admins"        (just the leaf)
      mode=path  -> "staff-admins"  (full path, flattened)
    """
    parts = [p for p in str(group_path).strip("/").split("/") if p]
    if not parts:
        return None
    return parts[-1] if mode == "last" else "-".join(parts)


def main():
    ap = argparse.ArgumentParser(
        description="Convert Keycloak user JSON to a Moodle upload CSV.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("users_json", help="Keycloak users JSON (API array or realm export)")
    ap.add_argument("-o", "--output", default="moodle-users.csv", help="CSV to write")
    ap.add_argument(
        "--groups",
        help="Optional JSON mapping groups to members (needed for REST API input)",
    )
    ap.add_argument(
        "--auth",
        default="oauth2",
        help="Moodle auth method for every row (default: oauth2). "
        "Use 'manual' if you want local passwords instead.",
    )
    ap.add_argument(
        "--group-mode",
        choices=["last", "path"],
        default="last",
        help="How to flatten nested Keycloak group paths (default: last)",
    )
    ap.add_argument(
        "--cohort-prefix",
        default="",
        help="Prepended to every cohort name, e.g. 'kc-'",
    )
    ap.add_argument(
        "--include-disabled",
        action="store_true",
        help="Include users with enabled=false (skipped by default)",
    )
    ap.add_argument(
        "--include-service-accounts",
        action="store_true",
        help="Include service-account-* users (skipped by default)",
    )
    args = ap.parse_args()

    users = load_users(args.users_json)
    group_map = load_group_map(args.groups) if args.groups else {}

    rows = []
    seen_emails = {}
    skipped = defaultdict(int)
    warnings = []

    for u in users:
        username = (u.get("username") or "").strip()
        if not username:
            skipped["no username"] += 1
            continue

        if not args.include_service_accounts and username.startswith("service-account-"):
            skipped["service account"] += 1
            continue

        if not args.include_disabled and u.get("enabled") is False:
            skipped["disabled in Keycloak"] += 1
            continue

        email = (u.get("email") or "").strip().lower()
        if not email:
            skipped["no email address"] += 1
            continue

        # Moodle matches OAuth2 logins on email, so a duplicate would collide
        # with an account already in the file.
        if email in seen_emails:
            skipped["duplicate email"] += 1
            warnings.append(
                f"{username}: email {email} already used by {seen_emails[email]} - skipped"
            )
            continue
        seen_emails[email] = username

        first = (u.get("firstName") or "").strip()
        last = (u.get("lastName") or "").strip()
        if not first or not last:
            # Moodle's upload tool rejects rows missing either name.
            skipped["missing first or last name"] += 1
            warnings.append(f"{username}: missing firstName/lastName - skipped")
            continue

        username_lc = username.lower()
        if not MOODLE_USERNAME_OK.match(username_lc):
            warnings.append(
                f"{username}: contains characters Moodle may reject; "
                f"enable extendedusernamechars or rename in Keycloak"
            )

        # Group membership: on the user object (offline export) or from --groups.
        raw_groups = u.get("groups") or group_map.get(username) or []
        cohorts = []
        for g in raw_groups:
            name = cohort_name(g, args.group_mode)
            if name:
                full = f"{args.cohort_prefix}{name}"
                if full not in cohorts:
                    cohorts.append(full)

        rows.append(
            {
                "username": username_lc,
                "firstname": first,
                "lastname": last,
                "email": email,
                "auth": args.auth,
                "_cohorts": cohorts,
            }
        )

    if not rows:
        sys.exit("No users survived filtering — nothing written. See the summary above.")

    max_cohorts = max(len(r["_cohorts"]) for r in rows)
    fieldnames = ["username", "firstname", "lastname", "email", "auth"]
    fieldnames += [f"cohort{i}" for i in range(1, max_cohorts + 1)]

    with open(args.output, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for r in rows:
            out = {k: r[k] for k in ("username", "firstname", "lastname", "email", "auth")}
            for i, c in enumerate(r["_cohorts"], start=1):
                out[f"cohort{i}"] = c
            writer.writerow(out)

    # Summary to stderr so stdout stays clean if anyone pipes this.
    print(f"Wrote {len(rows)} users to {args.output}", file=sys.stderr)
    print(f"Cohort columns: {max_cohorts}", file=sys.stderr)
    if skipped:
        print("Skipped:", file=sys.stderr)
        for reason, n in sorted(skipped.items(), key=lambda kv: -kv[1]):
            print(f"  {n:5d}  {reason}", file=sys.stderr)
    if warnings:
        print(f"\n{len(warnings)} warning(s):", file=sys.stderr)
        for w in warnings[:20]:
            print(f"  - {w}", file=sys.stderr)
        if len(warnings) > 20:
            print(f"  ... and {len(warnings) - 20} more", file=sys.stderr)


if __name__ == "__main__":
    main()
