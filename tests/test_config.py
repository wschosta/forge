"""Tests for forge.config — constants, state properties, and cstr_ainbp."""

import math

import pytest

from forge.config import (
    CONCISE_RECODE,
    ISSUE_KEY,
    PARTY_ID_TO_NAME,
    PARTY_NAME_TO_ID,
    STATE_PROPERTIES,
    VOTE_ID_TO_NAME,
    VOTE_NAME_TO_ID,
    ForgeConfig,
    create_id_strings,
    cstr_ainbp,
)


# ---------------------------------------------------------------------------
# State properties
# ---------------------------------------------------------------------------


class TestStateProperties:
    def test_indiana_chamber_sizes(self):
        assert STATE_PROPERTIES["IN"].senate_size == 50
        assert STATE_PROPERTIES["IN"].house_size == 100

    def test_california_chamber_sizes(self):
        assert STATE_PROPERTIES["CA"].senate_size == 40
        assert STATE_PROPERTIES["CA"].house_size == 88

    def test_us_congress_sizes(self):
        assert STATE_PROPERTIES["US"].senate_size == 100
        assert STATE_PROPERTIES["US"].house_size == 435

    def test_all_states_have_positive_sizes(self):
        for state_id, chambers in STATE_PROPERTIES.items():
            assert chambers.senate_size > 0, f"{state_id} senate_size must be positive"
            assert chambers.house_size > 0, f"{state_id} house_size must be positive"

    def test_eleven_states_configured(self):
        assert len(STATE_PROPERTIES) == 11

    def test_unsupported_state_raises(self):
        assert "XX" not in STATE_PROPERTIES


# ---------------------------------------------------------------------------
# Constant mappings
# ---------------------------------------------------------------------------


class TestPartyKey:
    def test_democrat_is_zero(self):
        assert PARTY_NAME_TO_ID["Democrat"] == 0

    def test_republican_is_one(self):
        assert PARTY_NAME_TO_ID["Republican"] == 1

    def test_independent_is_two(self):
        assert PARTY_NAME_TO_ID["Independent"] == 2

    def test_roundtrip(self):
        for party_id, name in PARTY_ID_TO_NAME.items():
            assert PARTY_NAME_TO_ID[name] == party_id


class TestVoteKey:
    def test_yea_is_one(self):
        assert VOTE_NAME_TO_ID["yea"] == 1

    def test_nay_is_two(self):
        assert VOTE_NAME_TO_ID["nay"] == 2

    def test_absent_is_three(self):
        assert VOTE_NAME_TO_ID["absent"] == 3

    def test_four_vote_types(self):
        assert len(VOTE_ID_TO_NAME) == 4


class TestIssueKey:
    def test_sixteen_categories(self):
        assert len(ISSUE_KEY) == 16

    def test_agriculture_is_one(self):
        assert ISSUE_KEY[1] == "Agriculture"

    def test_other_is_sixteen(self):
        assert ISSUE_KEY[16] == "Other"


class TestConciseRecode:
    def test_eleven_groups(self):
        assert len(CONCISE_RECODE) == 11

    def test_first_group(self):
        assert CONCISE_RECODE[0] == [1, 2]


# ---------------------------------------------------------------------------
# ForgeConfig
# ---------------------------------------------------------------------------


class TestForgeConfig:
    def test_defaults(self):
        cfg = ForgeConfig(state_id="IN")
        assert cfg.monte_carlo_number == 16_000
        assert cfg.elo_monte_carlo_number == 15_000
        assert cfg.committee_threshold == 0.75
        assert cfg.competitive_threshold == 0.85
        assert cfg.bayes_initial == 0.5
        assert cfg.cut_off == 3001
        assert cfg.iwv == 0.13
        assert cfg.awv == 0.0

    def test_chamber_sizes_from_state(self):
        cfg = ForgeConfig(state_id="IN")
        assert cfg.senate_size == 50
        assert cfg.house_size == 100

    def test_unsupported_state_raises(self):
        cfg = ForgeConfig(state_id="XX")
        with pytest.raises(KeyError):
            _ = cfg.senate_size


# ---------------------------------------------------------------------------
# create_id_strings
# ---------------------------------------------------------------------------


class TestCreateIDStrings:
    def test_basic(self):
        assert create_id_strings([1, 2, 3]) == ["id1", "id2", "id3"]

    def test_empty(self):
        assert create_id_strings([]) == []

    def test_with_filter(self):
        result = create_id_strings([1, 2, 3, 4], filter_ids=["id2", "id4"])
        assert result == ["id2", "id4"]

    def test_filter_no_matches(self):
        result = create_id_strings([1, 2, 3], filter_ids=["id99"])
        assert result == []

    def test_large_ids(self):
        assert create_id_strings([12345]) == ["id12345"]


# ---------------------------------------------------------------------------
# cstr_ainbp — the critical string matching function (~30 MATLAB call sites)
# ---------------------------------------------------------------------------


class TestCstrAinbp:
    def test_basic_overlap(self):
        a_idx, b_idx = cstr_ainbp(["x", "y", "z"], ["y", "z", "w"])
        assert a_idx == [1, 2]
        assert b_idx == [0, 1]

    def test_no_overlap(self):
        a_idx, b_idx = cstr_ainbp(["a", "b", "c"], ["d", "e"])
        assert a_idx == []
        assert b_idx == []

    def test_complete_overlap(self):
        a_idx, b_idx = cstr_ainbp(["a", "b"], ["a", "b"])
        assert a_idx == [0, 1]
        assert b_idx == [0, 1]

    def test_empty_a(self):
        a_idx, b_idx = cstr_ainbp([], ["a", "b"])
        assert a_idx == []
        assert b_idx == []

    def test_empty_b(self):
        a_idx, b_idx = cstr_ainbp(["a", "b"], [])
        assert a_idx == []
        assert b_idx == []

    def test_both_empty(self):
        a_idx, b_idx = cstr_ainbp([], [])
        assert a_idx == []
        assert b_idx == []

    def test_case_sensitive(self):
        """CStrAinBP is case-sensitive."""
        a_idx, b_idx = cstr_ainbp(["Hello", "hello"], ["hello"])
        assert a_idx == [1]
        assert b_idx == [0]

    def test_duplicate_in_b_uses_first(self):
        """When B has duplicates, match to the first occurrence."""
        a_idx, b_idx = cstr_ainbp(["x"], ["x", "x"])
        assert a_idx == [0]
        assert b_idx == [0]

    def test_duplicate_in_a(self):
        """When A has duplicates, both match to the same B entry."""
        a_idx, b_idx = cstr_ainbp(["x", "x"], ["x"])
        assert a_idx == [0, 1]
        assert b_idx == [0, 0]

    def test_order_preserved(self):
        """Results are in order of appearance in A."""
        a_idx, b_idx = cstr_ainbp(["c", "a", "b"], ["b", "a"])
        assert a_idx == [1, 2]
        assert b_idx == [1, 0]

    def test_with_id_strings(self):
        """Test with the typical 'id{N}' format used throughout Forge."""
        all_ids = ["id100", "id200", "id300", "id400"]
        subset = ["id200", "id400"]
        a_idx, b_idx = cstr_ainbp(all_ids, subset)
        assert a_idx == [1, 3]
        assert b_idx == [0, 1]

    def test_single_element_match(self):
        a_idx, b_idx = cstr_ainbp(["only"], ["only"])
        assert a_idx == [0]
        assert b_idx == [0]

    def test_single_element_no_match(self):
        a_idx, b_idx = cstr_ainbp(["only"], ["other"])
        assert a_idx == []
        assert b_idx == []
