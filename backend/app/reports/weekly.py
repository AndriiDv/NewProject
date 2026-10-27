import csv
import io
import re
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db import SessionLocal
from app.models import Meeting


def parse_iso_week(
    week_str: str,
) -> tuple[datetime, datetime, datetime, datetime, str]:
    """Parse an ISO week string (e.g. '2026-W43') into UTC time boundaries.

    Returns:
        (target_start, target_end, prev_start, prev_end, prev_week_str)
        where start is Monday 00:00:00 UTC and end is next Monday 00:00:00 UTC.
    """
    m = re.match(r"^(\d{4})-W(\d{2})$", week_str.strip())
    if not m:
        raise ValueError(
            f"Invalid ISO week format '{week_str}', expected 'YYYY-Www' (e.g. '2026-W43')"
        )
    year = int(m.group(1))
    week_num = int(m.group(2))
    if not (1 <= week_num <= 53):
        raise ValueError(f"Week number must be between 1 and 53, got {week_num}")

    # Monday of the target ISO week at 00:00:00 UTC
    target_start = datetime.fromisocalendar(year, week_num, 1).replace(
        hour=0, minute=0, second=0, microsecond=0, tzinfo=UTC
    )
    target_end = target_start + timedelta(days=7)

    # Previous ISO week boundaries
    prev_start = target_start - timedelta(days=7)
    prev_end = target_start
    prev_year, prev_week_num, _ = prev_start.isocalendar()
    prev_week_str = f"{prev_year}-W{prev_week_num:02d}"

    return target_start, target_end, prev_start, prev_end, prev_week_str


def get_previous_iso_week(ref_date: datetime | None = None) -> str:
    """Return the ISO week string for the week preceding ref_date (defaulting to now UTC)."""
    now = ref_date or datetime.now(UTC)
    curr_start = datetime.fromisocalendar(now.year, now.isocalendar().week, 1).replace(
        hour=0, minute=0, second=0, microsecond=0, tzinfo=UTC
    )
    prev_week_start = curr_start - timedelta(days=7)
    year, week, _ = prev_week_start.isocalendar()
    return f"{year}-W{week:02d}"


async def build_weekly_report(week: str, session: AsyncSession | None = None) -> bytes:
    """Build a weekly meeting summary report in CSV format.

    Calculates:
      - Total meetings and aggregate duration (in hours) for the specified ISO week.
      - Same metrics for the previous week and computes changes/trends.
      - Top 5 longest meetings: title, start datetime, duration, and number of participants.

    Returns:
        CSV content as bytes (UTF-8).
    """
    target_start, target_end, prev_start, prev_end, prev_week_str = parse_iso_week(week)

    if session is not None:
        return await _generate_report(
            week, prev_week_str, target_start, target_end, prev_start, prev_end, session
        )

    async with SessionLocal() as db_session:
        return await _generate_report(
            week, prev_week_str, target_start, target_end, prev_start, prev_end, db_session
        )


async def _generate_report(
    week_str: str,
    prev_week_str: str,
    target_start: datetime,
    target_end: datetime,
    prev_start: datetime,
    prev_end: datetime,
    session: AsyncSession,
) -> bytes:
    # Query meetings for current week with participants eagerly loaded
    stmt_curr = (
        select(Meeting)
        .options(selectinload(Meeting.participants))
        .where(Meeting.starts_at >= target_start, Meeting.starts_at < target_end)
    )
    res_curr = await session.execute(stmt_curr)
    curr_meetings = res_curr.scalars().all()

    # Query meetings for previous week
    stmt_prev = select(Meeting).where(Meeting.starts_at >= prev_start, Meeting.starts_at < prev_end)
    res_prev = await session.execute(stmt_prev)
    prev_meetings = res_prev.scalars().all()

    # Aggregate metrics
    total_meetings = len(curr_meetings)
    total_duration_hours = sum(
        (m.ends_at - m.starts_at).total_seconds() / 3600.0 for m in curr_meetings
    )

    prev_total_meetings = len(prev_meetings)
    prev_total_duration_hours = sum(
        (m.ends_at - m.starts_at).total_seconds() / 3600.0 for m in prev_meetings
    )

    meetings_diff = total_meetings - prev_total_meetings
    duration_diff = total_duration_hours - prev_total_duration_hours

    # Top 5 longest meetings in current week
    sorted_meetings = sorted(
        curr_meetings,
        key=lambda m: (
            (m.ends_at - m.starts_at).total_seconds(),
            -m.starts_at.timestamp(),
        ),
        reverse=True,
    )
    top_5 = sorted_meetings[:5]

    output = io.StringIO()
    writer = csv.writer(output)

    # Section 1: Summary & Trends
    writer.writerow(["metric", "current_week", "previous_week", "change"])
    writer.writerow(["week", week_str, prev_week_str, "-"])
    writer.writerow(
        [
            "total_meetings",
            total_meetings,
            prev_total_meetings,
            f"{meetings_diff:+d}" if meetings_diff != 0 else "0",
        ]
    )
    writer.writerow(
        [
            "total_duration_hours",
            f"{total_duration_hours:.2f}",
            f"{prev_total_duration_hours:.2f}",
            f"{duration_diff:+.2f}" if duration_diff != 0 else "0.00",
        ]
    )

    writer.writerow([])  # Blank line separating sections

    # Section 2: Top 5 Longest Meetings
    writer.writerow(["rank", "title", "start_datetime", "duration_hours", "participants_count"])
    for rank, m in enumerate(top_5, start=1):
        dur = (m.ends_at - m.starts_at).total_seconds() / 3600.0
        writer.writerow(
            [
                rank,
                m.title,
                m.starts_at.isoformat(),
                f"{dur:.2f}",
                len(m.participants),
            ]
        )

    return output.getvalue().encode("utf-8")
