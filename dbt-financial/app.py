import os
import subprocess
import threading
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel


app = FastAPI(
    title="DWH Financial dbt Runner",
    version="1.1.0"
)


# -------------------------------------------------------------------
# Estado de ejecución
# -------------------------------------------------------------------

execution_lock = threading.Lock()

execution_state = {
    "status": "idle",
    "started_at": None,
    "finished_at": None,
    "command": None,
    "return_code": None,
    "output": None,
}


# -------------------------------------------------------------------
# Request model
# -------------------------------------------------------------------

class RunRequest(BaseModel):
    select: str = "staging"
    full_refresh: bool = False


# -------------------------------------------------------------------
# Configuración
# -------------------------------------------------------------------

ALLOWED_SELECTS = {
    "staging",
    "intermediate",
    "marts",
    "staging+",
    "intermediate+",
    "marts+",
    "*",
}


# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

def utc_now():
    return datetime.now(timezone.utc).isoformat()


def validate_select(select: str):
    """
    Permite uno o varios selectores dbt separados por espacios.

    Ejemplos válidos:
        staging
        intermediate
        staging intermediate
        staging intermediate marts
        staging+ intermediate+
        *
    """

    selectors = select.split()

    if not selectors:
        raise HTTPException(
            status_code=400,
            detail="Select cannot be empty."
        )

    invalid = [
        selector
        for selector in selectors
        if selector not in ALLOWED_SELECTS
    ]

    if invalid:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid select(s): {', '.join(invalid)}"
        )


def run_dbt(select: str, full_refresh: bool):
    global execution_state

    command = [
        "dbt",
        "run",
        "--select",
        *select.split(),
    ]

    if full_refresh:
        command.append("--full-refresh")

    execution_state = {
        "status": "running",
        "started_at": utc_now(),
        "finished_at": None,
        "command": command,
        "return_code": None,
        "output": None,
    }

    try:
        result = subprocess.run(
            command,
            cwd="/workspace",
            capture_output=True,
            text=True,
            env=os.environ.copy(),
        )

        output = ""

        if result.stdout:
            output += result.stdout

        if result.stderr:
            output += "\n" + result.stderr

        execution_state.update({
            "status": "success" if result.returncode == 0 else "error",
            "finished_at": utc_now(),
            "return_code": result.returncode,
            "output": output,
        })

    except Exception as exc:
        execution_state.update({
            "status": "error",
            "finished_at": utc_now(),
            "return_code": -1,
            "output": str(exc),
        })

    finally:
        execution_lock.release()


# -------------------------------------------------------------------
# Endpoints
# -------------------------------------------------------------------

@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "dbt-runner",
    }


@app.get("/status")
def status():
    return execution_state


@app.post("/run")
def run(request: RunRequest):

    validate_select(request.select)

    if not execution_lock.acquire(blocking=False):
        raise HTTPException(
            status_code=409,
            detail="A dbt execution is already running."
        )

    thread = threading.Thread(
        target=run_dbt,
        args=(request.select, request.full_refresh),
        daemon=True,
    )

    thread.start()

    return {
        "status": "started",
        "select": request.select,
        "full_refresh": request.full_refresh,
    }