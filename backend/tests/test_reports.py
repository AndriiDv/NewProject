import csv
import io
import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Meeting, Participant, User
from app.reports.builder_handler import detect_trigger, extract_week
from app.reports.weekly import build_weekly_report, get_previous_iso_week, parse_iso_week


@pytest.fixture
async def session(engine):
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as s:
        yield s


def test_parse_iso_week():
    start, end, prev_start, prev_end, prev_week = parse_iso_week("2026-W43")
    assert start == datetime(2026, 10, 19, 0, 0, 0, tzinfo=UTC)
    assert end == datetime(2026, 10, 26, 0, 0, 0, tzinfo=UTC)
    assert prev_start == datetime(2026, 10, 12, 0, 0, 0, tzinfo=UTC)
    assert prev_end == datetime(2026, 10, 19, 0, 0, 0, tzinfo=UTC)
    assert prev_week == "2026-W42"

    with pytest.raises(ValueError, match="Invalid ISO week format"):
        parse_iso_week("invalid-week")

    with pytest.raises(ValueError, match="between 1 and 53"):
        parse_iso_week("2026-W99")


def test_get_previous_iso_week():
    # 2026-10-27 is a Tuesday in 2026-W44, previous is 2026-W43
    dt = datetime(2026, 10, 27, 12, 0, 0, tzinfo=UTC)
    assert get_previous_iso_week(dt) == "2026-W43"


def test_detect_trigger_and_extract_week():
    # SQS trigger with schedule source
    sqs_schedule = {"Records": [{"body": '{"week": null, "source": "schedule"}'}]}
    assert detect_trigger(sqs_schedule) == "schedule"
    # Null week falls back to previous ISO week
    week = extract_week(sqs_schedule)
    assert "-W" in week

    # SQS trigger with manual source and explicit week
    sqs_manual = {"Records": [{"body": '{"week": "2026-W43", "source": "manual"}'}]}
    assert detect_trigger(sqs_manual) == "manual"
    assert extract_week(sqs_manual) == "2026-W43"

    # Direct payload
    direct = {"week": "2026-W42", "source": "schedule"}
    assert detect_trigger(direct) == "schedule"
    assert extract_week(direct) == "2026-W42"


async def test_build_weekly_report_empty(session):
    report_bytes = await build_weekly_report("2026-W43", session=session)
    assert isinstance(report_bytes, bytes)
    text = report_bytes.decode("utf-8")

    reader = list(csv.reader(io.StringIO(text)))
    assert reader[0] == ["metric", "current_week", "previous_week", "change"]
    # Total meetings should be 0
    meetings_row = [r for r in reader if len(r) >= 2 and r[0] == "total_meetings"][0]
    assert meetings_row[1] == "0"
    assert meetings_row[2] == "0"
    assert meetings_row[3] == "0"


async def test_build_weekly_report_with_meetings(session):
    # Create test user
    user = User(
        cognito_sub=f"sub-{uuid.uuid4()}",
        email="reporter@example.com",
        name="Reporter",
    )
    session.add(user)
    await session.flush()

    # Create participants
    p1 = Participant(name="Alice", email=f"alice-{uuid.uuid4()}@example.com")
    p2 = Participant(name="Bob", email=f"bob-{uuid.uuid4()}@example.com")
    p3 = Participant(name="Charlie", email=f"charlie-{uuid.uuid4()}@example.com")
    session.add_all([p1, p2, p3])
    await session.flush()

    # Week 42 (previous week: Oct 12 - Oct 19, 2026)
    m_prev1 = Meeting(
        title="Prev Week Standup",
        starts_at=datetime(2026, 10, 13, 10, 0, tzinfo=UTC),
        ends_at=datetime(2026, 10, 13, 11, 0, tzinfo=UTC),  # 1.0 hr
        place="Online",
        owner_id=user.id,
        participants=[p1],
    )
    session.add(m_prev1)

    # Week 43 (current week: Oct 19 - Oct 26, 2026)
    m1 = Meeting(
        title="Quarterly Strategy",
        starts_at=datetime(2026, 10, 20, 9, 0, tzinfo=UTC),
        ends_at=datetime(2026, 10, 20, 12, 0, tzinfo=UTC),  # 3.0 hr
        place="Conf Room A",
        owner_id=user.id,
        participants=[p1, p2, p3],
    )
    m2 = Meeting(
        title="Architecture Sync",
        starts_at=datetime(2026, 10, 21, 14, 0, tzinfo=UTC),
        ends_at=datetime(2026, 10, 21, 16, 0, tzinfo=UTC),  # 2.0 hr
        place="Conf Room B",
        owner_id=user.id,
        participants=[p1, p2],
    )
    m3 = Meeting(
        title="Quick 1-on-1",
        starts_at=datetime(2026, 10, 22, 11, 0, tzinfo=UTC),
        ends_at=datetime(2026, 10, 22, 11, 30, tzinfo=UTC),  # 0.5 hr
        place="Lounge",
        owner_id=user.id,
        participants=[p1],
    )
    session.add_all([m1, m2, m3])
    await session.commit()

    # Generate report
    report_bytes = await build_weekly_report("2026-W43", session=session)
    text = report_bytes.decode("utf-8")
    lines = list(csv.reader(io.StringIO(text)))

    # Metrics
    metrics_map = {row[0]: row[1:] for row in lines if len(row) == 4}
    assert metrics_map["week"] == ["2026-W43", "2026-W42", "-"]
    assert metrics_map["total_meetings"] == ["3", "1", "+2"]
    # Total duration: 3.0 + 2.0 + 0.5 = 5.5 hrs, prev = 1.0 hr, diff = +4.50
    assert metrics_map["total_duration_hours"] == ["5.50", "1.00", "+4.50"]

    # Top meetings
    top_meetings = [row for row in lines if len(row) == 5 and row[0] not in ("metric", "rank")]
    assert len(top_meetings) == 3
    # First is longest: Quarterly Strategy (3.00 hrs, 3 participants)
    assert top_meetings[0][1] == "Quarterly Strategy"
    assert top_meetings[0][3] == "3.00"
    assert top_meetings[0][4] == "3"

    # Second: Architecture Sync (2.00 hrs, 2 participants)
    assert top_meetings[1][1] == "Architecture Sync"
    assert top_meetings[1][3] == "2.00"
    assert top_meetings[1][4] == "2"

    # Third: Quick 1-on-1 (0.50 hrs, 1 participant)
    assert top_meetings[2][1] == "Quick 1-on-1"
    assert top_meetings[2][3] == "0.50"
    assert top_meetings[2][4] == "1"


async def test_idempotent_report_generation(session):
    # Calling multiple times produces identical bytes
    report1 = await build_weekly_report("2026-W43", session=session)
    report2 = await build_weekly_report("2026-W43", session=session)
    assert report1 == report2
