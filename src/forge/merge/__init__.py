"""Data merging — finance, ideology scores, seniority."""

from forge.merge.finance import merge_finance_data, process_finance
from forge.merge.ideology import merge_shor_mccarty
from forge.merge.seniority import merge_seniority

__all__ = [
    "merge_finance_data",
    "merge_seniority",
    "merge_shor_mccarty",
    "process_finance",
]
