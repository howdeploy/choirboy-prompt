#!/usr/bin/env python3
"""Drive agent-authored project artifacts through lifecycle hooks.

This script intentionally does not write artifact content. It discovers the
projects described by the canonical lore, emits a deterministic SessionStart
request for the currently running agent, validates the files that agent wrote,
and records a freshness manifest. A Stop hook can use the same state to return
the unfinished bootstrap to that same agent once.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import shlex
import sys
import tempfile
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_VERSION = 1
REQUEST_FILE = ".artifact-request.json"
MANIFEST_FILE = ".artifact-manifest.json"
INDEX_FILE = "INDEX.md"
PROJECTS_DIR = "projects"

CORE_SOURCES = (
    "prompt.md",
    "security-posture.md",
    "lore.md",
    "user.md",
    "context/research-index.md",
)

REQUIRED_SECTIONS = (
    "Канон",
    "Цель и результат",
    "Архитектура и компоненты",
    "Решения и ограничения",
    "Операционный контур",
    "Шишки и правила",
    "Источники",
    "Неизвестное",
    "Когда пересматривать",
)

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


def normalize_text(value: str) -> str:
    return value.replace("\r\n", "\n").replace("\r", "\n")


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
    for match in re.finditer(r"research/(\d{1,2})(?:\s*[–—-]\s*(\d{1,2}))?", section):
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
    artifact_root = artifact_root.resolve()
    if artifact_root == Path(artifact_root.anchor):
        raise ArtifactError(f"refusing filesystem root as artifact directory: {artifact_root}")
    artifact_root.mkdir(parents=True, exist_ok=True)
    (artifact_root / PROJECTS_DIR).mkdir(parents=True, exist_ok=True)
    request = build_request(source_root, artifact_root)
    write_if_changed(artifact_root / REQUEST_FILE, json_text(request))
    return request


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


def validate_project_file(path: Path, project: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if not path.is_file() or path.is_symlink():
        return [f"missing agent-authored artifact: {path}"]
    document = read_text(path)
    first_line = next((line.strip() for line in document.splitlines() if line.strip()), "")
    if first_line != f"# {project['title']}":
        errors.append(f"{path}: first heading must be '# {project['title']}'")
    sections = split_sections(document)
    for heading in REQUIRED_SECTIONS:
        body = sections.get(heading, "")
        if len(re.sub(r"\s+", " ", body).strip()) < 12:
            errors.append(f"{path}: section '## {heading}' is missing or empty")
    source_section = sections.get("Источники", "")
    expected_sources = ["lore.md", *project.get("research", [])]
    for source in expected_sources:
        if source not in source_section:
            errors.append(f"{path}: source section must cite {source}")
    return errors


def validate_index(path: Path, projects: list[dict[str, Any]]) -> list[str]:
    if not path.is_file() or path.is_symlink():
        return [f"missing agent-authored index: {path}"]
    document = read_text(path)
    errors = []
    for project in projects:
        link = f"[{project['title']}]({project['artifact']})"
        if link not in document:
            errors.append(f"{path}: missing exact project link {link}")
    return errors


def validate_project_set(artifact_root: Path, projects: list[dict[str, Any]]) -> list[str]:
    expected = {project["artifact"] for project in projects}
    actual = {
        path.relative_to(artifact_root).as_posix()
        for path in (artifact_root / PROJECTS_DIR).rglob("*.md")
    }
    return [
        f"unexpected project artifact: {artifact_root / relative}"
        for relative in sorted(actual - expected)
    ]


def artifact_file_digest(path: Path) -> str:
    return sha256_text(read_text(path))


def current_status(request: dict[str, Any], artifact_root: Path) -> dict[str, Any]:
    manifest = load_json(artifact_root / MANIFEST_FILE)
    reasons: list[str] = []
    if manifest is None:
        reasons.append("completion manifest is missing or invalid")
    elif manifest.get("schema_version") != SCHEMA_VERSION:
        reasons.append("completion manifest schema is stale")
    elif manifest.get("source_sha256") != request["source_sha256"]:
        reasons.append("canonical lore or research changed")
    else:
        expected_slugs = [project["slug"] for project in request["projects"]]
        records = manifest.get("projects")
        if not isinstance(records, dict) or set(records) != set(expected_slugs):
            reasons.append("project set changed")
        index = artifact_root / INDEX_FILE
        if not reasons:
            if not index.is_file() or index.is_symlink():
                reasons.append("artifact index is missing")
            elif artifact_file_digest(index) != manifest.get("index_sha256"):
                reasons.append("artifact index changed after finalization")
        if not reasons:
            for project in request["projects"]:
                record = records.get(project["slug"], {})
                path = artifact_root / project["artifact"]
                if not isinstance(record, dict):
                    reasons.append(f"invalid manifest record: {project['slug']}")
                    continue
                if record.get("source_sha256") != project["source_sha256"]:
                    reasons.append(f"stale source digest: {project['slug']}")
                    continue
                if not path.is_file() or path.is_symlink():
                    reasons.append(f"artifact is missing: {project['artifact']}")
                    continue
                if artifact_file_digest(path) != record.get("artifact_sha256"):
                    reasons.append(f"artifact changed after finalization: {project['artifact']}")
    return {
        "status": "ready" if not reasons else "pending",
        "source_sha256": request["source_sha256"],
        "artifact_root": str(artifact_root),
        "project_count": len(request["projects"]),
        "reasons": reasons,
    }


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
        "content_author": "runtime-agent",
        "index_sha256": artifact_file_digest(artifact_root / INDEX_FILE),
        "projects": records,
    }
    atomic_write(artifact_root / MANIFEST_FILE, json_text(manifest))
    return current_status(request, artifact_root)


def quoted_command(source_root: Path, artifact_root: Path) -> str:
    values = (
        "python3",
        str(source_root / "scripts/artifact-generator.py"),
        "finalize",
        "--source-root",
        str(source_root),
        "--root",
        str(artifact_root),
    )
    return " ".join(shlex.quote(value) for value in values)


def project_lines(request: dict[str, Any]) -> str:
    lines = []
    for project in request["projects"]:
        references = ", ".join(project["research"]) or "только канонический lore"
        lines.append(
            f"- `{project['artifact']}` — {project['title']} (источники: {references})"
        )
    return "\n".join(lines)


def bootstrap_instruction(request: dict[str, Any], artifact_root: Path) -> str:
    source_root = Path(request["source_root"])
    command = quoted_command(source_root, artifact_root)
    return f"""Автогенерация проектных артефактов ещё не завершена.

