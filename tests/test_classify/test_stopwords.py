"""Tests for forge.classify.stopwords."""

from forge.classify.stopwords import get_common_words


class TestGetCommonWords:
    def test_returns_nonempty_list(self):
        words = get_common_words()
        assert len(words) > 700

    def test_contains_common_english(self):
        words = get_common_words()
        for word in ["the", "of", "to", "and", "a", "in", "is"]:
            assert word in words

    def test_contains_state_names(self):
        words = get_common_words()
        for state in ["California", "Indiana", "Ohio"]:
            assert state in words

    def test_contains_state_abbreviations(self):
        words = get_common_words()
        for abbr in ["CA", "IN", "OH", "NY"]:
            assert abbr in words

    def test_contains_legislative_terms(self):
        words = get_common_words()
        for term in ["bill", "sec", "amends", "prohibits"]:
            assert term in words

    def test_contains_months(self):
        words = get_common_words()
        for month in ["january", "february", "march"]:
            assert month in words
