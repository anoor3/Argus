"""Optional plotting of trace timelines.

matplotlib is an optional dependency. If it is not installed, plot_timeline
raises a clear error instead of failing at import time, so the rest of the host
tooling stays dependency-free.
"""

from __future__ import annotations

from .trace import TraceRecord


def _require_matplotlib():
    try:
        import matplotlib.pyplot as plt  # type: ignore
        return plt
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise RuntimeError(
            "matplotlib is required for plotting; install with "
            "`pip install matplotlib`"
        ) from exc


def plot_timeline(records: list[TraceRecord], path: str) -> None:
    """Scatter events on a (timestamp, source) timeline and save to path."""
    plt = _require_matplotlib()
    if not records:
        raise ValueError("no records to plot")
    xs = [r.timestamp for r in records]
    ys = [r.source_id for r in records]
    labels = sorted({(r.source_id, r.source_name) for r in records})

    fig, ax = plt.subplots(figsize=(8, 3))
    ax.scatter(xs, ys, marker="|", s=200)
    ax.set_yticks([sid for sid, _ in labels])
    ax.set_yticklabels([name for _, name in labels])
    ax.set_xlabel("timestamp (cycles)")
    ax.set_title("ARGUS event timeline")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
