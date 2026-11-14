"""Cleans up Firestore data left behind by accounts deleted in the Firebase
Console.

Deleting a user from the console's Authentication tab removes only the
sign-in account. This zero-cost project has no Cloud Function to react to
that, so the rest stays behind: the `usernames/{name}` claim (the name can
never be taken again), the `users/{uid}` doc and everything under it (and
since that doc keeps `usernameLower`, the person still shows up in user
search), and their `follows` docs.

The app's own Delete Account (AccountDeletionService.deleteAccount) removes
all of that. This script does the same for accounts that no longer exist in
Firebase Authentication:

  1. Collects every uid the data mentions: each `usernames` doc's uid, each
     `users/{uid}` doc (including ones that only have subcollections left),
     and both sides of each `follows` doc.
  2. Asks Firebase Authentication which of those uids still exist.
  3. For each uid that doesn't: deletes its `usernames` docs, its `follows`
     docs (both directions) and the whole `users/{uid}` tree.

Like the in-app deletion, it leaves likes/comments the user left on other
people's posts.

Dry run by default: it lists what it would delete and changes nothing. Pass
--apply to delete.

    cd backend
    venv\\Scripts\\python scripts\\cleanup_deleted_accounts.py
    venv\\Scripts\\python scripts\\cleanup_deleted_accounts.py --apply

Credentials: --key, else FIREBASE_CREDENTIAL_PATH, else
backend/serviceAccountKey.json.
"""
from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable

BACKEND_DIR = Path(__file__).resolve().parent.parent

# Firebase Authentication's get_users takes at most 100 identifiers per call.
AUTH_LOOKUP_BATCH = 100


@dataclass
class Orphan:
    """Everything left behind by one uid that's gone from Authentication."""

    uid: str
    usernames: list[str] = field(default_factory=list)  # usernames doc ids
    follow_ids: list[str] = field(default_factory=list)  # follows doc ids
    has_user_tree: bool = False  # users/{uid} or anything under it


@dataclass
class Scan:
    orphans: list[Orphan]
    checked_uids: int
    # usernames docs with no uid field — can't be tied to an account, so
    # they're only reported.
    malformed_usernames: list[str]


def find_orphans(db, existing_uids: Callable[[list[str]], set[str]]) -> Scan:
    """Finds data whose uid no longer exists in Authentication.

    [existing_uids] gets a list of uids and returns the ones that still
    exist; it raises if Authentication can't be asked, so nothing is ever
    treated as deleted because of a failed lookup.
    """
    username_owner: dict[str, str] = {}
    malformed: list[str] = []
    for doc in db.collection("usernames").stream():
        uid = (doc.to_dict() or {}).get("uid")
        if isinstance(uid, str) and uid:
            username_owner[doc.id] = uid
        else:
            malformed.append(doc.id)

    # list_documents also returns "missing" parents — a users/{uid} whose
    # own doc is gone but which still has subcollections under it.
    user_tree_uids = {ref.id for ref in db.collection("users").list_documents()}

    follows: list[tuple[str, str | None, str | None]] = []
    for doc in db.collection("follows").stream():
        data = doc.to_dict() or {}
        follows.append((doc.id, data.get("followerUid"), data.get("followingUid")))

    candidates = set(username_owner.values()) | user_tree_uids
    for _, follower, following in follows:
        candidates.update(u for u in (follower, following) if isinstance(u, str) and u)

    ordered = sorted(candidates)
    alive: set[str] = set()
    for i in range(0, len(ordered), AUTH_LOOKUP_BATCH):
        alive |= existing_uids(ordered[i : i + AUTH_LOOKUP_BATCH])

    orphans = {uid: Orphan(uid) for uid in ordered if uid not in alive}
    for name, uid in sorted(username_owner.items()):
        if uid in orphans:
            orphans[uid].usernames.append(name)
    for doc_id, follower, following in follows:
        for uid in {follower, following}:
            if uid in orphans:
                orphans[uid].follow_ids.append(doc_id)
    for uid in user_tree_uids:
        if uid in orphans:
            orphans[uid].has_user_tree = True

    return Scan(
        orphans=list(orphans.values()),
        checked_uids=len(ordered),
        malformed_usernames=sorted(malformed),
    )


