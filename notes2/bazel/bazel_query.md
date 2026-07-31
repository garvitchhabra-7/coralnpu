# Bazel Query

`bazel query` inspects Bazel's dependency graph without building anything. Bazel models the entire build as a directed acyclic graph — targets are nodes, dependencies are edges. Query traverses that graph.

## Target patterns

- `//pkg:target` — a single target
- `//pkg:all` — all targets in a package
- `//pkg/...` — all targets recursively (package + subpackages)

## Useful queries

```bash
# All test targets under a path
bazel query 'tests(//tests/cocotb/...)'

# What does a target depend on?
bazel query 'deps(//some:target)'

# What depends on a target? (reverse deps)
bazel query 'rdeps(//..., //some:target)'

# Filter by rule kind
bazel query 'kind(cc_library, //hdl/...)'

# Combine with grep for filtering
bazel query 'tests(//tests/cocotb/...)' | grep verilator
```
