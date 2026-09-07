import logging
import os
import time

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import psycopg
from pydantic import BaseModel
from psycopg_pool import ConnectionPool

logger = logging.getLogger("loantrack")

# LoanTrack backend
app = FastAPI(title="LoanTrack API")


app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://127.0.0.1:5500",
        "http://localhost:5500",
        "http://127.0.0.1:8081",
        "http://localhost:8081"
    ],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)


# PostgreSQL configuration
DATABASE_URL = (
    f"postgresql://{os.getenv('POSTGRES_USER', 'loantrack_user')}:"
    f"{os.getenv('POSTGRES_PASSWORD', 'loantrack_password')}@"
    f"{os.getenv('POSTGRES_HOST', 'localhost')}:"
    f"{os.getenv('POSTGRES_PORT', '5432')}/"
    f"{os.getenv('POSTGRES_DB', 'loantrack')}"
)

# Connection pool
pool = ConnectionPool(
    conninfo=DATABASE_URL,
    min_size=1,
    max_size=10,
    open=False
)


@app.on_event("startup")
def startup():
    max_attempts = 10

    for attempt in range(1, max_attempts + 1):
        try:
            with psycopg.connect(DATABASE_URL) as connection:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT 1")

            logger.info("Database connection successful on attempt %d", attempt)
            pool.open(wait=True)
            return

        except Exception as exc:
            logger.warning(
                "Database connection attempt %d/%d failed: %s",
                attempt,
                max_attempts,
                exc,
            )

            if attempt == max_attempts:
                logger.error("Database unavailable after %d attempts", max_attempts)
                raise

            delay = min(2 ** (attempt - 1), 10)
            logger.warning("Retrying database connection in %d seconds", delay)
            time.sleep(delay)


@app.on_event("shutdown")
def shutdown():
    pool.close()


# Request model for creating a loan
class LoanCreate(BaseModel):
    borrower_name: str
    loan_amount: float
    property_city: str | None = None
    status: str = "PENDING"


# Health check
@app.get("/healthz")
def healthz():
    return {"status": "ok"}


# Readiness check
@app.get("/readyz")
def readyz():

    try:
        with pool.connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")

        return {"status": "ready"}

    except Exception:
        raise HTTPException(
            status_code=503,
            detail="Database is not ready"
        )


# Get all loans
@app.get("/loans")
def get_loans():

    try:

        with pool.connection() as connection:

            with connection.cursor() as cursor:

                cursor.execute("""
                    SELECT
                        id,
                        borrower_name,
                        loan_amount,
                        property_city,
                        status,
                        created_at
                    FROM loans
                    ORDER BY id;
                """)

                rows = cursor.fetchall()

        loans = []

        for row in rows:

            loans.append({
                "id": row[0],
                "borrower_name": row[1],
                "loan_amount": float(row[2]),
                "property_city": row[3],
                "status": row[4],
                "created_at": row[5].isoformat()
            })

        return loans

    except Exception:
        raise HTTPException(
            status_code=500,
            detail="Failed to retrieve loans"
        )


# Create a new loan
@app.post("/loans")
def create_loan(loan: LoanCreate):

    try:

        with pool.connection() as connection:

            with connection.cursor() as cursor:

                cursor.execute(
                    """
                    INSERT INTO loans (
                        borrower_name,
                        loan_amount,
                        property_city,
                        status
                    )
                    VALUES (%s, %s, %s, %s)
                    RETURNING
                        id,
                        borrower_name,
                        loan_amount,
                        property_city,
                        status,
                        created_at;
                    """,
                    (
                        loan.borrower_name,
                        loan.loan_amount,
                        loan.property_city,
                        loan.status
                    )
                )

                row = cursor.fetchone()

            connection.commit()

        return {
            "id": row[0],
            "borrower_name": row[1],
            "loan_amount": float(row[2]),
            "property_city": row[3],
            "status": row[4],
            "created_at": row[5].isoformat()
        }

    except Exception:
        raise HTTPException(
            status_code=500,
            detail="Failed to create loan"
        )