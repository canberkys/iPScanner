#!/usr/bin/env python3
"""Guards against shipping an update that Sparkle would never offer.

Sparkle compares CFBundleVersion (CURRENT_PROJECT_VERSION), not the marketing
version. A release whose build number is not greater than the newest build in the
published appcast installs fine from the DMG but is never offered in-app.

Usage:
  check-release-version.py            # CI: project.yml must be consistent with appcast.xml
  check-release-version.py 1.3.2      # release: tag must match and the build must be new
"""
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def project_versions(text: str) -> tuple[str, int]:
    def setting(name: str) -> str:
        match = re.search(rf'^\s*{name}:\s*"?([^"\s]+)"?\s*$', text, re.MULTILINE)
        if not match:
            sys.exit(f"error: {name} not found in project.yml")
        return match.group(1)

    build = setting("CURRENT_PROJECT_VERSION")
    if not build.isdigit():
        sys.exit(f"error: CURRENT_PROJECT_VERSION must be an integer, got {build!r}")
    return setting("MARKETING_VERSION"), int(build)


def latest_published(appcast: Path) -> tuple[str, int] | None:
    items = []
    for item in ET.parse(appcast).getroot().iter("item"):
        build = item.findtext(f"{SPARKLE}version")
        short = item.findtext(f"{SPARKLE}shortVersionString")
        if build and build.strip().isdigit() and short:
            items.append((int(build), short.strip()))
    if not items:
        return None
    build, short = max(items)
    return short, build


def check(version: str | None, marketing: str, build: int, published: tuple[str, int] | None) -> list[str]:
    errors = []
    if version is not None and version != marketing:
        errors.append(f"tag version {version} does not match MARKETING_VERSION {marketing} in project.yml")
    if published is None:
        return errors
    pub_short, pub_build = published
    if build < pub_build:
        errors.append(f"CURRENT_PROJECT_VERSION {build} is lower than published build {pub_build} ({pub_short})")
    elif build == pub_build and marketing != pub_short:
        errors.append(
            f"MARKETING_VERSION is {marketing} but CURRENT_PROJECT_VERSION is still {build}, "
            f"the build of published {pub_short}; Sparkle would not offer this update. Increase it to {pub_build + 1}."
        )
    return errors


def main() -> None:
    version = sys.argv[1].removeprefix("v") if len(sys.argv) > 1 else None
    marketing, build = project_versions((ROOT / "project.yml").read_text(encoding="utf-8"))
    published = latest_published(ROOT / "appcast.xml")
    errors = check(version, marketing, build, published)
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if errors:
        sys.exit(1)
    print(f"ok: {marketing} (build {build}); latest published: {published[0]} (build {published[1]})" if published
          else f"ok: {marketing} (build {build}); no published builds")


if __name__ == "__main__":
    main()
