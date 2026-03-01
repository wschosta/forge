"""Chamber data model — replaces +util/+templates/getChamberTemplate.m and processChamberRollcalls output."""

from __future__ import annotations

from dataclasses import dataclass, field

from forge.models.vote import Vote


@dataclass
class ChamberData:
    """Processed rollcall data for one chamber (House or Senate) of one bill.

    Created by processChamberRollcalls(). Contains separated chamber and
    committee votes, plus summary statistics from the final vote.
    """

    committee_votes: list[Vote] = field(default_factory=list)
    chamber_votes: list[Vote] = field(default_factory=list)

    # Final vote summary (from the last chamber vote)
    final_yea: int = 0
    final_nay: int = 0
    final_nv: int = 0
    final_total_vote: int = 0
    final_yes_percentage: float = -1.0

    # Competitiveness flag (set during bill processing)
    competitive: int = 0
