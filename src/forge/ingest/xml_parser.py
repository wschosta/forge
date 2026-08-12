"""Congressional XML bill parser — replaces +la/xmlparse.m.

Parses XML files from data/congressional_archive/ to extract bill titles,
policy areas, summary text, and legislative subject areas. This data is
used to train the bill classification learning algorithm.
"""

from __future__ import annotations

import logging
import zipfile
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from xml.etree.ElementTree import ParseError

from lxml import etree

logger = logging.getLogger(__name__)


@dataclass
class ParsedBill:
    """A single congressional bill parsed from XML."""

    title: str = ""
    policy_area: str = ""
    text: str = ""  # Summary text (from CDATA)
    subject_areas: list[str] = field(default_factory=list)
    filename: str = ""


def _extract_best_summary(bill_element: etree._Element) -> str:
    """Extract the best available summary text from a bill XML element.

    If multiple summaries exist, pick the last one that is NOT the
    "This measure has not been amended" placeholder. This matches the
    MATLAB logic which iterates backwards.
    """
    items = bill_element.findall(".//summaries/billSummaries/item")
    if not items:
        return ""

    if len(items) == 1:
        text_el = items[0].find("text")
        return text_el.text if text_el is not None and text_el.text else ""

    # Multiple summaries: find the last one that's not the placeholder
    for item in reversed(items):
        text_el = item.find("text")
        if text_el is not None and text_el.text and "(This measure has not been amended" not in text_el.text:
            return text_el.text

    # Fallback to the last summary
    text_el = items[-1].find("text")
    return text_el.text if text_el is not None and text_el.text else ""


def _extract_subjects(bill_element: etree._Element) -> list[str]:
    """Extract legislative subject area names from a bill XML element."""
    items = bill_element.findall(".//subjects/legislativeSubjects/item")
    subjects = []
    for item in items:
        name_el = item.find("name")
        if name_el is not None and name_el.text:
            subjects.append(name_el.text)
    return subjects


def iter_xml_documents(xml_dir: str | Path) -> Iterator[tuple[str, bytes]]:
    """Yield ``(filename, contents)`` for every bill XML under a directory.

    The congressional corpus is stored twice: as ~35,000 loose
    ``BILLSTATUS-*.xml`` files and as the zip archives they were extracted
    from, under ``Store/``. Reading the archives directly means the loose copies
    do not have to be committed, which is worth roughly 35,000 files in the
    repository. Both forms are still accepted so an already-extracted working
    directory keeps working.

    A bill present in both forms is yielded once. The loose file wins, on the
    grounds that anyone who extracted or edited one meant to use it.

    Args:
        xml_dir: Directory holding loose ``*.xml`` files, ``*.zip`` archives, or
            a ``Store/`` subdirectory of archives.

    Yields:
        Tuples of (filename, raw XML bytes), ordered by filename.
    """
    xml_dir = Path(xml_dir)
    seen: set[str] = set()
    documents: list[tuple[str, bytes]] = []

    for xml_file in sorted(xml_dir.glob("*.xml")):
        seen.add(xml_file.name)
        documents.append((xml_file.name, xml_file.read_bytes()))

    archives = sorted(xml_dir.glob("*.zip")) + sorted((xml_dir / "Store").glob("*.zip"))
    for archive in archives:
        try:
            with zipfile.ZipFile(archive) as zf:
                for entry in zf.namelist():
                    name = Path(entry).name
                    if not name.endswith(".xml") or name in seen:
                        continue
                    seen.add(name)
                    documents.append((name, zf.read(entry)))
        except (zipfile.BadZipFile, OSError) as exc:
            logger.warning("Could not read archive %s: %s", archive, exc)

    documents.sort(key=lambda item: item[0])
    yield from documents


def parse_congressional_xml(
    xml_dir: str | Path = "data/congressional_archive",
) -> list[ParsedBill]:
    """Parse all congressional XML bill files in a directory.

    Replaces la.xmlparse(). Only returns bills that have all required fields:
    title, policyArea, and at least one summary text.

    Args:
        xml_dir: Path to directory containing BILLSTATUS-*.xml files.

    Returns:
        List of ParsedBill objects for all complete bills.
    """
    xml_dir = Path(xml_dir)
    if not xml_dir.is_dir():
        raise FileNotFoundError(f"XML directory not found: {xml_dir}")

    documents = list(iter_xml_documents(xml_dir))
    if not documents:
        logger.warning("No XML documents found in %s (looked for *.xml and *.zip)", xml_dir)
        return []

    parsed: list[ParsedBill] = []
    incomplete = 0

    for name, data in documents:
        try:
            root = etree.fromstring(data)
        except (ParseError, etree.XMLSyntaxError) as e:
            logger.warning("Failed to parse %s: %s", name, e)
            incomplete += 1
            continue

        xml_file = Path(name)
        bill = root.find("bill")
        if bill is None:
            incomplete += 1
            continue

        # Extract title
        title_el = bill.find("title")
        if title_el is None or not title_el.text:
            incomplete += 1
            continue

        # Extract policy area
        policy_el = bill.find("policyArea/name")
        if policy_el is None or not policy_el.text:
            incomplete += 1
            continue

        # Extract summary text
        summary_text = _extract_best_summary(bill)
        if not summary_text:
            incomplete += 1
            continue

        # Extract subjects (may be empty — that's OK)
        subjects = _extract_subjects(bill)

        parsed.append(
            ParsedBill(
                title=title_el.text,
                policy_area=policy_el.text,
                text=summary_text,
                subject_areas=subjects,
                filename=xml_file.name,
            )
        )

    logger.info("XML parse complete: %d bills parsed, %d incomplete", len(parsed), incomplete)
    return parsed
