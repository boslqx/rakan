from fastapi import FastAPI
from firebase_config import db
from routers.plan_router import router as plan_router
from routers.adapt_router import router as adapt_router

app = FastAPI(title="Rakan AI Backend")

# Register routers — all plan endpoints are now available
app.include_router(plan_router)
app.include_router(adapt_router)

@app.get("/")
def root():
    return {"status": "Rakan backend is running"}

@app.get("/test-firebase")
def test_firebase():
    db.collection("_test").document("ping").set({"status": "connected"})
    return {"status": "Firebase connected successfully"}