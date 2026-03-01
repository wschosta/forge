"""Data merging — finance, ideology scores, seniority."""

from forge.merge.finance import merge_finance_data, process_finance
from forge.merge.ideology import merge_shor_mccarty
from forge.merge.seniority import merge_seniority

__all__ = [
    "merge_finance_data",
    "merge_shor_mccarty",
    "merge_seniority",
    "process_finance",
]
