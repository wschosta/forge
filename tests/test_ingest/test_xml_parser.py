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


class TestZipArchiveReading:
    """The corpus is read from its zip archives, not only loose XML files.

    The ~35,000 loose ``BILLSTATUS-*.xml`` files were byte-identical to the
    contents of the 24 archives under ``Store/``, so only the archives are
    committed. Parsing has to work from those alone.
    """

    def test_reads_bills_from_archives(self, xml_dir: Path):
        from forge.ingest.xml_parser import iter_xml_documents

        documents = list(iter_xml_documents(xml_dir))
        assert len(documents) > 30_000
        assert all(name.endswith(".xml") for name, _ in documents)
        assert all(data.lstrip().startswith(b"<") for _, data in documents[:20])

    def test_yields_each_bill_once(self, xml_dir: Path):
        """A bill present both loose and in an archive must not be parsed twice."""
        from forge.ingest.xml_parser import iter_xml_documents

        names = [name for name, _ in iter_xml_documents(xml_dir)]
        assert len(names) == len(set(names))

    def test_loose_file_takes_precedence_over_archive(self, tmp_path: Path):
        """An extracted or edited loose file wins over the archived copy."""
        import zipfile

        from forge.ingest.xml_parser import iter_xml_documents

        archive_dir = tmp_path / "Store"
        archive_dir.mkdir()
        with zipfile.ZipFile(archive_dir / "bills.zip", "w") as zf:
            zf.writestr("BILLSTATUS-1.xml", "<archived/>")
        (tmp_path / "BILLSTATUS-1.xml").write_text("<loose/>")

        documents = dict(iter_xml_documents(tmp_path))
        assert documents["BILLSTATUS-1.xml"] == b"<loose/>"

    def test_unreadable_archive_is_skipped_not_fatal(self, tmp_path: Path):
        from forge.ingest.xml_parser import iter_xml_documents

        (tmp_path / "broken.zip").write_text("not a zip")
        (tmp_path / "BILLSTATUS-1.xml").write_text("<bill/>")

        documents = dict(iter_xml_documents(tmp_path))
        assert set(documents) == {"BILLSTATUS-1.xml"}
