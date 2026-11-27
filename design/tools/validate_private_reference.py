#!/usr/bin/env python3
"""Audit the approved private development index without printing source prose."""

import argparse
from contextlib import closing
import hashlib
from pathlib import Path
import re
import sqlite3
import sys


APPROVED_SHA256 = "197734c2a4a58078e08894d9cb5d3392c4d4ba42ff02e351a10c55e3585a08b0"
EXPECTED_COUNTS = {
    "reference_documents": 4,
    "reference_pages": 1327,
    "reference_outline": 2701,
    "catalog": 1968,
    "spell_classes": 778,
    "references_map": 4903,
}
EXPECTED_GAPS = {"no_text": 44, "sparse_text": 11}
SHA256_PATTERN = re.compile(r"[0-9a-fA-F]{64}")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate(path, source_directory):
    if sha256(path) != APPROVED_SHA256:
        raise ValueError("Database SHA-256 differs from the approved development artifact.")

    # The approved artifact is a complete, checksum-pinned file with no sidecars.
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True)) as db:
        db.execute("PRAGMA query_only = ON")
        if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise ValueError("SQLite integrity_check reported errors.")
        if db.execute("PRAGMA foreign_key_check").fetchone() is not None:
            raise ValueError("SQLite foreign_key_check reported violations.")

        for table, expected in EXPECTED_COUNTS.items():
            count = db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            if count != expected:
                raise ValueError(f"{table}: expected {expected} rows, found {count}.")
            print(f"{table}: {count}")

        ruleset = db.execute("SELECT value FROM metadata WHERE key = 'ruleset'").fetchone()
        if ruleset != ("5e-2014-2018",):
            raise ValueError("Unexpected structured catalogue ruleset.")

        documents = db.execute(
            "SELECT id, filename, sha256, page_count FROM reference_documents ORDER BY id"
        ).fetchall()
        gaps = dict(db.execute(
            "SELECT quality, count(*) FROM reference_pages "
            "WHERE quality IN ('no_text', 'sparse_text') GROUP BY quality"
        ))
        if gaps != EXPECTED_GAPS:
            raise ValueError(f"Unexpected page-quality counts: {gaps}.")
        print("Page extraction gaps: " + ", ".join(f"{count} {quality}" for quality, count in gaps.items()) + ".")

        for sequence, (document_id, filename, digest, page_count) in enumerate(documents, 1):
            if not isinstance(digest, str) or SHA256_PATTERN.fullmatch(digest) is None:
                raise ValueError(f"Document {sequence} has invalid source SHA-256 metadata.")
            if not isinstance(page_count, int) or page_count < 1:
                raise ValueError(f"Document {sequence} has invalid source page count.")
            if source_directory is not None:
                if not filename or filename in (".", "..") or "/" in filename or "\\" in filename:
                    raise ValueError(f"Document {sequence} has an unsafe source filename.")
                if sha256(source_directory / filename) != digest.lower():
                    raise ValueError(f"Source PDF {sequence} does not match its recorded SHA-256.")

            pages = {
                page: quality
                for page, quality in db.execute(
                    "SELECT pdf_page, quality FROM reference_pages WHERE document_id = ?",
                    (document_id,),
                )
            }
            expected_pages = set(range(1, page_count + 1))
            outline_out_of_range = db.execute(
                "SELECT count(*) FROM reference_outline "
                "WHERE document_id = ? AND (pdf_page IS NULL OR pdf_page NOT BETWEEN 1 AND ?)",
                (document_id, page_count),
            ).fetchone()[0]
            print(f"Document {sequence}: {len(pages)}/{page_count} indexed physical pages.")
            if outline_out_of_range:
                print(f"  outline entries without an in-range physical page: {outline_out_of_range}")
            for label, numbers in (
                ("missing", expected_pages - pages.keys()),
                ("out-of-range", pages.keys() - expected_pages),
                ("no text", [page for page, quality in pages.items() if quality == "no_text"]),
                ("sparse text", [page for page, quality in pages.items() if quality == "sparse_text"]),
            ):
                if numbers:
                    print(f"  {label}: {', '.join(map(str, sorted(numbers)))}")

        hits = db.execute(
            "SELECT count(*) FROM reference_search "
            "JOIN reference_pages ON reference_pages.id = reference_search.rowid "
            "WHERE reference_search MATCH ?",
            ("fireball",),
        ).fetchone()[0]
        if hits != 50:
            raise ValueError(f"Expected 50 linked FTS hits for the approved probe, found {hits}.")
        print("FTS: 50 linked hits for the approved probe.")
        if source_directory is None:
            print("Source PDF checksums have valid metadata. Supply --source-pdfs to compare originals.")
        else:
            print(f"All {len(documents)} source PDF files match the recorded checksums.")
        print("The structured catalogue and indexed book pages were checked separately.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path, help="Path to the authorized private_rules.db file")
    parser.add_argument("--source-pdfs", type=Path, help="Directory of authorized original PDFs")
    args = parser.parse_args()
    try:
        validate(args.database.resolve(), args.source_pdfs)
    except (OSError, ValueError, sqlite3.Error) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
