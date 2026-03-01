"""Text preprocessing for bill classification — replaces +la/cleanupText.m.

Cleans bill text by splitting, filtering stop words, removing short words
and numbers, uppercasing, deduplicating, and computing word frequency weights.
"""

from __future__ import annotations

import re
from collections import Counter


def cleanup_text(text: str | list[str], stop_words: list[str]) -> tuple[list[str], list[float]]:
    """Clean and tokenize text for bill classification.

    Replaces la.cleanupText(). Processing steps:
    1. If text is a string, apply regex replacements:
       - Remove numbers and number-prefixed words (``\\d+\\w*``)
       - Remove standalone 1-2 character words (`` \\w{1,2} ``)
       - Remove ``<p>`` and ``<b>`` HTML tags
    2. Split on non-word or whitespace characters
    3. Remove stop words (case-insensitive)
    4. Remove empty tokens
    5. Uppercase all tokens
    6. Deduplicate and compute frequency weights

    Args:
        text: Input text as a string, or pre-tokenized list of strings.
        stop_words: List of words to exclude.

    Returns:
        Tuple of (unique_words, weights) where:
            unique_words: List of unique uppercase tokens.
            weights: List of frequency counts for each unique word.
    """
    if not text:
        return [], [0.0]

    # Step 1-2: Tokenize if string
    if isinstance(text, str):
        # Apply the same regex replacements as MATLAB
        # Remove digits and digit-prefixed words
        text = re.sub(r"\d+\w*", " ", text)
        # Remove 1-2 character standalone words
        text = re.sub(r"\b\w{1,2}\b", " ", text)
        # Remove <p> and <b> HTML tags (MATLAB: '\<(\\)?[pb]\>')
        text = re.sub(r"</?[pb]>", " ", text)
        # Split on non-word or whitespace characters
        tokens = re.split(r"[\W\s]+", text)
    else:
        tokens = list(text)

    # Build uppercase stop word set for case-insensitive comparison
    stop_set = {w.upper() for w in stop_words}

    # Step 3-5: Filter and uppercase
    filtered = []
    for token in tokens:
        if not token:
            continue
        upper_token = token.upper()
        if upper_token in stop_set:
            continue
        filtered.append(upper_token)

    if not filtered:
        return [], [0.0]

    # Step 6: Deduplicate and count frequencies
    counts = Counter(filtered)
    unique_words = list(counts.keys())
    weights = [float(counts[w]) for w in unique_words]

    return unique_words, weights
