"""Tests for forge.ingest.xml_parser."""

from pathlib import Path

import pytest

from forge.ingest.xml_parser import ParsedBill, parse_congressional_xml


@pytest.fixture
def xml_dir() -> Path:
    return Path("data/congressional_archive")


class TestParseCongressionalXml:
    def test_parses_bills(self, xml_dir: Path):
        if not xml_dir.exists():
            pytest.skip("Congressional XML data not available")
        bills = parse_congressional_xml(xml_dir)
        assert len(bills) > 0
        assert all(isinstance(b, ParsedBill) for b in bills)

    def test_all_bills_have_required_fields(self, xml_dir: Path):
        if not xml_dir.exists():
            pytest.skip("Congressional XML data not available")
        bills = parse_congressional_xml(xml_dir)
        for bill in bills[:100]:  # Check first 100
            assert bill.title, f"Bill {bill.filename} missing title"
            assert bill.policy_area, f"Bill {bill.filename} missing policy_area"
            assert bill.text, f"Bill {bill.filename} missing text"

    def test_policy_areas_are_nonempty_strings(self, xml_dir: Path):
        if not xml_dir.exists():
            pytest.skip("Congressional XML data not available")
        bills = parse_congressional_xml(xml_dir)
        policy_areas = {b.policy_area for b in bills}
        assert len(policy_areas) > 5, "Should have multiple distinct policy areas"

    def test_significant_number_of_bills_parsed(self, xml_dir: Path):
        if not xml_dir.exists():
            pytest.skip("Congressional XML data not available")
        bills = parse_congressional_xml(xml_dir)
        # We know there are ~34k XML files; at least half should parse
        assert len(bills) > 10000

    def test_invalid_directory_raises(self):
        with pytest.raises(FileNotFoundError):
            parse_congressional_xml("/nonexistent/path")
