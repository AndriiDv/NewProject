import os
from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends
from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings

connect_args = {}
if "rds.amazonaws.com" in settings.database_url:
    connect_args["ssl"] = "require"

engine = create_async_engine(
    settings.database_url,
    connect_args=connect_args,
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_recycle=600,
    # Connections can go stale while a Lambda instance is frozen between requests.
    pool_pre_ping=True,
)


@event.listens_for(engine.sync_engine, "do_connect")
def provide_token(dialect, conn_rec, cargs, cparams):
    host = cparams.get("host") or ""
    if "rds.amazonaws.com" in host and (
        not cparams.get("password") or cparams.get("password") in ("", "iam", "None")
    ):
        try:
            import boto3

            region = os.environ.get("AWS_REGION") or (
                host.split(".")[-4] if len(host.split(".")) >= 4 else "eu-north-1"
            )
            rds_client = boto3.client("rds", region_name=region)
            token = rds_client.generate_db_auth_token(
                DBHostname=host,
                Port=cparams.get("port", 5432),
                DBUsername=cparams.get("user", "meetings"),
                Region=region,
            )
            cparams["password"] = token
            cparams["ssl"] = "require"
        except Exception:
            pass


SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session


SessionDep = Annotated[AsyncSession, Depends(get_session)]
