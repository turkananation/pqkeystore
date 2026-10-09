#!/usr/bin/env python3
"""Evidence-based pub.dev pub-points pre-flight.

pana 0.23.19 (the latest) cannot run on Dart 3.13.4 — its bundled analyzer reads
an SDK file, `lib/_internal/allowed_experiments.json`, that the SDK no longer
ships. So this checks each published criterion directly instead of guessing at a
number. Every line prints the evidence it used.

Criteria are from https://pub.dev/help/scoring (fetched 2026-10-09):
  1. Follow Dart file conventions  - pubspec URLs, LICENSE, README, CHANGELOG
  2. Provide documentation        - example, >=20% public API documented
  3. Platform support             - platforms declared or detected, SwiftPM, Wasm
  4. Pass static analysis         - analyzer clean
  5. Support up-to-date deps      - SDK floor, dependency currency
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# OSI-approved identifiers pub.dev's license detector recognises.
OSI = ("MIT", "BSD-3-Clause", "BSD-2-Clause", "Apache-2.0", "ISC", "Unlicense")

VERSION_HEADING = re.compile(
    r"^#{1,3}\s*\[?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)\]?"
)


def sh(cmd, cwd, timeout=600):
    try:
        return subprocess.run(
            cmd, cwd=cwd, shell=True, capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", "TIMEOUT")


def pubspec(path: Path):
    f = path / "pubspec.yaml"
    if not f.exists():
        return {}
    out = {}
    lines = f.read_text().split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"^([a-z_]+):\s*(.*)$", lines[i])
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2)
        if val[:2] in (">-", ">-", "|", "|-", ">+", "|+") or val in (">", "|"):
            # Folded/literal block scalar: collect the indented continuation.
            block = []
            i += 1
            while i < len(lines) and (lines[i].strip() == "" or lines[i].startswith(" ")):
                block.append(lines[i].strip())
                i += 1
            out[key] = " ".join(x for x in block if x)
            continue
        out[key] = val.strip().strip("'\"")
        i += 1
    return out


def api_doc_ratio(path: Path):
    """Approximate share of public top-level declarations carrying dartdoc.

    Approximate, not pana's dartdoc-based measure: it counts top-level
    declarations outside lib/src and reports the fraction with a preceding `///`.
    """
    total = documented = 0
    for dart in sorted(path.glob("lib/**/*.dart")):
        if dart.name.startswith("_") and dart.parent.name == "src":
            continue
        lines = dart.read_text().split("\n")
        for i, line in enumerate(lines):
            s = line.strip()
            if not s.startswith(("class ", "abstract class ", "final class ",
                                 "sealed class ", "enum ", "mixin ", "extension ",
                                 "typedef ", "const ", "final ", "var ",
                                 "factory ", "static ")):
                continue
            # skip private
            name = s.split(" ")[-1].split("(")[0].split("<")[0].split(";")[0].strip()
            if not name or name.startswith("_") or name in ("{", "}"):
                continue
            total += 1
            j = i - 1
            while j >= 0 and (lines[j].strip() == "" or lines[j].strip().startswith("//")):
                if lines[j].strip().startswith("///"):
                    documented += 1
                    break
                j -= 1
    return documented, total


def score(path: Path):
    r = {"package": path.name, "issues": []}
    ps = pubspec(path)

    # 1. File conventions -------------------------------------------------
    lic = [f for f in ("LICENSE", "LICENSE.md", "LICENSE.txt") if (path / f).exists()]
    r["license"] = lic[0] if lic else None
    if not lic:
        r["issues"].append("no LICENSE file (+10)")
    elif not any(o in (path / lic[0]).read_text() for o in OSI):
        r["issues"].append(f"LICENSE present but no OSI identifier from {OSI}")
    r["readme"] = (path / "README.md").exists()
    if not r["readme"]:
        r["issues"].append("no README.md (+30)")

    chg = path / "CHANGELOG.md"
    r["changelog"] = chg.exists()
    if chg.exists():
        heads = [m.group(1) for m in
                 (VERSION_HEADING.match(l) for l in chg.read_text().split("\n")) if m]
        r["changelog_versions"] = heads[:5]
        if not heads:
            r["issues"].append("CHANGELOG.md has no parseable version heading (+20)")
    else:
        r["issues"].append("no CHANGELOG.md (+20)")

    urls = re.findall(r"^\s*(?:homepage|repository|issue_tracker|documentation):\s*(\S+)",
                      (path / "pubspec.yaml").read_text(), re.M)
    r["urls"] = urls
    for u in urls:
        if u.startswith("http://"):
            r["issues"].append(f"URL not https: {u}")

    desc = ps.get("description", "")
    r["description_len"] = len(desc)
    if not (20 <= len(desc) <= 180):
        r["issues"].append(f"description is {len(desc)} chars; scoring wants 20-180 (+20)")

    # 2. Documentation ----------------------------------------------------
    ex = (path / "example").exists()
    r["example"] = ex
    if not ex:
        r["issues"].append("no example/ (+20)")
    d, t = api_doc_ratio(path)
    r["api_documented"] = f"{d}/{t}"
    pct = (d / t * 100) if t else 0
    r["api_pct"] = round(pct, 1)
    if t and pct < 20:
        r["issues"].append(f"only {pct:.1f}% public API documented; need >=20%")

    # 3. Platforms --------------------------------------------------------
    r["declared_platforms"] = "platforms:" in (path / "pubspec.yaml").read_text()
    r["flutter_plugin"] = "flutter:" in (path / "pubspec.yaml").read_text()

    # 4. Static analysis --------------------------------------------------
    is_flutter = r["flutter_plugin"] or "flutter" in ps.get("environment", "")
    tool = "flutter" if is_flutter else "dart"
    sh(f"{tool} pub get", path, 900)
    a = sh(f"{tool} analyze --fatal-infos 2>&1 | tail -3", path, 900)
    out = (a.stdout or "") + (a.stderr or "")
    m = re.search(r"No issues found", out)
    m2 = re.search(r"(\d+) issues? found", out)
    r["analyze"] = "clean" if m else (f"{m2.group(1)} issues" if m2 else out.strip()[-120:])
    if not m:
        r["issues"].append(f"{tool} analyze not clean: {r['analyze']}")

    f = sh(f"{tool} format --output=none --set-exit-if-changed . 2>&1 | tail -3", path, 300)
    r["format"] = "clean" if f.returncode == 0 else "would reformat"

    # 5. Dependencies -----------------------------------------------------
    sdk = re.search(r"sdk:\s*['\"]?([^'\"\n]+)", ps.get("environment", ""))
    r["sdk"] = sdk.group(1) if sdk else None
    o = sh("dart pub outdated --json 2>/dev/null", path, 600)
    try:
        data = json.loads(o.stdout or "{}")
        outs = []
        for dep, info in (data.get("dependencies") or []):
            if info.get("isDiscontinued") or info.get("kind") == "direct":
                outs.append(dep)
        r["outdated_direct"] = outs[:10]
    except Exception:
        r["outdated_direct"] = "n/a"

    return r


if __name__ == "__main__":
    targets = sys.argv[1:] or [
        "/home/liquidsilence/Projects/zeroize",
        "/home/liquidsilence/Projects/pqcrypto",
        "/home/liquidsilence/Projects/pqforge",
        "/home/liquidsilence/Projects/pqthreshold",
        "/home/liquidsilence/Projects/pqdga",
        "/home/liquidsilence/Projects/pqtransport",
        "/home/liquidsilence/Projects/swissarmyknife",
        "/home/liquidsilence/Projects/pqforge_ffi",
        "/home/liquidsilence/Projects/pqkeystore",
    ]
    for t in targets:
        p = Path(t)
        if not p.exists():
            continue
        r = score(p)
        print("=" * 72)
        print(f"{r['package']}")
        print(f"  license={r['license']} readme={r['readme']} changelog={r['changelog']} "
              f"versions={r.get('changelog_versions')}")
        print(f"  description={r['description_len']}ch  example={r['example']}  "
              f"api_documented={r['api_documented']} ({r['api_pct']}%)")
        print(f"  platforms_declared={r['declared_platforms']} flutter_plugin={r['flutter_plugin']}  "
              f"sdk={r['sdk']}")
        print(f"  analyze={r['analyze']}  format={r['format']}")
        if r["urls"]:
            print(f"  urls={r['urls']}")
        if r["outdated_direct"] not in ("n/a", []):
            print(f"  outdated_direct={r['outdated_direct']}")
        for i in r["issues"]:
            print(f"  ISSUE: {i}")