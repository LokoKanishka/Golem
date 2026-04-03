#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from golem_host_describe_analyze_internal.core import main, parse_args
from golem_host_describe_analyze_internal.fields import _normalize_surface_state_bundle

__all__ = ["main", "parse_args", "_normalize_surface_state_bundle"]


if __name__ == "__main__":
    raise SystemExit(main())
