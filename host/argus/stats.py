"""Latency and rate statistics over decoded trace records.

Turns a list of TraceRecord into simple, dependency-free statistics used in the
characterization/reporting flow: inter-event intervals (in timebase cycles),
min/max/mean, and per-source event counts.
"""

from __future__ import annotations

from .trace import TraceRecord


def inter_event_intervals(records: list[TraceRecord]) -> list[int]:
    """Timestamp deltas between consecutive records (assumes time order)."""
    ts = [r.timestamp for r in records]
    return [b - a for a, b in zip(ts, ts[1:])]


def interval_stats(records: list[TraceRecord]) -> dict:
    ivals = inter_event_intervals(records)
    if not ivals:
        return {"count": len(records), "min": None, "max": None, "mean": None}
    return {
        "count": len(records),
        "min": min(ivals),
        "max": max(ivals),
        "mean": sum(ivals) / len(ivals),
    }


def per_source_counts(records: list[TraceRecord]) -> dict:
    counts: dict[str, int] = {}
    for r in records:
        counts[r.source_name] = counts.get(r.source_name, 0) + 1
    return counts
