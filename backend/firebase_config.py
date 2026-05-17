import firebase_admin
from firebase_admin import credentials, firestore
from dotenv import load_dotenv
import os
import json

load_dotenv()

if not firebase_admin._apps:
    # On Render: credentials come from environment variable (JSON string)
    # Locally: credentials come from serviceAccountKey.json file
    firebase_credentials_json = os.getenv("FIREBASE_CREDENTIALS_JSON")

    if firebase_credentials_json:
        # Render deployment — parse JSON string from environment variable
        cred_dict = json.loads(firebase_credentials_json)
        cred = credentials.Certificate(cred_dict)
    else:
        # Local development — read from file
        cred = credentials.Certificate(
            os.getenv("FIREBASE_CREDENTIAL_PATH", "serviceAccountKey.json")
        )

    firebase_admin.initialize_app(cred)

db = firestore.client()