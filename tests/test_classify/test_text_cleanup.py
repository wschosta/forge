"""Tests for forge.classify.text_cleanup."""

from forge.classify.text_cleanup import cleanup_text


class TestCleanupText:
    def test_basic_tokenization(self):
        words, weights = cleanup_text("hello world", [])
        assert set(words) == {"HELLO", "WORLD"}
        assert all(w == 1.0 for w in weights)

    def test_removes_numbers(self):
        words, _ = cleanup_text("section 123 of the 45th amendment", [])
        # "123" and "45th" should be removed by \d+\w* pattern
        assert "123" not in words
        assert "45TH" not in words

    def test_removes_short_words(self):
        """Words of 1-2 characters should be removed."""
        words, _ = cleanup_text("I am a big dog in my yard", [])
        assert "I" not in words
        assert "AM" not in words
        assert "A" not in words
        assert "IN" not in words
        assert "MY" not in words

    def test_removes_stop_words(self):
        words, _ = cleanup_text("the quick brown fox", ["the", "brown"])
        assert "THE" not in words
        assert "BROWN" not in words
        assert "QUICK" in words
        assert "FOX" in words

    def test_stop_word_removal_case_insensitive(self):
        words, _ = cleanup_text("THE Quick BROWN fox", ["the", "brown"])
        assert "THE" not in words
        assert "BROWN" not in words

    def test_removes_html_tags(self):
        words, _ = cleanup_text("<p>hello</p> <b>world</b>", [])
        assert "P" not in words
        assert "B" not in words
        assert "HELLO" in words
        assert "WORLD" in words

    def test_uppercases_output(self):
        words, _ = cleanup_text("Mixed Case Words", [])
        assert all(w == w.upper() for w in words)

    def test_deduplicates_with_counts(self):
        words, weights = cleanup_text("cat dog cat cat dog", [])
        cat_idx = words.index("CAT")
        dog_idx = words.index("DOG")
        assert weights[cat_idx] == 3.0
        assert weights[dog_idx] == 2.0

    def test_empty_string(self):
        words, weights = cleanup_text("", [])
        assert words == []

    def test_empty_list(self):
        words, weights = cleanup_text([], [])
        assert words == []

    def test_all_stop_words(self):
        words, weights = cleanup_text("the and for", ["the", "and", "for"])
        assert words == []

    def test_list_input(self):
        """Pre-tokenized list input should skip regex step."""
        words, weights = cleanup_text(["HELLO", "WORLD", "HELLO"], [])
        assert "HELLO" in words
        assert "WORLD" in words

    def test_splits_on_nonword_chars(self):
        words, _ = cleanup_text("health-care;reform,act", [])
        assert "HEALTH" in words
        assert "CARE" in words
        assert "REFORM" in words
