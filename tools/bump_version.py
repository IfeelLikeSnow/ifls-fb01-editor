#!/usr/bin/env python3
"""Bump version in:
- main script header (-- @version)
- index.xml (<version name> + time=)

Usage:
  python tools/bump_version.py --version 0.2.0
"""
from __future__ import annotations
import argparse, re
from pathlib import Path
from datetime import datetime, timezone

def iso_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00","Z")

def bump_main(main_script: Path, version: str):
    txt = main_script.read_text(encoding="utf-8", errors="ignore")
    if re.search(r'--\s*@version\s+', txt[:2000]) is None:
        raise SystemExit("Main script has no @version header.")
    txt2 = re.sub(r'(--\s*@version\s+)([0-9]+(?:\.[0-9]+){1,3})', r'\g<1>'+version, txt, count=1)
    main_script.write_text(txt2, encoding="utf-8")

def bump_index(index_xml: Path, version: str):
    txt = index_xml.read_text(encoding="utf-8", errors="ignore")
    if 'time="' not in txt:
        raise SystemExit("index.xml version block missing time attribute.")
    txt = re.sub(r'(<version\s+name=")[^"]+(" )', r'\g<1>'+version+r'\2', txt, count=1)
    txt = re.sub(r'(time=")[^"]+(" )', r'\g<1>'+iso_now()+r'\2', txt, count=1)
    txt = re.sub(r'(time=")[^"]+("\>)', r'\g<1>'+iso_now()+r'\2', txt, count=1)
    index_xml.write_text(txt, encoding="utf-8")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".", help="Repo root")
    ap.add_argument("--version", required=True, help="New version, e.g. 0.2.0")
    args = ap.parse_args()

    root = Path(args.repo).resolve()
    main_script = root / "reaper" / "Scripts" / "IFLS_Workbench" / "Workbench" / "FB01" / "Editor" / "IFLS_FB01_SoundEditor.lua"
    index_xml = root / "index.xml"
    bump_main(main_script, args.version)
    bump_index(index_xml, args.version)
    print(f"Bumped to {args.version}")

if __name__ == "__main__":
    main()
