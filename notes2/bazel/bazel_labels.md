# Bazel Labels

## Absolute vs Relative Labels

- `//tests/cocotb/tutorial:target` — absolute label, prefixed with `//` (workspace root). Works from anywhere.
- `tests/cocotb/tutorial:target` — relative path. Only works when running from the workspace root directory.

Both resolve to the same target when run from the repo root. The `//` form is preferred as it's unambiguous.
