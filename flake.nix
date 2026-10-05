{
  description = "Coral NPU development environment (FHS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  # `nix develop` enters an FHS environment (bubblewrap, unprivileged user
  # namespaces): every package below is linked into /usr/{bin,include,lib}
  # inside the env, all built against the same Nix glibc. Tools that expect a
  # normal Linux layout (Bazel's downloaded binary, Verilator's generated
  # Makefiles, -lelf / <libelf.h>, CMake) then work without per-path hacks.
  #
  # Host directories such as /opt (Vivado), /var/keys (licenses) and $HOME stay
  # visible, and the outer environment is inherited, so run
  # `module load Vivado/2025.2` *before* `nix develop` to get vivado on PATH.
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      fhs = pkgs.buildFHSEnv {
        name = "coralnpu-fhs";

        targetPkgs = p: with p; [
          # Build tooling
          bazelisk
          clang
          lld
          llvm
          gnumake
          cmake
          ninja
          pkg-config
          perl
          python311
          uv
          jdk11
          patchelf
          git
          which
          file
          unzip
          zip
          gnutar
          gzip
          xz
          bzip2
          diffutils
          patch
          procps
          util-linux

          # Libraries for host-side C/C++ (Verilator DPI, nexus_loader, ...)
          elfutils    # libelf.h / -lelf (dpi_memutil, nexus_loader)
          lz4         # Verilator FST tracing
          zlib
          zstd
          libftdi1    # nexus_loader
          libusb1     # nexus_loader
          ncurses

          # Board tools
          openocd
          minicom
          screen

          # Runtime libraries for Vivado (/opt/Xilinx) run from inside the env
          # (bitstream builds launched through Bazel). GUI not targeted.
          ncurses5
          libxcrypt-legacy
          libuuid
          freetype
          fontconfig
          glib
          libx11
          libxext
          libxrender
          libxtst
          libxi
        ];

        # Link headers (dev outputs) into /usr/include as well.
        extraOutputsToInstall = [ "dev" ];

        profile = ''
          export CC=clang
        '';

        runScript = "bash";
      };
    in
    {
      packages.${system}.default = fhs;
      devShells.${system}.default = fhs.env;
    };
}
