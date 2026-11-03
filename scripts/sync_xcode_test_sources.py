#!/usr/bin/env python3
"""Register all Swift test sources in project.pbxproj."""

from __future__ import annotations

import re
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "Milehound.xcodeproj" / "project.pbxproj"

UNIT_FILES = sorted((ROOT / "MilehoundTests").rglob("*.swift"))
UI_FILES = sorted((ROOT / "MilehoundUITests").rglob("*.swift")) if (ROOT / "MilehoundUITests").exists() else []

UNIT_SOURCES_PHASE = "0CB5EC5CDD2143B581DB8157"
UNIT_GROUP = "EAD0FC18DADB4E359AC65213"
UI_SOURCES_PHASE = "UITESTSRC00000000000001"
UI_GROUP = "UITESTGRP00000000000001"

STALE_TEST_FILENAMES = [
    "MilehoundTests.swift",
    "PairingAndCoordinatorTests.swift",
    "VehicleConnectRecordingTests.swift",
]


def new_id() -> str:
    return uuid.uuid4().hex[:24].upper()


def make_entries(files: list[Path]) -> tuple[str, str, str, str]:
    file_refs = []
    build_files = []
    group_children = []
    source_children = []
    for path in files:
        posix = path.relative_to(ROOT).as_posix()
        name = path.name
        file_id = new_id()
        build_id = new_id()
        file_refs.append(
            f"\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {posix}; sourceTree = SOURCE_ROOT; }};"
        )
        build_files.append(
            f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};"
        )
        group_children.append(f"\t\t\t\t{file_id} /* {name} */,")
        source_children.append(f"\t\t\t\t{build_id} /* {name} in Sources */,")
    return (
        "\n".join(file_refs),
        "\n".join(build_files),
        "\n".join(group_children),
        "\n".join(source_children),
    )


def strip_target_sources(text: str, filename: str) -> str:
    text = re.sub(
        rf"\n\t\t[A-Z0-9]+ /\* {re.escape(filename)} in Sources \*/ = \{{isa = PBXBuildFile; fileRef = [A-Z0-9]+ /\* {re.escape(filename)} \*/; \}};",
        "",
        text,
    )
    text = re.sub(
        rf"\n\t\t[A-Z0-9]+ /\* {re.escape(filename)} \*/ = \{{isa = PBXFileReference;.*?\}};",
        "",
        text,
        flags=re.DOTALL,
    )
    text = re.sub(rf"\n\t\t\t\t[A-Z0-9]+ /\* {re.escape(filename)} \*/,?", "", text)
    text = re.sub(
        rf"\n\t\t\t\t[A-Z0-9]+ /\* {re.escape(filename)} in Sources \*/,?",
        "",
        text,
    )
    return text


def replace_group_children(text: str, group_id: str, group_name: str, children: str) -> str:
    pattern = (
        rf"{group_id} /\* {re.escape(group_name)} \*/ = \{{\n"
        rf"\t\t\tisa = PBXGroup;\n"
        rf"\t\t\tchildren = \(\n"
        r".*?"
        rf"\t\t\t\);\n"
        rf"\t\t\tpath = {re.escape(group_name)};\n"
        rf"\t\t\tsourceTree = \"<group>\";\n"
        rf"\t\t\}};"
    )
    replacement = (
        f"{group_id} /* {group_name} */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"{children}\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = {group_name};\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise ValueError(f"Failed to replace group children for {group_name}")
    return updated


def replace_sources_phase(text: str, phase_id: str, children: str) -> str:
    marker_start = f"{phase_id} /* Sources */ = {{"
    marker_end = "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
    start = text.find(marker_start)
    if start == -1:
        raise ValueError(f"Missing sources phase {phase_id}")
    end = text.find(marker_end, start)
    if end == -1:
        raise ValueError(f"Missing end for sources phase {phase_id}")
    end += len(marker_end)
    replacement = (
        f"{phase_id} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n{children}\n\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    return text[:start] + replacement + text[end:]


def strip_existing_test_entries(text: str, files: list[Path]) -> str:
    for path in files:
        text = strip_target_sources(text, path.name)
    for stale in STALE_TEST_FILENAMES:
        text = strip_target_sources(text, stale)
    return text


def main() -> None:
    text = PBX.read_text()
    all_files = UNIT_FILES + UI_FILES
    text = strip_existing_test_entries(text, all_files)

    unit_refs, unit_builds, unit_group, unit_sources = make_entries(UNIT_FILES)
    ui_refs, ui_builds, ui_group, ui_sources = ("", "", "", "")
    if UI_FILES:
        ui_refs, ui_builds, ui_group, ui_sources = make_entries(UI_FILES)

    text = re.sub(
        r"/\* Begin PBXBuildFile section \*/\n",
        "/* Begin PBXBuildFile section */\n" + unit_builds + ("\n" + ui_builds if ui_builds else "") + "\n",
        text,
        count=1,
    )
    text = re.sub(
        r"/\* Begin PBXFileReference section \*/\n",
        "/* Begin PBXFileReference section */\n" + unit_refs + ("\n" + ui_refs if ui_refs else "") + "\n",
        text,
        count=1,
    )

    text = replace_group_children(text, UNIT_GROUP, "MilehoundTests", unit_group)
    text = replace_sources_phase(text, UNIT_SOURCES_PHASE, unit_sources)

    if UI_FILES:
        text = replace_group_children(text, UI_GROUP, "MilehoundUITests", ui_group)
        text = replace_sources_phase(text, UI_SOURCES_PHASE, ui_sources)

    PBX.write_text(text)
    print(f"Registered {len(UNIT_FILES)} unit test files")
    if UI_FILES:
        print(f"Registered {len(UI_FILES)} UI test files")


if __name__ == "__main__":
    main()
