"""Generate pressure scenarios from skill + spec using LLM."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path

import yaml

from scripts.utils import extract_yaml

PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


@dataclass(frozen=True)
class Scenario:
    id: str
    level: int
    level_name: str
    description: str
    prompt: str
    setup_commands: tuple[str, ...]
    # (relative path, content) pairs written into the sandbox by Python. setup_commands run
    # without a shell, so `echo … > file` cannot give a fixture any content.
    files: tuple[tuple[str, str], ...] = ()
    # data the fake ro-sql/ro-pg/ro-es answer with (stubs/tool_stub.py), as JSON text.
    db: str = ""


def load_scenarios(path: Path) -> list[Scenario]:
    """load hand-written scenarios (same YAML shape as generated ones, plus `files:`)."""
    parsed = yaml.safe_load(path.read_text(encoding="utf-8"))
    shared = parsed.get("files", {}) or {}
    scenarios = [
        Scenario(
            id=s["id"],
            level=s["level"],
            level_name=s["level_name"],
            description=s["description"],
            prompt=s["prompt"].strip(),
            setup_commands=tuple(s.get("setup_commands", [])),
            files=tuple({**shared, **(s.get("files", {}) or {})}.items()),
            db=json.dumps(s.get("db", parsed.get("db")) or {}),
        )
        for s in parsed["scenarios"]
    ]
    return sorted(scenarios, key=lambda s: s.level)


def generate_scenarios(
    skill_path: Path,
    spec_yaml: str,
    model: str = "haiku",
) -> list[Scenario]:
    """Generate 3 scenarios with decreasing prompt strictness.

    Calls claude -p with the scenario_generator prompt, parses YAML output.
    """
    skill_content = skill_path.read_text(encoding="utf-8")
    prompt_template = (PROMPTS_DIR / "scenario_generator.md").read_text(encoding="utf-8")
    prompt = (
        prompt_template
        .replace("{skill_content}", skill_content)
        .replace("{spec_yaml}", spec_yaml)
    )

    result = subprocess.run(
        ["claude", "-p", "--model", model, "--output-format", "text"],
        input=prompt,
        capture_output=True,
        encoding="utf-8",
        timeout=120,
    )

    if result.returncode != 0:
        raise RuntimeError(f"claude -p failed: {result.stderr}")

    if not result.stdout.strip():
        raise RuntimeError("claude -p returned empty output")

    raw_yaml = extract_yaml(result.stdout)
    parsed = yaml.safe_load(raw_yaml)

    scenarios: list[Scenario] = []
    for s in parsed["scenarios"]:
        scenarios.append(Scenario(
            id=s["id"],
            level=s["level"],
            level_name=s["level_name"],
            description=s["description"],
            prompt=s["prompt"].strip(),
            setup_commands=tuple(s.get("setup_commands", [])),
        ))

    return sorted(scenarios, key=lambda s: s.level)
