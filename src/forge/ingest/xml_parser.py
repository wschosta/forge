"""Congressional XML bill parser — replaces +la/xmlparse.m.

Parses XML files from data/congressional_archive/ to extract bill titles,
policy areas, summary text, and legislative subject areas. This data is
used to train the bill classification learning algorithm.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence
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
        if text_el is not None and text_el.text:
            if "(This measure has not been amended" not in text_el.text:
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

    xml_files = sorted(xml_dir.glob("*.xml"))
    if not xml_files:
        logger.warning("No XML files found in %s", xml_dir)
        return []

    parsed: list[ParsedBill] = []
    incomplete = 0

    for xml_file in xml_files:
        try:
            tree = etree.parse(str(xml_file))
        except (ParseError, etree.XMLSyntaxError) as e:
            logger.warning("Failed to parse %s: %s", xml_file.name, e)
            incomplete += 1
            continue

        root = tree.getroot()
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
