import firebase_admin
from firebase_admin import credentials, firestore
from dotenv import load_dotenv
import os

load_dotenv()  # loads .env file

# Only initialize once — Firebase Admin throws an error
if not firebase_admin._apps:
    cred = credentials.Certificate(
        os.getenv("FIREBASE_CREDENTIAL_PATH", "serviceAccountKey.json")
    )
    firebase_admin.initialize_app(cred)

# Firestore client — import this in other files
db = firestore.client()