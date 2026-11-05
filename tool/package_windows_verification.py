#!/usr/bin/env python3
"""Package auditable Windows verification source, never a Windows executable.

Uses Python 3's standard library only. Sorted entries, fixed ZIP metadata and
content hashes make unchanged source produce an identical verification kit.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile
import zipfile


SOURCE_DIRECTORIES = (
    ".github", "assets", "docs", "lib", "macos", "test", "tool", "windows",
)
ROOT_FILES = (
    ".gitignore", ".metadata", "README.md", "analysis_options.yaml",
    "pubspec.lock", "pubspec.yaml",
)
EXCLUDED_COMPONENTS = {
    ".agents", ".aws", ".build", ".codex", ".dart_tool", ".git",
    ".history", ".idea", ".pub", ".pub-cache", ".swiftpm", "__pycache__",
    "build", "coverage", "credentials", "deriveddata", "dist", "ephemeral",
    "node_modules", "privatekeys", "secrets", "xcuserdata",
}
EXCLUDED_NAMES = {
    ".ds_store", ".flutter-plugins-dependencies", "auth.json",
    "flutter_export_environment.sh",
    "flutter-generated.xcconfig", "generated.xcconfig", "generated_config.cmake",
    "generated_plugin_registrant.cc", "generated_plugin_registrant.h",
    "generatedpluginregistrant.swift", "generated_plugins.cmake",
    "session.json", "workspacesettings.xcsettings",
}
EXCLUDED_SUFFIXES = {
    ".a", ".bak", ".cer", ".cert", ".crt", ".csr", ".db", ".db3", ".der",
    ".dll", ".dmg", ".dylib", ".exe", ".key", ".keystore", ".log",
    ".jks", ".kdbx", ".keychain", ".keychain-db", ".mobileprovision",
    ".p8", ".p12", ".p7b", ".p7c", ".pem", ".pfx", ".pkg", ".ppk",
    ".pyc", ".pyo", ".so", ".sqlite", ".sqlite3", ".swp", ".tmp",
    ".xcuserstate", ".zip",
}


def excluded(relative_path):
    """Exclude generated artifacts and common secret/database filenames."""
    parts = tuple(part.lower() for part in relative_path.parts)
    if any(part in EXCLUDED_COMPONENTS for part in parts):
        return True
    name = parts[-1]
    if name in EXCLUDED_NAMES or Path(name).suffix in EXCLUDED_SUFFIXES:
        return True
    if name == ".env" or name.startswith(".env."):
        return True
    if name.startswith(("renderer-session", "renderer_session.json")):
        return True
    if name.startswith("renderer") and "session" in name and name.endswith(".json"):
        return True
    if re.search(r"\.(?:db|db3|sqlite|sqlite3)(?:-(?:wal|shm|journal))?$", name):
        return True
    secret_name = r"(?:^|[._-])(?:credentials|private[-_]?key|secrets?)(?:[._-]|$)"
    if re.search(secret_name, name):
        return True
    return name.startswith(("id_rsa", "id_ed25519", "id_ecdsa"))


def source_files(project_root):
    """Walk only approved source roots, without following linked entries."""
    result = []
    for name in ROOT_FILES:
        path = project_root / name
        if path.is_symlink():
            raise ValueError("Root source file is a symlink: " + name)
        if not path.is_file():
            raise ValueError("Required source file is missing: " + name)
        result.append(path)
    for name in SOURCE_DIRECTORIES:
        source_root = project_root / name
        if source_root.is_symlink():
            raise ValueError("Source directory is a symlink: " + name)
        if not source_root.is_dir():
            raise ValueError("Required source directory is missing: " + name)
        for current, directories, files in os.walk(source_root, followlinks=False):
            current = Path(current)
            directories[:] = sorted(
                directory for directory in directories
                if not (current / directory).is_symlink()
                and not excluded((current / directory).relative_to(project_root))
            )
            for filename in sorted(files):
                path = current / filename
                if path.is_symlink() or excluded(path.relative_to(project_root)):
                    continue
                if stat.S_ISREG(path.stat().st_mode):
                    result.append(path)
    return sorted(
        result, key=lambda path: path.relative_to(project_root).as_posix()
    )


def archive_name_for(path, project_root):
    relative = path.relative_to(project_root)
    # Backslashes and drive syntax in a macOS filename must not become paths
    # outside the extraction folder when the kit is opened on Windows.
    if any("\\" in part or ":" in part for part in relative.parts):
        raise ValueError("Source filename is not safe for Windows: " + str(relative))
    return relative.as_posix()


def source_version(project_root):
    pubspec = project_root / "pubspec.yaml"
    if pubspec.is_symlink():
        raise ValueError("pubspec.yaml must be a regular source file.")
    version_pattern = (
        r"^version:\s*['\"]?"
        r"([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)"
        r"['\"]?\s*$"
    )
    match = re.search(
        version_pattern,
        pubspec.read_text(encoding="utf-8"), re.MULTILINE,
    )
    if match is None:
        raise ValueError("Cannot read a supported version from pubspec.yaml.")
    return match.group(1)


def start_instructions(version):
    return (
        "CANTIVRA " + version + " - WINDOWS VERIFICATION SOURCE KIT\n\n"
        "This archive contains source, not a compiled Windows application.\n"
        "Windows execution has not been verified by packaging this archive.\n\n"
        "Extract everything, open PowerShell in the folder with pubspec.yaml,\n"
        "and follow docs/WINDOWS_TESTING.md for prerequisites and manual gates.\n"
        "Install Flutter 3.38.5 (Dart 3.10.4), Git, Visual Studio Desktop\n"
        "development with C++, and a supported Windows SDK.\n\n"
        "Short automated verification:\n"
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\tool\\verify_windows.ps1\n\n"
        "Eight-hour automated verification:\n"
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\tool\\verify_windows.ps1 -EightHourSoak\n\n"
        "Each run retains evidence in build/qa/windows-verification.\n"
        "Return that run folder, manual outcomes and package hashes as described\n"
        "in docs/WINDOWS_TESTING.md. Native Windows close handling, physical HDMI,\n"
        "clean-machine offline launch, multilingual review and trusted release\n"
        "signing require separate results. Never attach renderer-session.json,\n"
        "real libraries, credentials, certificate passwords or private keys.\n"
    ).encode("utf-8")


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_archive(archive_path, expected_sources):
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or set(names) != set(expected_sources):
            raise ValueError("ZIP entry list differs from the source manifest.")
        corrupt = archive.testzip()
        if corrupt is not None:
            raise ValueError("ZIP integrity check failed: " + corrupt)
        for name in names:
            digest = hashlib.sha256()
            with archive.open(name) as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != expected_sources[name]:
                raise ValueError("ZIP source hash differs: " + name)


def package(project_root, output_directory):
    if project_root.is_symlink():
        raise ValueError("The project root must not be a symlink.")
    project_root = project_root.resolve()
    version = source_version(project_root)
    files = source_files(project_root)
    release = version.split("+", 1)[0]
    archive_name = "Cantivra-Windows-Verification-" + release + ".zip"
    output_directory.mkdir(parents=True, exist_ok=True)
    archive_path = output_directory / archive_name
    sources = {}
    with tempfile.TemporaryDirectory(
        prefix="cantivra-source-kit-", dir=output_directory
    ) as staging:
        staged_archive = Path(staging) / archive_name
        entries = {archive_name_for(path, project_root): path for path in files}
        entries["WINDOWS-START-HERE.txt"] = None
        with zipfile.ZipFile(
            staged_archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            for name, source in sorted(entries.items()):
                # Recheck before reading in case a source entry changed during traversal.
                if source is not None:
                    parents = []
                    parent = source.parent
                    while parent != project_root:
                        parents.append(parent)
                        parent = parent.parent
                    if source.is_symlink() or any(p.is_symlink() for p in parents):
                        raise ValueError("Source became a symlink: " + name)
                    data = source.read_bytes()
                else:
                    data = start_instructions(version)
                entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = (stat.S_IFREG | 0o644) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data, compresslevel=9)
                sources[name] = hashlib.sha256(data).hexdigest()
        verify_archive(staged_archive, sources)
        digest = file_sha256(staged_archive)
        manifest = {
            "formatVersion": 1,
            "application": "Cantivra",
            "version": version,
            "kind": "source verification kit",
            "windowsRuntimeVerified": False,
            "archive": archive_name,
            "archiveBytes": staged_archive.stat().st_size,
            "fileCount": len(sources),
            "sha256": digest,
            "sources": sources,
        }
        staged_manifest = Path(staging) / (archive_name + ".manifest.json")
        staged_manifest.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        staged_checksum = Path(staging) / (archive_name + ".sha256")
        staged_checksum.write_text(
            digest + "  " + archive_name + "\n", encoding="ascii"
        )
        # Complete validation before replacing any existing deliverables.
        staged_archive.replace(archive_path)
        staged_manifest.replace(output_directory / staged_manifest.name)
        staged_checksum.replace(output_directory / staged_checksum.name)
    verify_archive(archive_path, sources)
    if file_sha256(archive_path) != digest:
        raise ValueError("Final ZIP SHA-256 differs from its manifest.")
    return archive_path, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root", type=Path, default=Path(__file__).resolve().parent.parent
    )
    parser.add_argument(
        "--output", type=Path,
        help="Output directory (default: <project-root>/dist)."
    )
    args = parser.parse_args()
    output = args.output if args.output is not None else args.project_root / "dist"
    try:
        archive, manifest = package(args.project_root, output)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, "Source kit packaging failed: " + str(error) + "\n")
    print("Packaged " + str(archive))
    print("Source files: " + str(manifest["fileCount"]))
    print("SHA-256: " + manifest["sha256"])
    print("Windows runtime verified: false (requires execution on Windows)")


if __name__ == "__main__":
    main()
