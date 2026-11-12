"""CLI entry point for skill-comply."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path
from typing import Any

import yaml

from scripts.grader import grade
from scripts.report import generate_report
from scripts.runner import run_scenario
from scripts.parser import parse_spec
from scripts.scenario_generator import generate_scenarios, load_scenarios
from scripts.spec_generator import generate_spec

logger = logging.getLogger(__name__)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    parser = argparse.ArgumentParser(
        description="skill-comply: Measure skill compliance rates",
    )
    parser.add_argument(
        "skill",
        type=Path,
        help="Path to skill/rule file to test",
    )
    parser.add_argument(
        "--model",
        default="sonnet",
        help="Model for scenario execution (default: sonnet)",
    )
    parser.add_argument(
        "--gen-model",
        default="haiku",
        help="Model for spec/scenario generation (default: haiku)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Generate spec and scenarios without executing",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output report path (default: results/<skill-name>.md)",
    )

    parser.add_argument("--spec", type=Path, default=None, help="Use this spec YAML instead of generating one")
    parser.add_argument(
        "--scenarios", type=Path, default=None,
        help="Use this scenarios YAML (may carry `files:` fixtures) instead of generating them",
    )

    parser.add_argument("--repeat", type=int, default=1, help="Run each scenario N times (default 1)")

    args = parser.parse_args()
    if args.repeat < 1:
        parser.error("--repeat must be >= 1")

    if not args.skill.is_file():
        logger.error("Error: Skill file not found: %s", args.skill)
        sys.exit(1)

    results_dir = Path(__file__).parent.parent / "results"
    results_dir.mkdir(exist_ok=True)

    # Step 1: Generate compliance spec (--spec loads a fixed one, so reruns are comparable)
    if args.spec:
        logger.info("[1/4] Loading compliance spec %s...", args.spec)
        spec = parse_spec(args.spec)
    else:
        logger.info("[1/4] Generating compliance spec from %s...", args.skill.name)
        spec = generate_spec(args.skill, model=args.gen_model)
    logger.info("       %d steps extracted", len(spec.steps))

    # Step 2: Generate scenarios (--scenarios loads hand-written ones with fixture files)
    if args.scenarios:
        logger.info("[2/4] Loading scenarios %s...", args.scenarios)
        scenarios = load_scenarios(args.scenarios)
    else:
        spec_yaml = yaml.dump({
            "steps": [
                {"id": s.id, "description": s.description, "required": s.required}
                for s in spec.steps
            ]
        })
        logger.info("[2/4] Generating scenarios (3 prompt strictness levels)...")
        scenarios = generate_scenarios(args.skill, spec_yaml, model=args.gen_model)
    logger.info("       %d scenarios generated", len(scenarios))

    for s in scenarios:
        logger.info("       - %s: %s", s.level_name, s.description[:60])

    if args.dry_run:
        logger.info("\n[dry-run] Spec and scenarios generated. Skipping execution.")
        logger.info("\nSpec: %s (%d steps)", spec.id, len(spec.steps))
        for step in spec.steps:
            marker = "*" if step.required else " "
            logger.info("  [%s] %s: %s", marker, step.id, step.description)
        return

    # Step 3: Execute scenarios
    logger.info("[3/4] Executing scenarios (model=%s)...", args.model)
    graded_results: list[tuple[str, Any, list[Any]]] = []

    # --repeat N runs every scenario N times; labels become "<level> #i" and the report gets a
    # per-step hit-count table, so one lucky (or unlucky) run does not decide anything.
    for scenario in scenarios:
        for i in range(1, args.repeat + 1):
            label = scenario.level_name if args.repeat == 1 else f"{scenario.level_name} #{i}"
            logger.info("       Running %s...", label)
            try:
                run = run_scenario(scenario, model=args.model)
            except Exception as e:  # one crashed/timed-out session must not lose the other runs
                logger.warning("       %s: run failed (%s), skipped", label, e)
                continue
            result = grade(spec, list(run.observations))
            graded_results.append((label, result, list(run.observations)))
            logger.info("       %s: %.0f%%", label, result.compliance_rate * 100)

    # Step 4: Generate report
    skill_name = args.skill.parent.name if args.skill.stem == "SKILL" else args.skill.stem
    output_path = args.output or results_dir / f"{skill_name}.md"
    logger.info("[4/4] Generating report...")

    report = generate_report(args.skill, spec, graded_results, scenarios=scenarios)
    if args.repeat > 1:
        report = _hit_count_table(spec, scenarios, graded_results) + "\n" + report
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(report, encoding="utf-8")
    logger.info("       Report saved to %s", output_path)

    # Summary
    if not graded_results:
        logger.warning("No scenarios were executed.")
        return
    overall = sum(r.compliance_rate for _, r, _obs in graded_results) / len(graded_results)
    logger.info("\n%s", "=" * 50)
    logger.info("Overall Compliance: %.0f%%", overall * 100)
    if overall < spec.threshold_promote_to_hook:
        logger.info(
            "Recommendation: Some steps have low compliance. "
            "Consider promoting them to hooks. See the report for details."
        )


def _hit_count_table(spec: Any, scenarios: list[Any], graded: list[tuple[str, Any, list[Any]]]) -> str:
    """Per step × scenario: detected in k of n runs, plus mean compliance per scenario."""
    levels = [s.level_name for s in scenarios]
    by_level: dict[str, list[Any]] = {lv: [] for lv in levels}
    for label, result, _obs in graded:
        by_level.setdefault(label.split(" #")[0], []).append(result)
    lines = [
        "## Repeated runs — steps detected (k/n)",
        "",
        "| Step | Required | " + " | ".join(levels) + " |",
        "|------|----------|" + "|".join("---" for _ in levels) + "|",
    ]
    for step in spec.steps:
        cells = []
        for lv in levels:
            rs = by_level[lv]
            k = sum(1 for r in rs for sr in r.steps if sr.step_id == step.id and sr.detected)
            cells.append(f"{k}/{len(rs)}")
        lines.append(f"| {step.id} | {'Yes' if step.required else 'No'} | " + " | ".join(cells) + " |")
    means = []
    for lv in levels:
        rs = by_level[lv]
        if rs:
            rates = sorted(r.compliance_rate for r in rs)
            means.append(f"{sum(rates) / len(rates):.0%} ({rates[0]:.0%}–{rates[-1]:.0%})")
        else:
            means.append("no runs")
    lines.append("| **mean (min–max)** | | " + " | ".join(means) + " |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
