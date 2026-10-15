"""Sunwai API.

Run (from the backend folder):   uvicorn app.main:app --reload
API docs:                        http://localhost:8000/docs
"""
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from psycopg import errors

from .config import settings
from .db import fetch_all, pool, scalar, system_session
from .routers import (analytics, appeals, auth_routes, committee, complaints, demo,
                      handler, reevaluation, triage_officer)
from .services import scheduler

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool.open(wait=True, timeout=10)
    task = None
    if settings.scheduler_seconds > 0:
        task = asyncio.create_task(scheduler.loop())
    yield
    if task:
        task.cancel()
    pool.close()


app = FastAPI(title="Sunwai API", version="1.0",
              description="AI-routed grievance redressal for NSUT. "
                          "All rules and permissions live in PostgreSQL.",
              lifespan=lifespan)

app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
                   allow_methods=["*"], allow_headers=["*"])


# ---- database errors -> HTTP errors, with PostgreSQL's own message
@app.exception_handler(errors.InsufficientPrivilege)
async def denied(_: Request, e: errors.InsufficientPrivilege):
    return JSONResponse(status_code=403, content={"detail": e.diag.message_primary,
                                                  "source": "postgresql"})


@app.exception_handler(errors.RaiseException)
async def rule(_: Request, e: errors.RaiseException):
    # raised by our procedures / triggers, e.g. "The 7-day reopen window has passed"
    return JSONResponse(status_code=400, content={"detail": e.diag.message_primary,
                                                  "source": "postgresql"})


@app.exception_handler(errors.IntegrityError)
async def integrity(_: Request, e: errors.IntegrityError):
    return JSONResponse(status_code=400, content={"detail": e.diag.message_primary,
                                                  "source": "postgresql"})


@app.exception_handler(errors.DataError)
async def data(_: Request, e: errors.DataError):
    return JSONResponse(status_code=400, content={"detail": e.diag.message_primary,
                                                  "source": "postgresql"})


for r in (auth_routes, complaints, handler, committee, triage_officer, appeals,
          reevaluation, analytics, demo):
    app.include_router(r.router)


@app.get("/api/health")
def health():
    with system_session() as cur:
        complaints_n = scalar(cur, "SELECT count(*) FROM complaint")
    return {"database": "ok", "complaints_visible_to_admin": complaints_n,
            "llm": settings.openai_model if settings.use_openai else "offline classifier"}


@app.get("/api/categories")
def categories():
    with system_session() as cur:
        return fetch_all(cur, "SELECT category_id, name, domain, sensitivity, base_priority,"
                              " sla_hours, anonymous_allowed FROM category ORDER BY 1")
