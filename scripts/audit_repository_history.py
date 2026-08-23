#!/usr/bin/env python3
"""Fail when reachable Git history contains private release metadata."""

from __future__ import annotations

import argparse
import base64
import re
import subprocess
import sys
from pathlib import Path


def git(*arguments: str) -> bytes:
    completed = subprocess.run(
        ["git", *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.decode("utf-8", errors="replace").strip())
    return completed.stdout


def encoded_forms(value: str) -> tuple[bytes, ...]:
    return tuple(value.encode(encoding) for encoding in ("utf-8", "utf-16-le", "utf-16-be"))


def contains_token(data: bytes, token: str) -> bool:
    return any(encoded in data for encoded in encoded_forms(token))


def forbidden_tokens() -> tuple[str, ...]:
    return (
        "/" + "Us" + "ers/",
        "/" + "Vol" + "umes/",
        "wei" + "chaoshen",
        "fc" + "no2",
        "recipe" + "20250101",
        "recipe" + "20260615" + ".fcp" + "bundle",
        "chinese" + " pancake",
        "pancake" + "20260812",
        "2026" + "0820",
        "2026" + "0821",
    )


def reachable_blobs() -> list[tuple[str, str]]:
    objects = git("rev-list", "--objects", "--all").decode("utf-8", errors="surrogateescape")
    blobs: list[tuple[str, str]] = []
    seen: set[str] = set()
    for line in objects.splitlines():
        object_id, separator, path = line.partition(" ")
        if not separator or object_id in seen:
            continue
        if git("cat-file", "-t", object_id).strip() != b"blob":
            continue
        seen.add(object_id)
        blobs.append((object_id, path))
    return blobs


def decoded_xml(data: bytes) -> str | None:
    for encoding in ("utf-8", "utf-16-le", "utf-16-be"):
        try:
            text = data.decode(encoding)
        except UnicodeDecodeError:
            continue
        if "<" in text:
            return text
    return None


def audit_blobs() -> list[str]:
    violations: list[str] = []
    opening = "<" + "book" + "mark"
    paired = re.compile(
        re.escape(opening) + r"(?:\s[^>]*)?>([A-Za-z0-9+/=\s]*)</bookmark>",
        re.IGNORECASE,
    )
    tokens = forbidden_tokens()

    for object_id, path in reachable_blobs():
        data = git("cat-file", "blob", object_id)
        for index, token in enumerate(tokens):
            if contains_token(data, token):
                violations.append(f"{object_id[:12]} {path}: private-token-{index}")

        if not path.lower().endswith((".fcpxml", ".xml")):
            continue
        text = decoded_xml(data)
        if text is None:
            violations.append(f"{object_id[:12]} {path}: undecodable-xml")
            continue
        if opening.lower() in text.lower():
            violations.append(f"{object_id[:12]} {path}: bookmark-element")
        for payload_index, match in enumerate(paired.finditer(text)):
            payload = "".join(match.group(1).split())
            try:
                decoded = base64.b64decode(payload, validate=True)
            except ValueError:
                violations.append(f"{object_id[:12]} {path}: malformed-bookmark-{payload_index}")
                continue
            for token_index, token in enumerate(tokens):
                if contains_token(decoded, token):
                    violations.append(
                        f"{object_id[:12]} {path}: bookmark-{payload_index}-private-token-{token_index}"
                    )
    return violations


def audit_authors(require_noreply: bool) -> list[str]:
    if not require_noreply:
        return []
    output = git("log", "--all", "--format=%H%x00%ae%x00%ce").decode("utf-8", errors="replace")
    violations: list[str] = []
    for line in output.splitlines():
        commit, author, committer = line.split("\0")
        for role, email in (("author", author), ("committer", committer)):
            if not email.lower().endswith("@users.noreply.github.com"):
                violations.append(f"{commit[:12]}: non-noreply-{role}-email")
    return violations


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-noreply-authors", action="store_true")
    arguments = parser.parse_args()

    if not Path(".git").exists():
        print("audit_repository_history.py: run from a Git working tree root", file=sys.stderr)
        return 2
    try:
        violations = audit_blobs() + audit_authors(arguments.require_noreply_authors)
    except RuntimeError as error:
        print(f"audit_repository_history.py: {error}", file=sys.stderr)
        return 2

    if violations:
        print("reachable Git history privacy audit: FAIL", file=sys.stderr)
        for violation in sorted(set(violations)):
            print(f"- {violation}", file=sys.stderr)
        return 1
    print("reachable Git history privacy audit: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
