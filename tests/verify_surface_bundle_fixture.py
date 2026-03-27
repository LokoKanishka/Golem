#!/usr/bin/env python3
from __future__ import annotations

import copy
import difflib
import importlib.util
import json
import pathlib
import sys


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "golem_host_describe_analyze.py"
FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "surface_bundle_normalization"


def load_module():
    spec = importlib.util.spec_from_file_location("golem_host_describe_analyze", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load module from {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_json(path: pathlib.Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(value: object) -> str:
    return json.dumps(value, indent=2, ensure_ascii=True, sort_keys=True) + "\n"


def main() -> int:
    module = load_module()
    fixture_input = load_json(FIXTURE_DIR / "input.json")
    expected = load_json(FIXTURE_DIR / "expected.json")

    actual = module._normalize_surface_state_bundle(copy.deepcopy(fixture_input))
    rerun = module._normalize_surface_state_bundle(copy.deepcopy(fixture_input))
    idempotent = module._normalize_surface_state_bundle(copy.deepcopy(actual))

    print("--- surface bundle fixture verify ---")
    print(f"fixture input: {FIXTURE_DIR / 'input.json'}")
    print(f"expected output: {FIXTURE_DIR / 'expected.json'}")

    if actual != expected:
        diff = difflib.unified_diff(
            dump_json(expected).splitlines(True),
            dump_json(actual).splitlines(True),
            fromfile="expected.json",
            tofile="actual.json",
        )
        sys.stdout.writelines(diff)
        return 1

    if actual != rerun:
        print("determinism check failed: repeated normalization changed the output")
        return 1

    if actual != idempotent:
        print("idempotence check failed: normalizing the normalized bundle changed the output")
        return 1

    print("fixture comparison: OK")
    print("determinism check: OK")
    print("idempotence check: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
