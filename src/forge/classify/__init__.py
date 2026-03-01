"""Bill classification system — text-based policy area classification."""

from forge.classify.classifier import classify_bill, process_all_bills
from forge.classify.learning import (
    LearningData,
    LearningMaterials,
    generate_learning_table,
    load_learning_data,
    save_learning_data,
)
from forge.classify.stopwords import get_common_words
from forge.classify.text_cleanup import cleanup_text

__all__ = [
    "classify_bill",
    "cleanup_text",
    "generate_learning_table",
    "get_common_words",
    "load_learning_data",
    "LearningData",
    "LearningMaterials",
    "process_all_bills",
    "save_learning_data",
]
