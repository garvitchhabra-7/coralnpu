# Setting Up Bazel with Nix-Managed Clang

When using clang installed via Nix (Home Manager or `nix-env`), Bazel builds fail
because Nix's clang wrapper only injects C++ stdlib headers when called as `clang++`.
Bazel calls `clang` for both C and C++ files, so C++ compilations can't find
`<string>`, `<cstdint>`, etc.

## Prerequisites

Install clang and LLVM tools via Nix. If using Home Manager (`~/.config/home-manager/home.nix`):

```nix
home.packages = [
  pkgs.clang
  pkgs.lld
  pkgs.llvm
];
```

Then `home-manager switch`.

Or imperatively: `nix-env -iA nixpkgs.clang nixpkgs.lld nixpkgs.llvm`

## Run the Setup Script

```bash
utils/setup_nix_bazel.sh
```

This auto-detects your Nix clang's store paths and generates two gitignored files:

- `.local-tools/clang-cxx-wrapper` — wrapper that calls clang with explicit
  `-isystem` paths for the C++ stdlib headers
- `.bazelrc.user` — points Bazel's `CC` at the wrapper via `--repo_env` and
  `--action_env`

If you had a previous build cache, expunge it:

```bash
bazelisk clean --expunge
```

## Re-run After Nix Updates

If you update your Nix clang (e.g. `home-manager switch` with a newer nixpkgs),
the Nix store hashes change. Re-run the setup script:

```bash
utils/setup_nix_bazel.sh
bazelisk clean --expunge
```

## Why This Is Needed

The project's `.bazelrc` sets `CC="clang"`. Bazel's auto-configured host toolchain
(`local_config_cc`) uses this to compile host tools (protobuf, abseil, etc.).

Nix's clang is a bash wrapper script that conditionally adds C++ stdlib `-isystem`
flags only when the binary name ends in `++` (i.e. `clang++`). When Bazel invokes
`clang` for `.cc` files, those flags are missing and compilation fails.

System GCC is not an alternative — abseil requires GCC 10+, and the server has GCC 8.

The wrapper script solves this by always passing the `-isystem` flags to clang,
regardless of how it's called.
