import asyncio
import os
from logging.config import fileConfig

from sqlalchemy import event, text
from sqlalchemy.ext.asyncio import create_async_engine

from alembic import context
from app.config import settings
from app.models import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

# Migrations run on every container start; on Lambda several instances can start at once.
# A session-level advisory lock makes them take turns (the rest then find nothing to do).
MIGRATION_LOCK_ID = 7_120_531


def run_migrations_offline() -> None:
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection) -> None:
    connection.execute(text("SELECT pg_advisory_lock(:id)"), {"id": MIGRATION_LOCK_ID})
    connection.commit()
    try:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
    finally:
        connection.execute(text("SELECT pg_advisory_unlock(:id)"), {"id": MIGRATION_LOCK_ID})
        connection.commit()


async def run_migrations_online() -> None:
    connect_args = {}
    if "rds.amazonaws.com" in settings.database_url:
        connect_args["ssl"] = "require"

    engine = create_async_engine(settings.database_url, connect_args=connect_args)

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

    async with engine.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
