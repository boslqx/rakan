from fastapi import Depends, FastAPI
from auth import current_uid
from routers.plan_router import router as plan_router
from routers.adapt_router import router as adapt_router
from routers.adaptation_engine_router import router as adaptation_engine_router

app = FastAPI(title="Rakan AI Backend")

# Register routers — all plan endpoints are now available. Every endpoint
# needs a valid Firebase ID token (D-15 / V-07); the plan routes also use
# the token's uid for their writes, so they take the dependency per route.
app.include_router(plan_router)
app.include_router(adapt_router, dependencies=[Depends(current_uid)])
app.include_router(adaptation_engine_router, dependencies=[Depends(current_uid)])

@app.get("/")
def root():
    return {"status": "Rakan backend is running"}