#!/bin/bash
# Sets up .local-tools/ and .bazelrc.user for building with Nix-managed clang.
#
# Nix's clang wrapper only injects C++ stdlib -isystem paths when called as
# "clang++" (binary name ends in "++").  Bazel calls "clang" for both C and
# C++ files, so C++ compilations fail to find standard headers.
#
# This script generates a thin wrapper that adds the missing -isystem flags
# and points Bazel's CC at it via .bazelrc.user.
#
# Run once after installing clang via Nix (home-manager switch, nix-env, etc).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Resolve Nix clang paths ---

CLANG_BIN="$(readlink -f "$(which clang 2>/dev/null)")" || {
  echo "Error: clang not found on PATH. Install it via Nix first." >&2
  exit 1
}

CLANG_WRAPPER_DIR="$(dirname "$CLANG_BIN")/.."

CXX_FLAGS_FILE="$CLANG_WRAPPER_DIR/nix-support/libcxx-cxxflags"
if [[ ! -f "$CXX_FLAGS_FILE" ]]; then
  echo "Error: Not a Nix clang wrapper (missing $CXX_FLAGS_FILE)." >&2
  echo "This script is only needed for Nix-managed clang." >&2
  exit 1
fi

CXX_FLAGS="$(cat "$CXX_FLAGS_FILE")"

# --- Generate wrapper ---

mkdir -p "$REPO_ROOT/.local-tools"

cat > "$REPO_ROOT/.local-tools/clang-cxx-wrapper" <<EOF
#!/bin/bash
exec $CLANG_BIN \\
  $CXX_FLAGS \\
  "\$@"
EOF
chmod +x "$REPO_ROOT/.local-tools/clang-cxx-wrapper"

# --- Generate .bazelrc.user ---

WRAPPER_PATH="$REPO_ROOT/.local-tools/clang-cxx-wrapper"

cat > "$REPO_ROOT/.bazelrc.user" <<EOF
build --repo_env=CC=$WRAPPER_PATH
build --action_env=CC=$WRAPPER_PATH
EOF

echo "Setup complete."
echo "  Wrapper: $WRAPPER_PATH"
echo "  Clang:   $CLANG_BIN"
echo "  C++ flags: $CXX_FLAGS"
echo ""
echo "Run 'bazelisk clean --expunge' if you had a previous build cache."
