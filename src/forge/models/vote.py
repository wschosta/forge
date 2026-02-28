"""Vote data model — replaces +util/+templates/getVoteTemplate.m."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Vote:
    """Represents a single rollcall vote with its voter lists.

    Fields mirror the MATLAB struct created by getVoteTemplate() plus
    the voter lists attached by addRollcallVotes().
    """

    rollcall_id: int = 0
    description: str = ""
    date: str = ""
    yea: int = 0
    nay: int = 0
    nv: int = 0
    total_vote: int = 0
    yes_percent: float = 0.0

    # Voter ID lists (sponsor_id values)
    yes_list: list[int] = field(default_factory=list)
    no_list: list[int] = field(default_factory=list)
    abstain_list: list[int] = field(default_factory=list)
