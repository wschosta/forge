"""Data ingestion layer for LegiScan CSV/JSON and Congressional XML."""

from forge.ingest.csv_reader import read_all_csv
from forge.ingest.json_reader import read_all_json
from forge.ingest.xml_parser import parse_congressional_xml

__all__ = ["read_all_csv", "read_all_json", "parse_congressional_xml"]
