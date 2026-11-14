"""cleanup_deleted_accounts against an in-memory stand-in for Firestore, so
no Firebase project is touched."""
import pytest

from scripts.cleanup_deleted_accounts import AUTH_LOOKUP_BATCH, find_orphans, run


class _Doc:
    def __init__(self, doc_id, data):
        self.id = doc_id
        self._data = data

    def to_dict(self):
        return dict(self._data)


class _Ref:
    def __init__(self, db, path):
        self.db = db
        self.path = path
        self.id = path.rsplit("/", 1)[-1]


class _Collection:
    def __init__(self, db, name):
        self.db = db
        self.name = name

    def _ids(self):
        return [p.split("/")[1] for p in self.db.docs if p.startswith(self.name + "/") and p.count("/") == 1]

    def stream(self):
        return [_Doc(i, self.db.docs[f"{self.name}/{i}"]) for i in sorted(self._ids())]

    def list_documents(self):
        # Like Firestore: also parents that only have subcollections.
        ids = {p.split("/")[1] for p in self.db.docs if p.startswith(self.name + "/")}
        return [_Ref(self.db, f"{self.name}/{i}") for i in sorted(ids)]

    def document(self, doc_id):
        return _Ref(self.db, f"{self.name}/{doc_id}")


class _Batch:
    def __init__(self, db):
        self.db = db
        self.deletes = []

    def delete(self, ref):
        self.deletes.append(ref.path)

    def commit(self):
        for path in self.deletes:
            self.db.docs.pop(path, None)


class FakeDb:
    def __init__(self, docs):
        self.docs = dict(docs)

    def collection(self, name):
        return _Collection(self, name)

    def batch(self):
        return _Batch(self)

    def recursive_delete(self, ref):
        for path in [p for p in self.docs if p == ref.path or p.startswith(ref.path + "/")]:
            del self.docs[path]


def lookup(alive):
    calls = []

    def existing(uids):
        calls.append(list(uids))
        return {u for u in uids if u in alive}

    existing.calls = calls
    return existing


def seeded():
    return FakeDb({
        "usernames/alice": {"uid": "alive"},
        "usernames/ghost": {"uid": "gone"},
        "usernames/broken": {},
        "users/alive": {"username": "alice", "usernameLower": "alice"},
        "users/alive/workoutLogs/l1": {"x": 1},
        "users/gone": {"username": "Ghost", "usernameLower": "ghost"},
        "users/gone/workoutPlans/p1": {"x": 1},
        "users/gone/workoutPlans/p1/days/d1": {"x": 1},
        # users/{uid} doc gone, subcollection left, no username
        "users/husk/profile/info": {"x": 1},
        "follows/f1": {"followerUid": "alive", "followingUid": "gone"},
        "follows/f2": {"followerUid": "gone", "followingUid": "alive"},
        "follows/f3": {"followerUid": "alive", "followingUid": "other"},
        "follows/f4": {"followerUid": "gone", "followingUid": "husk"},
    })


def test_finds_only_uids_missing_from_auth():
    scan = find_orphans(seeded(), lookup({"alive", "other"}))
    by_uid = {o.uid: o for o in scan.orphans}

    assert set(by_uid) == {"gone", "husk"}
    assert by_uid["gone"].usernames == ["ghost"]
    assert sorted(by_uid["gone"].follow_ids) == ["f1", "f2", "f4"]
    assert by_uid["gone"].has_user_tree
    assert by_uid["husk"].usernames == []
    assert by_uid["husk"].has_user_tree
    assert scan.malformed_usernames == ["broken"]


def test_dry_run_deletes_nothing():
    db = seeded()
    before = dict(db.docs)
    run(db, lookup({"alive", "other"}), apply=False, out=lambda _: None)
    assert db.docs == before


def test_apply_deletes_orphans_and_keeps_live_accounts():
    db = seeded()
    run(db, lookup({"alive", "other"}), apply=True, out=lambda _: None)

    assert sorted(db.docs) == [
        "follows/f3",
        "usernames/alice",
        "usernames/broken",
        "users/alive",
        "users/alive/workoutLogs/l1",
    ]


def test_failed_auth_lookup_deletes_nothing():
    db = seeded()
    before = dict(db.docs)

    def broken(_):
        raise RuntimeError("auth unavailable")

    with pytest.raises(RuntimeError):
        run(db, broken, apply=True, out=lambda _: None)
    assert db.docs == before


def test_auth_lookups_are_batched():
    db = FakeDb({f"usernames/u{i}": {"uid": f"uid{i}"} for i in range(AUTH_LOOKUP_BATCH + 5)})
    existing = lookup(set())
    find_orphans(db, existing)
    assert [len(c) for c in existing.calls] == [AUTH_LOOKUP_BATCH, 5]
