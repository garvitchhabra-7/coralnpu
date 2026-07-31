# Writing Custom Bazel Rules

Custom rules in this repo (e.g. `rules/coco_tb.bzl`) are written in **Starlark** — a restricted subset of Python used for both `BUILD` files and `.bzl` files. No classes, no arbitrary imports, deterministic by design so Bazel can cache and parallelize safely.

## Label syntax recap

`@repo//package:file` — repo (`@repo`, omitted = current repo) + package/directory (`//package`) + file/target (`:file`).

- `//rules:host_cpus.bzl` — "current repo's `rules/` dir." Resolves relative to whichever repo the referencing file lives in.
- `@coralnpu_hw//rules:sram_backdoor.bzl` — same thing, spelled out explicitly. `coralnpu_hw` is this repo's own name (`workspace(name = "coralnpu_hw")` in `WORKSPACE`), so this is only ever pinned explicitly when a `.bzl` file might get loaded from a context where "current repo" wouldn't be coralnpu_hw itself.
- `@rules_hdl//cocotb:cocotb.bzl` — an external repo, fetched via `http_archive` in `rules/repos.bzl` (not built into Bazel).

`rules/` is just an ordinary directory of `.bzl` files containing `def`s and macros — any file can pull them in with `load(...)`, like a Python import.

## Anatomy of a custom rule

Example: `vcs_cocotb_model` in `rules/coco_tb.bzl:246-348`.

### 1. `rule()` — declares the interface

```python
vcs_cocotb_model = rule(
    implementation = _vcs_cocotb_model_impl,
    attrs = { ... },
    executable = True,
)
```

`rule()` is a builtin Starlark function. Calling it returns a new callable, used in `BUILD` files exactly like any builtin rule: `vcs_cocotb_model(name = "foo", hdl_toplevel = "MyModule", ...)`.

### 2. `attrs` — typed parameter list

```python
"hdl_toplevel": attr.string(mandatory = True),
"defines": attr.string_dict(default = {}),
"data": attr.label_list(allow_files = True, default = []),
"_vcs_libs": attr.label(default = "@coralnpu_pip_deps_cocotb//:cocotb_libs"),
```

Each `attr.*()` declares one field: type, required-ness, default. Names starting with `_` (`_vcs_libs`, `_template`) are **implicit attributes** — not settable from `BUILD` files, just hardcoded dependencies the rule always pulls in. `attr.label`/`attr.label_list` point at other targets; Bazel builds those first and hands you their output files.

### 3. Implementation function — runs at analysis time

```python
def _vcs_cocotb_model_impl(ctx):
```

`ctx` exposes everything declared in `attrs`:
- `ctx.attr.hdl_toplevel` — the string value
- `ctx.files._vcs_libs` — actual `File` objects from a label attr
- `ctx.actions.*` — API for scheduling build steps
- `ctx.expand_location`, `ctx.actions.declare_file`, etc.

This function doesn't run anything itself — it **declares** a plan (files + actions) that Bazel executes later, possibly cached, possibly remote.

### 4. Declaring outputs and actions

```python
output_simv = ctx.actions.declare_file(outdir_name + "/simv")
...
ctx.actions.run_shell(
    outputs = [output_simv, output_daidir, output_vdb],
    inputs = depset(inputs),
    command = "bash {}".format(wrapper.path),
    mnemonic = "VcsCompile",
)
```

`declare_file` registers a Bazel-managed, content-hashed output path. `run_shell` says: "to produce `outputs`, given exactly these `inputs`, run this `command`" — sandboxed, so nothing outside the declared inputs is visible. `mnemonic` is just a label shown in build logs (`[123/400] VcsCompile //foo:bar`).

`expand_template` (used earlier in the same impl) is a simpler action: substitute `%{PLACEHOLDER}%` markers in a template file with real values — used here to generate the actual compile shell script instead of building one giant inline command string.

### 5. Returning providers

```python
return [
    DefaultInfo(
        files = depset([output_simv]),
        runfiles = ctx.runfiles(files = [output_simv, output_daidir, output_vdb]),
        executable = output_simv,
    ),
]
```

Every rule implementation returns a list of **providers** — structured data other targets can consume. `DefaultInfo` is universal: `files` = what `bazel build` produces, `executable` = what `bazel run` invokes, `runfiles` = extra files the executable needs alongside it at runtime. Rules can return additional providers too — e.g. `verilator_cocotb_model` (same file) also returns `OutputGroupInfo` to expose named output subsets to callers.

## The pattern in one line

`attrs` (typed inputs) → `implementation(ctx)` (declare files/actions from those inputs) → `return [Providers]` (expose outputs to the rest of the build graph). Nearly every custom rule in this repo (`vcs_cocotb_model`, `verilator_cocotb_model`, `vcs_simulation_run`, `vcs_simulation_test` in `rules/coco_tb.bzl`) follows this same three-part shape.
