import json, os
from google.oauth2 import service_account
from google.cloud import firestore_admin_v1
KEY = os.path.join(os.path.dirname(__file__), "..", "..", "backend", "serviceAccountKey.json")
creds = service_account.Credentials.from_service_account_file(KEY)
project = json.load(open(KEY))["project_id"]
c = firestore_admin_v1.FirestoreAdminClient(credentials=creds)
for ix in c.list_indexes(parent=f"projects/{project}/databases/(default)/collectionGroups/weeklySummaries"):
    print([(f.field_path, f.order.name) for f in ix.fields], ix.state.name)