def delete_orphan(db, orphan: Orphan) -> None:
    """Deletes what [orphan] left behind. The users/{uid} tree goes last, as
    in the app, so a failure part-way leaves the uid findable on a re-run."""
    batch = db.batch()
    writes = 0
    for name in orphan.usernames:
        batch.delete(db.collection("usernames").document(name))
        writes += 1
    # A follow between two deleted accounts is listed under both.
    for doc_id in dict.fromkeys(orphan.follow_ids):
        batch.delete(db.collection("follows").document(doc_id))
        writes += 1
        if writes >= 400:  # Firestore batches hold at most 500 writes
            batch.commit()
            batch, writes = db.batch(), 0
    if writes:
        batch.commit()
    if orphan.has_user_tree:
        db.recursive_delete(db.collection("users").document(orphan.uid))


def describe(orphan: Orphan) -> str:
    parts = []
    if orphan.usernames:
        parts.append("username " + ", ".join(f"@{n}" for n in orphan.usernames))
    if orphan.has_user_tree:
        parts.append("users/ doc and data")
    if orphan.follow_ids:
        n = len(set(orphan.follow_ids))
        parts.append(f"{n} follow{'s' if n != 1 else ''}")
    return f"{orphan.uid}: " + "; ".join(parts)


def run(db, existing_uids, apply: bool, out=print) -> Scan:
    scan = find_orphans(db, existing_uids)
    out(f"Checked {scan.checked_uids} uid(s) against Firebase Authentication.")
    for name in scan.malformed_usernames:
        out(f"  ! usernames/{name} has no uid - left as is")
    if not scan.orphans:
        out("Nothing left behind by deleted accounts.")
        return scan

    out(f"{len(scan.orphans)} deleted account(s) still have data:")
    for orphan in scan.orphans:
        out("  - " + describe(orphan))

    if not apply:
        out("Dry run: nothing was deleted. Re-run with --apply to delete the above.")
        return scan

    for orphan in scan.orphans:
        delete_orphan(db, orphan)
        out(f"  deleted {orphan.uid}")
    out(f"Done: cleaned up {len(scan.orphans)} account(s).")
    return scan


def _auth_lookup(auth_module) -> Callable[[list[str]], set[str]]:
    def existing(uids: list[str]) -> set[str]:
        result = auth_module.get_users([auth_module.UidIdentifier(u) for u in uids])
        return {user.uid for user in result.users}

    return existing


def _credential_path(arg: str | None) -> Path:
    if arg:
        return Path(arg)
    env = os.getenv("FIREBASE_CREDENTIAL_PATH")
    return Path(env) if env else BACKEND_DIR / "serviceAccountKey.json"


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Remove usernames and data left by accounts deleted in the Firebase Console."
    )
    parser.add_argument("--apply", action="store_true", help="delete (default is a dry run)")
    parser.add_argument("--key", help="service account JSON (default: backend/serviceAccountKey.json)")
    args = parser.parse_args(list(argv) if argv is not None else None)

    key = _credential_path(args.key)
    if not key.is_file():
        print(f"Service account key not found: {key}", file=sys.stderr)
        return 1

    import firebase_admin
    from firebase_admin import auth, credentials, firestore

    app = firebase_admin.initialize_app(credentials.Certificate(str(key)), name="cleanup")
    try:
        db = firestore.client(app)
        project = app.project_id
        print(f"Project: {project}{'' if args.apply else ' (dry run)'}")

        class _Auth:  # binds the lookups to this app
            UidIdentifier = auth.UidIdentifier

            @staticmethod
            def get_users(ids):
                return auth.get_users(ids, app=app)

        run(db, _auth_lookup(_Auth), apply=args.apply)
    finally:
        firebase_admin.delete_app(app)
    return 0


if __name__ == "__main__":
    sys.exit(main())
