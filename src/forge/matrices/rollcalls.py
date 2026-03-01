"""Rollcall processing — replaces processChamberRollcalls.m and addRollcallVotes.m.

Separates rollcalls into chamber vs. committee votes based on vote count,
and extracts voter ID lists from individual rollcalls.
"""

from __future__ import annotations

import pandas as pd

from forge.config import VOTE_NAME_TO_ID
from forge.models.chamber import ChamberData
from forge.models.vote import Vote


def add_rollcall_votes(rollcall_row: pd.Series, votes_df: pd.DataFrame) -> Vote:
    """Extract yes/no/abstain voter lists from a single rollcall.

    Replaces @forge/addRollcallVotes.m.

    Args:
        rollcall_row: A single row from the rollcalls DataFrame.
        votes_df: DataFrame of individual votes for this rollcall.

    Returns:
        A Vote object with rollcall metadata and voter ID lists.
    """
    specific_votes = votes_df[votes_df["roll_call_id"] == rollcall_row["roll_call_id"]]

    yea_id = VOTE_NAME_TO_ID["yea"]
    nay_id = VOTE_NAME_TO_ID["nay"]
    absent_id = VOTE_NAME_TO_ID["absent"]

    yes_list = specific_votes.loc[specific_votes["vote"] == yea_id, "sponsor_id"].tolist()
    no_list = specific_votes.loc[specific_votes["vote"] == nay_id, "sponsor_id"].tolist()
    abstain_list = specific_votes.loc[specific_votes["vote"] == absent_id, "sponsor_id"].tolist()

    desc = rollcall_row.get("description", "")
    if isinstance(desc, list):
        desc = " ".join(str(d) for d in desc)
    elif not isinstance(desc, str):
        desc = str(desc) if pd.notna(desc) else ""

    return Vote(
        rollcall_id=int(rollcall_row["roll_call_id"]),
        description=desc,
        date=str(rollcall_row.get("date", "")),
        yea=int(rollcall_row.get("yea", 0)),
        nay=int(rollcall_row.get("nay", 0)),
        nv=int(rollcall_row.get("nv", 0)),
        total_vote=int(rollcall_row.get("total_vote", 0)),
        yes_percent=float(rollcall_row.get("yes_percent", 0.0)),
        yes_list=yes_list,
        no_list=no_list,
        abstain_list=abstain_list,
    )


def process_chamber_rollcalls(
    rollcalls: pd.DataFrame,
    votes_df: pd.DataFrame,
    committee_size: float,
) -> ChamberData:
    """Separate rollcalls into chamber vs. committee votes and build ChamberData.

    Replaces @forge/processChamberRollcalls.m.

    Rollcalls with ``total_vote < committee_size`` are classified as committee
    votes; the rest are chamber votes. The final vote statistics come from the
    last chamber vote.

    Args:
        rollcalls: DataFrame of rollcalls for one bill in one chamber,
            sorted by date. Must have columns: roll_call_id, total_vote,
            yea, nay, nv, date, description, yes_percent.
        votes_df: Full votes DataFrame (all vote records across sessions).
        committee_size: Threshold for separating committee from chamber votes
            (typically ``chamber_size * committee_threshold``).

    Returns:
        ChamberData with separated vote lists and final vote statistics.
    """
    committee_votes: list[Vote] = []
    chamber_votes: list[Vote] = []

    for _, row in rollcalls.iterrows():
        vote = add_rollcall_votes(row, votes_df)
        if row["total_vote"] < committee_size:
            committee_votes.append(vote)
        else:
            chamber_votes.append(vote)

    # Build ChamberData with final vote statistics from last chamber vote
    cd = ChamberData(
        committee_votes=committee_votes,
        chamber_votes=chamber_votes,
    )

    if chamber_votes:
        last = chamber_votes[-1]
        cd.final_yea = last.yea
        cd.final_nay = last.nay
        cd.final_nv = last.nv
        cd.final_total_vote = last.total_vote
        cd.final_yes_percentage = last.yes_percent

    return cd
