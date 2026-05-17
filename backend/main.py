from fastapi import FastAPI
from firebase_config import db  # this triggers Firebase initialization

app = FastAPI(title="Rakan AI Backend")

@app.get("/")
def root():
    return {"status": "Rakan backend is running"}

@app.get("/test-firebase")
def test_firebase():
    # Try writing a test document to Firestore
    # If this works, Firebase connection is confirmed
    db.collection("_test").document("ping").set({"status": "connected"})
    return {"status": "Firebase connected successfully"}