Это одноразовый bootstrap текущей установки. Выполни его сам через доступные
file tools до обычной проектной работы, затем продолжи исходную задачу
пользователя. Скрипт не генерирует содержимое и не заменяет твою работу.

1. Прочитай полностью `{source_root / 'lore.md'}`, `{source_root / 'prompt.md'}`,
   `{source_root / 'security-posture.md'}`, `{source_root / 'user.md'}`,
   `{source_root / 'context/research-index.md'}` и все Markdown-файлы внутри
   `{source_root / 'research'}`. Не выводи факты, которых нет в этих источниках;
   пробелы фиксируй фразой «Не зафиксировано в источниках».
2. Создай `{artifact_root / INDEX_FILE}` и ровно эти dossiers:
{project_lines(request)}
3. В каждом dossier первая строка — `# <точное название проекта>`, затем
   непустые разделы: {', '.join(f'`## {name}`' for name in REQUIRED_SECTIONS)}.
   В `## Источники` укажи `lore.md` и перечисленные research-файлы. INDEX должен
   содержать название и относительную ссылку на каждый dossier.
4. Проверь и зафиксируй готовность командой:
   `{command}`
5. Если validator сообщает ошибку, исправь файлы и повтори команду. Не завершай
   bootstrap одним описанием того, что следовало бы сделать.
"""


def session_context(request: dict[str, Any], artifact_root: Path) -> str:
    status = current_status(request, artifact_root)
    root = html.escape(str(artifact_root), quote=True)
    digest = html.escape(request["source_sha256"], quote=True)
    if status["status"] == "ready":
        body = (
            f"Проектные артефакты готовы: `{artifact_root / INDEX_FILE}`. "
            "Перед решением задачи из описанного домена сначала прочитай INDEX и "
            "соответствующий dossier. При расхождении канонические lore/research "
            "сильнее производного артефакта."
        )
    else:
        body = bootstrap_instruction(request, artifact_root)
    return (
        f'<choirboy-project-artifacts status="{status["status"]}" '
        f'source_sha256="{digest}" root="{root}">\n'
        f"{body.rstrip()}\n"
        "</choirboy-project-artifacts>"
    )


def stop_response(request: dict[str, Any], artifact_root: Path, hook_input: str) -> dict[str, Any]:
    try:
        event = json.loads(hook_input) if hook_input.strip() else {}
    except json.JSONDecodeError:
        return {}
    if not isinstance(event, dict):
        return {}
    if event.get("stop_hook_active") is True:
        return {}
    status = current_status(request, artifact_root)
    if status["status"] == "ready":
        return {}
    reason = (
        bootstrap_instruction(request, artifact_root)
        + "\nStop-проверка обнаружила незавершённый bootstrap. Продолжи сейчас; "
        "после успешного finalize этот хук перестанет вмешиваться."
    )
    return {"decision": "block", "reason": reason}


def default_artifact_root() -> Path:
    configured = os.environ.get("CHOIRBOY_ARTIFACTS_DIR")
    if configured:
        return Path(configured)
    plugin_data = os.environ.get("CLAUDE_PLUGIN_DATA")
    if plugin_data:
        return Path(plugin_data) / "project-artifacts"
    return PLUGIN_ROOT / "artifacts"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument(
        "command",
        choices=("prepare", "status", "session-context", "stop", "finalize"),
    )
    value.add_argument("--source-root", type=Path, default=PLUGIN_ROOT)
    value.add_argument("--root", type=Path, default=default_artifact_root())
    value.add_argument("--json", action="store_true", help="emit machine-readable status")
    return value


def main() -> int:
    args = parser().parse_args()
    try:
        source_root = args.source_root.resolve()
        artifact_root = args.root.resolve()
        request = prepare(source_root, artifact_root)
        if args.command == "prepare":
            result = current_status(request, artifact_root)
            print(json_text(result).rstrip() if args.json else f"{result['status']} {artifact_root}")
        elif args.command == "status":
            result = current_status(request, artifact_root)
            print(json_text(result).rstrip() if args.json else result["status"])
        elif args.command == "session-context":
            print(session_context(request, artifact_root))
        elif args.command == "stop":
            print(json.dumps(stop_response(request, artifact_root, sys.stdin.read()), ensure_ascii=False))
        elif args.command == "finalize":
            result = finalize(request, artifact_root)
            print(json_text(result).rstrip() if args.json else f"ready {artifact_root / INDEX_FILE}")
    except ArtifactError as exc:
        print(f"artifact-generator: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
