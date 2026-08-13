"""Crash-safe checkpointing for the long-running Monte Carlo and Elo drivers.

A full Indiana Elo sweep is roughly a day of compute and the Monte Carlo
prediction several hours. Any interruption — a reclaimed container, a laptop
lid, a stray Ctrl-C — previously discarded all of it, because both drivers
accumulate everything in memory and write only at the end.

This stores partial progress so an interrupted run resumes instead of
restarting. Both drivers are structured to make that exact rather than
approximate:

* the Monte Carlo loop computes one independent result per bill;
* the Elo loop seeds iteration ``j`` with ``j + 1`` rather than drawing from a
  continuing stream, so iteration ``j`` produces the same numbers no matter
  when it runs.

A resumed run therefore reproduces an uninterrupted one bit for bit, which
``tests/test_predict/test_checkpoint.py`` asserts rather than assumes.

Checkpoints are derived data and disposable: delete the directory to force a
clean run. They are keyed by content-independent names supplied by the caller,
so two different runs must not share a directory.
"""

from __future__ import annotations

import logging
import os
import pickle
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

#: Bumped when the pickled payload shape changes. A checkpoint written by an
#: older version is ignored rather than misread, because silently resuming from
#: a stale shape would corrupt results in a way no test would catch.
CHECKPOINT_FORMAT = 2


class Checkpoint:
    """A directory of resumable partial results.

    Disabled instances (``directory=None``) satisfy the same interface and do
    nothing, so callers need no branching — passing ``None`` restores the
    original all-or-nothing behaviour exactly.

    Args:
        directory: Where to store partial results, or None to disable.
    """

    def __init__(self, directory: str | Path | None) -> None:
        self.directory = Path(directory) if directory is not None else None
        if self.directory is not None:
            self.directory.mkdir(parents=True, exist_ok=True)

    @property
    def enabled(self) -> bool:
        """Whether this checkpoint actually persists anything."""
        return self.directory is not None

    def _path(self, key: str) -> Path:
        assert self.directory is not None
        # Keys come from internal callers (bill ids, category numbers), but a
        # separator would silently write outside the directory.
        safe = key.replace("/", "_").replace("..", "_")
        return self.directory / f"{safe}.pkl"

    def load(self, key: str) -> Any | None:
        """Return the stored payload for ``key``, or None if absent or unusable.

        A checkpoint that cannot be read is treated as absent rather than fatal:
        the work is recomputed, which is slow but always correct. A truncated
        file from a process killed mid-write is the expected case.
        """
        if not self.enabled:
            return None
        path = self._path(key)
        if not path.exists():
            return None
        try:
            with path.open("rb") as handle:
                payload = pickle.load(handle)
        except Exception as exc:  # noqa: BLE001 - see below
            # Deliberately broad. A pickle truncated by a killed process raises
            # whatever the corrupted opcode stream happens to produce —
            # UnpicklingError and EOFError are common, but a mangled length
            # prefix yields MemoryError, and a mangled class path yields
            # AttributeError or ImportError. Every one of them means the same
            # thing here: the cached work is unusable, so recompute it. Failing
            # the run instead would turn a disposable cache into a liability.
            logger.warning("Ignoring unreadable checkpoint %s: %s", path.name, exc)
            return None

        if not isinstance(payload, dict) or payload.get("format") != CHECKPOINT_FORMAT:
            logger.warning(
                "Ignoring checkpoint %s written in format %s (this build expects %d)",
                path.name, (payload or {}).get("format") if isinstance(payload, dict) else "?",
                CHECKPOINT_FORMAT,
            )
            return None
        return payload["value"]

    def save(self, key: str, value: Any) -> None:
        """Persist ``value`` under ``key``, atomically.

        The write goes to a temporary file which is then renamed. Rename is
        atomic on POSIX, so a process killed at any point leaves either the
        previous checkpoint or the new one — never a half-written file that
        would be silently loaded as truth.
        """
        if not self.enabled:
            return
        path = self._path(key)
        tmp = path.with_suffix(".pkl.tmp")
        try:
            with tmp.open("wb") as handle:
                pickle.dump({"format": CHECKPOINT_FORMAT, "value": value}, handle,
                            protocol=pickle.HIGHEST_PROTOCOL)
                handle.flush()
                os.fsync(handle.fileno())
            tmp.replace(path)
        except OSError as exc:
            # Losing a checkpoint costs time, not correctness — never abort the
            # run over one.
            logger.warning("Could not write checkpoint %s: %s", path.name, exc)
            tmp.unlink(missing_ok=True)

    def keys(self) -> list[str]:
        """Return the keys currently stored, sorted."""
        if not self.enabled:
            return []
        return sorted(p.stem for p in self.directory.glob("*.pkl"))

    def clear(self) -> None:
        """Delete every stored checkpoint, leaving the directory in place."""
        if not self.enabled:
            return
        for path in self.directory.glob("*.pkl"):
            path.unlink(missing_ok=True)
        for path in self.directory.glob("*.pkl.tmp"):
            path.unlink(missing_ok=True)
