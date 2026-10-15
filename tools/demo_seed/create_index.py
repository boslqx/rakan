"""Create the composite index the app's weekly-summary query needs:
weeklySummaries (collection group scope COLLECTION): changesAcknowledged ASC, generatedAt DESC."""
import json, os, sys, time
from google.oauth2 import service_account
from google.cloud import firestore_admin_v1
from google.cloud.firestore_admin_v1.types import Index
KEY = os.path.join(os.path.dirname(__file__), "..", "..", "backend", "serviceAccountKey.json")
creds = service_account.Credentials.from_service_account_file(KEY)
project = json.load(open(KEY))["project_id"]
client = firestore_admin_v1.FirestoreAdminClient(credentials=creds)
parent = f"projects/{project}/databases/(default)/collectionGroups/weeklySummaries"
existing = list(client.list_indexes(parent=parent))
for ix in existing:
    print("existing:", [(f.field_path, f.order) for f in ix.fields], ix.state.name)
idx = Index(query_scope=Index.QueryScope.COLLECTION, fields=[
    Index.IndexField(field_path="changesAcknowledged", order=Index.IndexField.Order.ASCENDING),
    Index.IndexField(field_path="generatedAt", order=Index.IndexField.Order.DESCENDING),
])
try:
    op = client.create_index(parent=parent, index=idx)
    print("create requested:", op.operation.name)
except Exception as e:
    print("create_index:", type(e).__name__, e)
for i in range(30):
    states = [(tuple(f.field_path for f in ix.fields), ix.state.name) for ix in client.list_indexes(parent=parent)]
    print("states:", states); sys.stdout.flush()
    if any(s == "READY" and "changesAcknowledged" in f for f, s in states):
        print("INDEX READY"); break
    time.sleep(10)
