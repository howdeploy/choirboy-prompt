#!/usr/bin/env python3
"""Drive agent-authored project artifacts through lifecycle hooks.

This script intentionally does not write artifact content. It discovers the
projects described by the canonical lore, validates dossiers the agent wrote
when the user asked for an update, and records a freshness manifest. A missing
or damaged artifact root is restored from the ready bundle shipped with the
plugin when that bundle still matches the canonical sources. Stop hooks do not
continue the turn and do not demand dossier authorship.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import shutil
import sys
import tempfile
import unicodedata
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_VERSION = 1
REQUEST_FILE = ".artifact-request.json"
MANIFEST_FILE = ".artifact-manifest.json"
MIGRATION_FILE = ".artifact-migration.json"
INDEX_FILE = "INDEX.md"
PROJECTS_DIR = "projects"
# Claude Code shows the model only the first 2,000 characters of an oversized
# hook field and will not raise the 10,000-character cap. Stay under the preview.
SESSION_STATUS_CHAR_LIMIT = 1800

CORE_SOURCES = (
    "prompt.md",
    "security-posture.md",
    "lore.md",
    "user.md",
    "context/research-index.md",
)

REQUIRED_SECTIONS = (
    "Canon",
    "Goal and Outcome",
    "Architecture and Components",
    "Decisions and Constraints",
    "Operating Workflow",
    "Lessons and Rules",
    "Sources",
    "Unknowns",
    "When to Revisit",
)

ENGLISH_SIGNAL_WORDS = frozenset(
    "and are by each for from is it its must of only our should that the their "
    "they this through to under use used uses using was we when where which while "
    "will with without your".split()
)
MIN_ENGLISH_SIGNAL_RATIO = 0.08

CYRILLIC_TRANSLITERATION = str.maketrans(
    {
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e",
        "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "i", "к": "k",
        "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
        "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "",
        "э": "e", "ю": "yu", "я": "ya",
    }
)


class ArtifactError(RuntimeError):
    """A user-actionable artifact protocol failure."""


def resolve_artifact_root(value: Path) -> Path:
    """Resolve an artifact root without accepting managed-directory symlinks."""

    candidate = value.expanduser()
    if candidate.is_symlink():
        raise ArtifactError(f"refusing symlink artifact root: {candidate}")
    artifact_root = candidate.resolve()
    if artifact_root == Path(artifact_root.anchor):
        raise ArtifactError(
            f"refusing filesystem root as artifact directory: {artifact_root}"
        )
    projects_root = artifact_root / PROJECTS_DIR
    if projects_root.is_symlink():
        raise ArtifactError(f"refusing symlink projects directory: {projects_root}")
    return artifact_root


def normalize_text(value: str) -> str:
    return value.replace("\r\n", "\n").replace("\r", "\n")


def has_non_latin_alphabetic(value: str) -> bool:
    for character in value:
        if not character.isalpha() or character.isascii():
            continue
        if not unicodedata.name(character, "").startswith("LATIN "):
            return True
    return False


def looks_like_english_prose(value: str) -> bool:
    prose = re.sub(r"```.*?```", " ", value, flags=re.DOTALL)
    prose = re.sub(r"`[^`\n]*`", " ", prose)
    prose = "\n".join(
        line for line in prose.splitlines() if not line.lstrip().startswith("#")
    )
    words = re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", prose.casefold())
    if len(words) < 40:
        return False
    signals = sum(word in ENGLISH_SIGNAL_WORDS for word in words)
    distinct_signals = {word for word in words if word in ENGLISH_SIGNAL_WORDS}
    return (
        len(distinct_signals) >= 6
        and signals >= 6
        and signals / len(words) >= MIN_ENGLISH_SIGNAL_RATIO
    )


def read_text(path: Path) -> str:
    try:
        return normalize_text(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ArtifactError(f"cannot read {path}: {exc}") from exc


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def atomic_write(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ArtifactError(f"refusing to replace symlink: {path}")
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.tmp.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(value)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def write_if_changed(path: Path, value: str) -> None:
    if path.is_file() and not path.is_symlink() and read_text(path) == value:
        return
    atomic_write(path, value)


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def source_paths(source_root: Path) -> list[Path]:
    paths: list[Path] = []
    for relative in CORE_SOURCES:
        path = source_root / relative
        if not path.is_file():
            raise ArtifactError(f"canonical source is missing: {path}")
        paths.append(path)
    research_root = source_root / "research"
    if not research_root.is_dir():
        raise ArtifactError(f"research directory is missing: {research_root}")
    paths.extend(sorted(research_root.rglob("*.md"), key=lambda item: item.as_posix()))
    return paths


def relative_path(path: Path, source_root: Path) -> str:
    return path.relative_to(source_root).as_posix()


def source_bundle_digest(paths: list[Path], source_root: Path) -> str:
    digest = hashlib.sha256()
    for path in paths:
        relative = relative_path(path, source_root)
        digest.update(f"path:{relative}\n".encode())
        digest.update(read_text(path).encode("utf-8"))
        digest.update(b"\n\0\n")
    return digest.hexdigest()


def slugify(title: str, ordinal: int) -> str:
    transliterated = title.lower().translate(CYRILLIC_TRANSLITERATION)
    ascii_title = (
        unicodedata.normalize("NFKD", transliterated)
        .encode("ascii", "ignore")
        .decode("ascii")
    )
    words = re.findall(r"[a-z0-9]+", ascii_title)
    body = "-".join(words)[:56].strip("-")
    if not body:
        body = f"project-{sha256_text(title)[:10]}"
    return f"{ordinal:02d}-{body}"


def extract_lore_projects(lore: str) -> list[dict[str, str]]:
    headings = list(re.finditer(r"(?m)^###\s+(.+?)\s*$", lore))
    if not headings:
        raise ArtifactError("lore.md must contain at least one level-three project heading")
    projects: list[dict[str, str]] = []
    seen: set[str] = set()
    for ordinal, heading in enumerate(headings, start=1):
        next_level_two = re.search(r"(?m)^##\s+", lore[heading.end() :])
        candidates = [len(lore)]
        if ordinal < len(headings):
            candidates.append(headings[ordinal].start())
        if next_level_two:
            candidates.append(heading.end() + next_level_two.start())
        end = min(candidates)
        title = heading.group(1).strip()
        section = lore[heading.start() : end].strip() + "\n"
        slug = slugify(title, ordinal)
        if slug in seen:
            slug = f"{slug}-{sha256_text(title)[:8]}"
        seen.add(slug)
        projects.append({"slug": slug, "title": title, "lore_section": section})
    return projects


def research_map(paths: list[Path], source_root: Path) -> dict[int, str]:
    result: dict[int, str] = {}
    for path in paths:
        relative = relative_path(path, source_root)
        match = re.fullmatch(r"research/(\d{2})-[^/]+\.md", relative)
        if match:
            result[int(match.group(1))] = relative
    return result


def referenced_research(section: str, available: dict[int, str]) -> list[str]:
    numbers: list[int] = []
    for match in re.finditer(
        r"research/(\d{1,2})(?:`?\s*[–—-]\s*`?(?:research/)?(\d{1,2}))?",
        section,
    ):
        start = int(match.group(1))
        stop = int(match.group(2) or start)
        step = 1 if stop >= start else -1
        numbers.extend(range(start, stop + step, step))
    return [available[number] for number in dict.fromkeys(numbers) if number in available]


def build_request(source_root: Path, artifact_root: Path) -> dict[str, Any]:
    paths = source_paths(source_root)
    digest = source_bundle_digest(paths, source_root)
    available_research = research_map(paths, source_root)
    projects = []
    for project in extract_lore_projects(read_text(source_root / "lore.md")):
        references = referenced_research(project["lore_section"], available_research)
        project_digest = sha256_text(
            digest + "\n" + project["title"] + "\n" + project["lore_section"]
        )
        projects.append(
            {
                "slug": project["slug"],
                "title": project["title"],
                "artifact": f"{PROJECTS_DIR}/{project['slug']}.md",
                "source_sha256": project_digest,
                "research": references,
            }
        )
    return {
        "schema_version": SCHEMA_VERSION,
        "source_root": str(source_root),
        "artifact_root": str(artifact_root),
        "source_sha256": digest,
        "sources": [relative_path(path, source_root) for path in paths],
        "required_sections": list(REQUIRED_SECTIONS),
        "projects": projects,
    }


def prepare(source_root: Path, artifact_root: Path) -> dict[str, Any]:
    source_root = source_root.resolve()
    artifact_root = resolve_artifact_root(artifact_root)
    artifact_root.mkdir(parents=True, exist_ok=True)
    projects_root = artifact_root / PROJECTS_DIR
    if projects_root.is_symlink():
        raise ArtifactError(f"refusing symlink projects directory: {projects_root}")
    projects_root.mkdir(parents=True, exist_ok=True)
    request = build_request(source_root, artifact_root)
    retire_removed_manifest_projects(request, artifact_root)
    write_if_changed(artifact_root / REQUEST_FILE, json_text(request))
    return request


def retire_removed_manifest_projects(
    request: dict[str, Any], artifact_root: Path
) -> list[str]:
    """Remove unchanged managed dossiers that no longer exist in canonical lore."""

    manifest_path = artifact_root / MANIFEST_FILE
    previous_request_path = artifact_root / REQUEST_FILE
    if manifest_path.is_symlink() or previous_request_path.is_symlink():
        raise ArtifactError("refusing symlink artifact lifecycle metadata")
    manifest = load_json(manifest_path)
    previous_request = load_json(previous_request_path)
    if (
        not isinstance(manifest, dict)
        or manifest.get("schema_version") != SCHEMA_VERSION
    ):
        return []
    records = manifest.get("projects") if isinstance(manifest, dict) else None
    if not isinstance(records, dict):
        return []
    expected = {project["artifact"] for project in request["projects"]}
    expected_slugs = {project["slug"] for project in request["projects"]}
    previous_projects = (
        previous_request.get("projects") if isinstance(previous_request, dict) else None
    )
    previous_by_slug = {
        project["slug"]: project
        for project in previous_projects or []
        if isinstance(project, dict)
        and isinstance(project.get("slug"), str)
        and isinstance(project.get("artifact"), str)
    }
    previous_request_valid = (
        isinstance(previous_request, dict)
        and previous_request.get("schema_version") == SCHEMA_VERSION
        and previous_request.get("source_sha256") == manifest.get("source_sha256")
        and isinstance(previous_projects, list)
    )
    projects_root = artifact_root / PROJECTS_DIR
    if projects_root.is_symlink():
        raise ArtifactError(f"refusing symlink projects directory: {projects_root}")
    retired: list[str] = []
    retired_record_found = False
    for slug, record in records.items():
        if not isinstance(record, dict):
            continue
        relative = record.get("path")
        digest = record.get("artifact_sha256")
        if not isinstance(relative, str) or relative in expected:
            continue
        previous_project = previous_by_slug.get(slug)
        if (
            not previous_request_valid
            or not isinstance(previous_project, dict)
            or previous_project.get("artifact") != relative
        ):
            continue
        parsed = PurePosixPath(relative)
        if (
            parsed.is_absolute()
            or len(parsed.parts) != 2
            or parsed.parts[0] != PROJECTS_DIR
            or re.fullmatch(r"[a-z0-9][a-z0-9-]*\.md", parsed.name) is None
        ):
            continue
        retired_record_found = True
        path = projects_root / parsed.name
        if path.is_symlink():
            raise ArtifactError(f"refusing retired artifact symlink: {path}")
        if not path.is_file() or not isinstance(digest, str):
            continue
        if artifact_file_digest(path) != digest:
            archive_root = artifact_root / "retired-projects"
            if archive_root.is_symlink():
                raise ArtifactError(
                    f"refusing symlink retired-projects directory: {archive_root}"
                )
            archive_root.mkdir(parents=True, exist_ok=True)
            destination = archive_root / path.name
            counter = 1
            while destination.exists():
                destination = archive_root / f"{path.stem}.{counter}{path.suffix}"
                counter += 1
            path.replace(destination)
            print(
                "artifact-generator: archived modified retired dossier: "
                f"{path} -> {destination}",
                file=sys.stderr,
            )
            retired.append(relative)
            continue
        path.unlink()
        retired.append(relative)

    manifest_paths = {
        record.get("path")
        for record in records.values()
        if isinstance(record, dict) and isinstance(record.get("path"), str)
    }
    project_set_changed = set(records) != expected_slugs or manifest_paths != expected
    index_path = artifact_root / INDEX_FILE
    index_digest = manifest.get("index_sha256")
    if retired_record_found or project_set_changed:
        if index_path.is_symlink():
            raise ArtifactError(f"refusing retired index symlink: {index_path}")
        if index_path.is_file() and isinstance(index_digest, str):
            if artifact_file_digest(index_path) == index_digest:
                index_path.unlink()
            else:
                print(
                    f"artifact-generator: preserving modified retired index: {index_path}",
                    file=sys.stderr,
                )
    if project_set_changed and manifest_path.is_file():
        manifest_path.unlink()
    return retired


def has_authored_payload(artifact_root: Path) -> bool:
    if (artifact_root / INDEX_FILE).is_file() or (artifact_root / MANIFEST_FILE).is_file():
        return True
    projects_root = artifact_root / PROJECTS_DIR
    return projects_root.is_dir() and any(projects_root.rglob("*.md"))


def migrate_legacy_artifacts(legacy_root: Path, artifact_root: Path) -> bool:
    """Resume-copy an old artifact bundle without overwriting unrelated work."""

    legacy_input = legacy_root.expanduser()
    artifact_input = artifact_root.expanduser()
    if legacy_input.is_symlink() or artifact_input.is_symlink():
        raise ArtifactError("refusing symlink artifact root during migration")
    legacy_root = legacy_input.resolve()
    artifact_root = artifact_input.resolve()
    if legacy_root == artifact_root or not legacy_root.exists():
        return False
    if legacy_root.is_symlink() or not legacy_root.is_dir():
        raise ArtifactError(f"refusing unsafe legacy artifact root: {legacy_root}")
    # A generated request by itself is not authored memory and must not stop
    # the caller from trying a later migration source that has a ready bundle.
    if not has_authored_payload(legacy_root):
        return False

    candidates: list[tuple[Path, Path]] = []
    for relative in (REQUEST_FILE, INDEX_FILE, MANIFEST_FILE):
        source = legacy_root / relative
        if source.exists():
            candidates.append((source, artifact_root / relative))
    projects_root = legacy_root / PROJECTS_DIR
    if projects_root.is_symlink():
        raise ArtifactError(f"refusing unsafe legacy projects directory: {projects_root}")
    if projects_root.is_dir():
        for source in sorted(projects_root.rglob("*.md")):
            candidates.append((source, artifact_root / source.relative_to(legacy_root)))
    if not candidates:
        return False

    for source, _ in candidates:
        if source.is_symlink() or not source.is_file():
            raise ArtifactError(f"refusing unsafe legacy artifact file: {source}")

    records = [
        {
            "path": destination.relative_to(artifact_root).as_posix(),
            "sha256": artifact_file_digest(source),
        }
        for source, destination in candidates
    ]
    migration = {
        "schema_version": 1,
        "source_root": str(legacy_root),
        "files": records,
    }
    marker_path = artifact_root / MIGRATION_FILE
    if marker_path.is_symlink():
        raise ArtifactError(f"refusing migration marker symlink: {marker_path}")
    active_migration = load_json(marker_path)
    if marker_path.exists() and active_migration is None:
        raise ArtifactError(f"invalid migration marker: {marker_path}")
    if active_migration is not None and active_migration.get("source_root") != str(
        legacy_root
    ):
        return False
    resuming = active_migration is not None
    if resuming and active_migration != migration:
        raise ArtifactError(
            f"legacy migration source changed before completion: {legacy_root}"
        )
    if not resuming and has_authored_payload(artifact_root):
        return False

    for (source, destination), record in zip(candidates, records):
        if destination.exists():
            replaceable_request = (
                destination == artifact_root / REQUEST_FILE
                and destination.is_file()
                and not destination.is_symlink()
            )
            already_copied = (
                resuming
                and destination.is_file()
                and not destination.is_symlink()
                and artifact_file_digest(destination) == record["sha256"]
            )
            if not replaceable_request and not already_copied:
                raise ArtifactError(
                    f"refusing to overwrite artifact during migration: {destination}"
                )
    artifact_root.mkdir(parents=True, exist_ok=True)
    if not resuming:
        atomic_write(marker_path, json_text(migration))
    for (source, destination), record in zip(candidates, records):
        if (
            destination.is_file()
            and not destination.is_symlink()
            and artifact_file_digest(destination) == record["sha256"]
        ):
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{destination.name}.migrate.", dir=destination.parent
        )
        os.close(descriptor)
        temporary = Path(temporary_name)
        try:
            shutil.copyfile(source, temporary)
            os.replace(temporary, destination)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
    for (_, destination), record in zip(candidates, records):
        if (
            not destination.is_file()
            or destination.is_symlink()
            or artifact_file_digest(destination) != record["sha256"]
        ):
            raise ArtifactError(f"legacy migration did not commit: {destination}")
    marker_path.unlink()
    return True


def bundle_root_for(source_root: Path) -> Path:
    """Ready bundle shipped with the plugin; overridable for tests/recovery."""

    configured = os.environ.get("CHOIRBOY_BUNDLE_DIR")
    if configured:
        return Path(configured).expanduser()
    return source_root / "artifacts"


def managed_markdown(root: Path) -> list[Path]:
    """INDEX and dossier files. Symlinks are ignored so restore cannot follow them."""

    found: list[Path] = []
    index = root / INDEX_FILE
    if index.is_file() and not index.is_symlink():
        found.append(index)
    projects = root / PROJECTS_DIR
    if projects.is_dir() and not projects.is_symlink():
        found.extend(
            path
            for path in sorted(projects.rglob("*.md"))
            if path.is_file() and not path.is_symlink()
        )
    return found


def restore_ready_bundle(bundle_root: Path, artifact_root: Path) -> None:
    """Fill a non-ready root from the bundle without discarding user edits.

    Missing managed files come from the bundle. An existing regular INDEX or
    dossier that differs from the bundle is kept, and the bundle manifest is
    not installed over that edit. Finalize is the command that records the
    edited bytes.
    """

    sources: list[Path] = []
    for relative in (INDEX_FILE, MANIFEST_FILE):
        candidate = bundle_root / relative
        if candidate.is_symlink() or not candidate.is_file():
            raise ArtifactError(f"bundle artifact is missing or unsafe: {candidate}")
        sources.append(candidate)
    projects_root = bundle_root / PROJECTS_DIR
    if projects_root.is_symlink() or not projects_root.is_dir():
        raise ArtifactError(f"bundle projects directory is unsafe: {projects_root}")
    for candidate in sorted(projects_root.rglob("*.md")):
        if candidate.is_symlink() or not candidate.is_file():
            raise ArtifactError(f"bundle artifact is missing or unsafe: {candidate}")
        sources.append(candidate)

    parent = artifact_root.parent
    parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{artifact_root.name}.staging-", dir=parent))
    backup: Path | None = None
    try:
        for source in sources:
            destination = staging / source.relative_to(bundle_root)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        preserved_edit = False
        if artifact_root.is_dir() and not artifact_root.is_symlink():
            for existing in managed_markdown(artifact_root):
                relative = existing.relative_to(artifact_root)
                staged = staging / relative
                try:
                    unchanged = (
                        staged.is_file()
                        and not staged.is_symlink()
                        and staged.read_bytes() == existing.read_bytes()
                    )
                except OSError:
                    unchanged = False
                if unchanged:
                    continue
                staged.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(existing, staged)
                preserved_edit = True
            # Copy archives into the staging tree and leave the originals in place
            # until the swap commits. A failed final rename must not delete them
            # with the temporary directory.
            for preserved in ("retired-projects",):
                existing = artifact_root / preserved
                if existing.is_dir() and not existing.is_symlink():
                    shutil.copytree(
                        existing,
                        staging / preserved,
                        symlinks=True,
                        copy_function=shutil.copy2,
                    )
        if preserved_edit:
            staged_manifest = staging / MANIFEST_FILE
            if staged_manifest.is_file() and not staged_manifest.is_symlink():
                staged_manifest.unlink()
        if artifact_root.exists():
            backup = parent / f".{artifact_root.name}.pre-restore-{os.getpid()}"
            os.rename(artifact_root, backup)
        try:
            os.rename(staging, artifact_root)
        except OSError:
            if backup is not None and not artifact_root.exists():
                os.rename(backup, artifact_root)
                backup = None
            raise
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    if backup is not None:
        shutil.rmtree(backup, ignore_errors=True)


def maybe_restore_bundle(
    request: dict[str, Any], source_root: Path, artifact_root: Path
) -> bool:
    """Self-heal a missing/broken/half-written root from the shipped bundle.

    The bundle only applies when it validates as ready against the current
    canonical sources, so a lore upgrade still triggers a genuine re-authoring
    bootstrap instead of restoring stale memory.
    """

    bundle = bundle_root_for(source_root)
    if bundle.is_symlink() or not bundle.is_dir():
        return False
    bundle = bundle.resolve()
    if (
        bundle == artifact_root
        or bundle in artifact_root.parents
        or artifact_root in bundle.parents
    ):
        return False
    if current_status(request, bundle)["status"] != "ready":
        return False
    if current_status(request, artifact_root)["status"] == "ready":
        return False
    restore_ready_bundle(bundle, artifact_root)
    print(f"artifact-generator: restored ready artifact bundle from {bundle}", file=sys.stderr)
    return True


def load_json(path: Path) -> dict[str, Any] | None:
    if not path.is_file() or path.is_symlink():
        return None
    try:
        value = json.loads(read_text(path))
    except (ArtifactError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def split_sections(document: str) -> dict[str, str]:
    matches = list(re.finditer(r"(?m)^##\s+(.+?)\s*$", document))
    sections: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(document)
        sections[match.group(1).strip()] = document[match.end() : end].strip()
    return sections


def validate_project_document(
    path: Path, document: str, project: dict[str, Any]
) -> list[str]:
    errors: list[str] = []
    if has_non_latin_alphabetic(document) or not looks_like_english_prose(document):
        errors.append(f"{path}: project artifacts must be written in English")
    first_line = next((line.strip() for line in document.splitlines() if line.strip()), "")
    if first_line != f"# {project['title']}":
        errors.append(f"{path}: first heading must be '# {project['title']}'")
    sections = split_sections(document)
    for heading in REQUIRED_SECTIONS:
        body = sections.get(heading, "")
        if len(re.sub(r"\s+", " ", body).strip()) < 12:
            errors.append(f"{path}: section '## {heading}' is missing or empty")
    source_section = sections.get("Sources", "")
    expected_sources = ["lore.md", *project.get("research", [])]
    for source in expected_sources:
        if source not in source_section:
            errors.append(f"{path}: source section must cite {source}")
    return errors


def validate_project_file(path: Path, project: dict[str, Any]) -> list[str]:
    if not path.is_file() or path.is_symlink():
        return [f"missing agent-authored artifact: {path}"]
    return validate_project_document(path, read_text(path), project)


def validate_index_document(
    path: Path, document: str, projects: list[dict[str, Any]]
) -> list[str]:
    errors = []
    if has_non_latin_alphabetic(document) or not looks_like_english_prose(document):
        errors.append(f"{path}: artifact index must be written in English")
    first_line = next((line.strip() for line in document.splitlines() if line.strip()), "")
    if not first_line.startswith("# "):
        errors.append(f"{path}: index must start with a level-one heading")
    for project in projects:
        link = f"[{project['title']}]({project['artifact']})"
        if link not in document:
            errors.append(f"{path}: missing exact project link {link}")
    expected_paths = {project["artifact"] for project in projects}
    actual_paths = set(re.findall(r"(projects/[A-Za-z0-9][A-Za-z0-9._/-]*\.md)", document))
    for relative in sorted(actual_paths - expected_paths):
        errors.append(f"{path}: unexpected project link {relative}")
    return errors


def validate_index(path: Path, projects: list[dict[str, Any]]) -> list[str]:
    if not path.is_file() or path.is_symlink():
        return [f"missing agent-authored index: {path}"]
    return validate_index_document(path, read_text(path), projects)


def validate_project_set(artifact_root: Path, projects: list[dict[str, Any]]) -> list[str]:
    projects_root = artifact_root / PROJECTS_DIR
    if projects_root.is_symlink():
        return [f"unsafe symlink projects directory: {projects_root}"]
    if not projects_root.is_dir():
        return [f"missing projects directory: {projects_root}"]
    expected = {project["artifact"] for project in projects}
    actual = {
        path.relative_to(artifact_root).as_posix()
        for path in projects_root.rglob("*.md")
    }
    return [
        f"unexpected project artifact: {artifact_root / relative}"
        for relative in sorted(actual - expected)
    ]


def artifact_file_digest(path: Path) -> str:
    return sha256_text(read_text(path))


def inspect_artifacts(
    request: dict[str, Any], artifact_root: Path
) -> tuple[dict[str, Any], dict[str, str]]:
    """Validate one in-memory snapshot and return documents only when ready."""

    reasons: list[str] = []
    documents: dict[str, str] = {}
    manifest = load_json(artifact_root / MANIFEST_FILE)

    if manifest is None:
        reasons.append("completion manifest is missing or invalid")
    else:
        if manifest.get("schema_version") != SCHEMA_VERSION:
            reasons.append("completion manifest schema is stale")
        if manifest.get("source_sha256") != request["source_sha256"]:
            reasons.append("canonical lore or research changed")

    expected_slugs = [project["slug"] for project in request["projects"]]
    records = manifest.get("projects") if isinstance(manifest, dict) else None
    records_valid = isinstance(records, dict) and set(records) == set(expected_slugs)
    if not records_valid:
        reasons.append("project set changed")

    index_path = artifact_root / INDEX_FILE
    if not index_path.is_file() or index_path.is_symlink():
        reasons.append("artifact index is missing or unsafe")
    else:
        documents[INDEX_FILE] = read_text(index_path)
        reasons.extend(
            validate_index_document(index_path, documents[INDEX_FILE], request["projects"])
        )
        if isinstance(manifest, dict) and sha256_text(documents[INDEX_FILE]) != manifest.get(
            "index_sha256"
        ):
            reasons.append("artifact index changed after finalization")

    reasons.extend(validate_project_set(artifact_root, request["projects"]))
    for project in request["projects"]:
        relative = project["artifact"]
        path = artifact_root / relative
        record = records.get(project["slug"]) if records_valid else None
        if records_valid:
            if not isinstance(record, dict):
                reasons.append(f"invalid manifest record: {project['slug']}")
                record = None
            else:
                if record.get("path") != relative:
                    reasons.append(f"invalid manifest path: {project['slug']}")
                if record.get("source_sha256") != project["source_sha256"]:
                    reasons.append(f"stale source digest: {project['slug']}")
        if not path.is_file() or path.is_symlink():
            reasons.append(f"artifact is missing or unsafe: {relative}")
            continue
        document = read_text(path)
        documents[relative] = document
        reasons.extend(validate_project_document(path, document, project))
        if isinstance(record, dict) and sha256_text(document) != record.get("artifact_sha256"):
            reasons.append(f"artifact changed after finalization: {relative}")

    # Keep reasons deterministic and compact when one broken input causes the
    # same diagnostic through more than one validation branch.
    reasons = list(dict.fromkeys(reasons))
    status = {
        "status": "ready" if not reasons else "pending",
        "source_sha256": request["source_sha256"],
        "artifact_root": str(artifact_root),
        "project_count": len(request["projects"]),
        "reasons": reasons,
    }
    return status, documents if not reasons else {}


def current_status(request: dict[str, Any], artifact_root: Path) -> dict[str, Any]:
    return inspect_artifacts(request, artifact_root)[0]


def finalize(request: dict[str, Any], artifact_root: Path) -> dict[str, Any]:
    errors = validate_index(artifact_root / INDEX_FILE, request["projects"])
    errors.extend(validate_project_set(artifact_root, request["projects"]))
    for project in request["projects"]:
        errors.extend(validate_project_file(artifact_root / project["artifact"], project))
    if errors:
        raise ArtifactError("artifact validation failed:\n- " + "\n- ".join(errors))
    records: dict[str, Any] = {}
    for project in request["projects"]:
        path = artifact_root / project["artifact"]
        records[project["slug"]] = {
            "path": project["artifact"],
            "source_sha256": project["source_sha256"],
            "artifact_sha256": artifact_file_digest(path),
        }
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "source_sha256": request["source_sha256"],
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "index_sha256": artifact_file_digest(artifact_root / INDEX_FILE),
        "projects": records,
    }
    atomic_write(artifact_root / MANIFEST_FILE, json_text(manifest))
    status = current_status(request, artifact_root)
    if status["status"] != "ready":
        raise ArtifactError("artifact snapshot changed during finalization")
    return status


def artifact_memory(request: dict[str, Any], documents: dict[str, str]) -> str:
    projects = request["projects"]
    blocks = [
        "# Established project history\n\n"
        "Continue from this prior project work. Apply its settled decisions and "
        "operational knowledge directly without asking the user to restate it.",
        documents[INDEX_FILE].rstrip(),
    ]
    blocks.extend(documents[project["artifact"]].rstrip() for project in projects)
    return "\n\n---\n\n".join(blocks)


def session_context(request: dict[str, Any], artifact_root: Path) -> str:
    status, documents = inspect_artifacts(request, artifact_root)
    if status["status"] == "ready":
        return artifact_memory(request, documents)
    root = html.escape(str(artifact_root), quote=True)
    digest = html.escape(request["source_sha256"], quote=True)
    body = (
        "Project dossiers are not ready. This is a status, not a request to write files. "
        "Load the load-context skill for the fixed lore. Author or refresh dossiers only "
        "when the user explicitly asks to update Choirboy memory."
    )
    return (
        f'<choirboy-project-artifacts status="pending" '
        f'source_sha256="{digest}" root="{root}">\n'
        f"{body}\n"
        "</choirboy-project-artifacts>"
    )


def session_status_text(request: dict[str, Any], artifact_root: Path) -> str:
    """Short factual status for Claude Code and Codex SessionStart hooks.

    Those harnesses cap or spill hook context. The full lore stays in the
    load-context skill and, when ready, on disk. This text must not look like
    an already-loaded canon and must not order the model to write dossiers.
    """

    status = current_status(request, artifact_root)
    root = str(artifact_root)
    if len(root) > 400:
        root = root[:397] + "..."
    lines = [
        f"Choirboy memory status: {status['status']}",
        f"Artifact root: {root}",
        "This message is a status, not loaded team context. It does not contain the fixed lore or project dossiers.",
        "Load the load-context skill when the task needs the team's established decisions.",
        "Do not author or rewrite dossiers unless the user explicitly asks to update Choirboy memory.",
    ]
    if status["status"] != "ready":
        reasons = [item for item in status.get("reasons", []) if isinstance(item, str)]
        if reasons:
            shown = "; ".join(reasons[:3])
            if len(shown) > 400:
                shown = shown[:397] + "..."
            lines.append(f"Not ready because: {shown}")
        lines.append(
            "A shipped ready bundle is restored automatically when it still matches the canonical sources."
        )
    text = "\n".join(lines).strip() + "\n"
    if len(text) > SESSION_STATUS_CHAR_LIMIT:
        text = text[: SESSION_STATUS_CHAR_LIMIT - 1].rstrip() + "\n"
    return text


def stop_response(request: dict[str, Any], artifact_root: Path, hook_input: str) -> dict[str, Any]:
    """Never continue the turn. Bundle restore already ran before this call."""

    del request, artifact_root, hook_input
    return {}


def kimi_stop_reason(
    request: dict[str, Any], artifact_root: Path, hook_input: str
) -> str | None:
    """Kimi Stop uses exit 2 as a continuation. Ordinary pending must not."""

    del request, artifact_root, hook_input
    return None


def default_artifact_root() -> Path:
    configured = os.environ.get("CHOIRBOY_ARTIFACTS_DIR")
    if configured:
        return Path(configured)
    plugin_data = os.environ.get("CLAUDE_PLUGIN_DATA")
    if plugin_data:
        return Path(plugin_data) / "project-artifacts"
    data_home = os.environ.get("XDG_DATA_HOME")
    if data_home:
        return Path(data_home) / "choirboy-prompt" / "project-artifacts"
    local_app_data = os.environ.get("LOCALAPPDATA")
    if os.name == "nt" and local_app_data:
        return Path(local_app_data) / "choirboy-prompt" / "project-artifacts"
    return Path.home() / ".local" / "share" / "choirboy-prompt" / "project-artifacts"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument(
        "command",
        choices=(
            "prepare",
            "status",
            "verify",
            "session-context",
            "session-status",
            "stop",
            "stop-kimi",
            "finalize",
        ),
    )
    value.add_argument("--source-root", type=Path, default=PLUGIN_ROOT)
    value.add_argument("--root", type=Path, default=default_artifact_root())
    value.add_argument(
        "--migrate-from",
        type=Path,
        action="append",
        default=[],
        help="copy a legacy checkout-local artifact bundle when the stable root is empty",
    )
    value.add_argument("--json", action="store_true", help="emit machine-readable status")
    return value


def main() -> int:
    # Hook pipes carry UTF-8 on every platform, independent of the host locale.
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", newline="\n")
    args = parser().parse_args()
    try:
        source_root = args.source_root.resolve()
        artifact_root = resolve_artifact_root(args.root)
        if args.command in ("status", "verify"):
            request = build_request(source_root, artifact_root)
        else:
            for legacy_root in args.migrate_from:
                if migrate_legacy_artifacts(legacy_root, artifact_root):
                    print(
                        f"artifact-generator: migrated artifacts from {legacy_root}",
                        file=sys.stderr,
                    )
                    break
            request = build_request(source_root, artifact_root)
            # Finalize records the files the user wrote. Restoring first would
            # replace those edits with the shipped bundle and then report ready.
            if args.command != "finalize":
                try:
                    maybe_restore_bundle(request, source_root, artifact_root)
                except ArtifactError as exc:
                    # A broken bundle must never break the hook; fall back to the
                    # ordinary pending status.
                    print(f"artifact-generator: bundle restore skipped: {exc}", file=sys.stderr)
            migration_marker = artifact_root / MIGRATION_FILE
            if migration_marker.exists():
                raise ArtifactError(
                    "legacy artifact migration is incomplete; rerun the installer "
                    "with the original migration source"
                )
            request = prepare(source_root, artifact_root)
        if args.command == "prepare":
            result = current_status(request, artifact_root)
            print(json_text(result).rstrip() if args.json else f"{result['status']} {artifact_root}")
        elif args.command == "status":
            result = current_status(request, artifact_root)
            print(json_text(result).rstrip() if args.json else result["status"])
        elif args.command == "verify":
            result = current_status(request, artifact_root)
            print(json_text(result).rstrip() if args.json else result["status"])
            if result["status"] != "ready":
                return 2
        elif args.command == "session-context":
            print(session_context(request, artifact_root))
        elif args.command == "session-status":
            print(session_status_text(request, artifact_root), end="")
        elif args.command == "stop":
            print(json.dumps(stop_response(request, artifact_root, sys.stdin.read()), ensure_ascii=False))
        elif args.command == "stop-kimi":
            reason = kimi_stop_reason(request, artifact_root, sys.stdin.read())
            if reason is not None:
                print(reason, file=sys.stderr)
                return 2
        elif args.command == "finalize":
            result = finalize(request, artifact_root)
            print(json_text(result).rstrip() if args.json else f"ready {artifact_root / INDEX_FILE}")
    except ArtifactError as exc:
        print(f"artifact-generator: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
