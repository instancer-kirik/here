{
  description = "here - Universal package manager that speaks your system's language";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, zig }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zigpkg = zig.packages.${system}."0.12.1";
      in
      {
        packages.default = pkgs.stdenv.mkDerivation rec {
          pname = "here";
          version = "1.0.0";

          src = ./.;

          nativeBuildInputs = [
            zigpkg
          ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild

            export HOME=$TMPDIR
            zig build -Doptimize=ReleaseFast --cache-dir /tmp/zig-cache --global-cache-dir /tmp/zig-global-cache

            runHook postBuild
          '';

          checkPhase = ''
            runHook preCheck

            export HOME=$TMPDIR
            zig build test --cache-dir /tmp/zig-cache --global-cache-dir /tmp/zig-global-cache

            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            cp zig-out/bin/here $out/bin/

            # Install documentation
            mkdir -p $out/share/doc/here
            cp README.md CHANGELOG.md $out/share/doc/here/

            # Install license
            mkdir -p $out/share/licenses/here
            cp LICENSE $out/share/licenses/here/

            runHook postInstall
          '';

          doCheck = true;

          meta = with pkgs.lib; {
            description = "Universal package manager that speaks your system's language";
            longDescription = ''
              here is a universal package manager that automatically detects your system's
              package managers, sources, and version managers, then intelligently installs
              software using the best available method. No more remembering different
              commands for different systems – just use here.
            '';
            homepage = "https://github.com/your-repo/here";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.unix;
            mainProgram = "here";
            funding = "0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a";
          };
        };

        packages.here = self.packages.${system}.default;

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/here";
        };

        apps.here = self.apps.${system}.default;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zigpkg

            # Development tools
            gnumake

            # Documentation tools
            pandoc

            # Package management tools (for testing detection)
            flatpak

            # Version managers (for testing detection)
            asdf-vm
          ];

          shellHook = ''
            echo "🏠 here development environment"
            echo "Available commands:"
            echo "  zig build          - Build debug version"
            echo "  zig build release  - Build release version"
            echo "  zig build test     - Run tests"
            echo "  make help          - Show make targets"
            echo ""
            echo "Zig version: $(zig version)"
            echo ""
          '';
        };

        # Cross-compilation outputs
        packages.here-linux-x86_64 = pkgs.stdenv.mkDerivation rec {
          pname = "here-linux-x86_64";
          version = "1.0.0";
          src = ./.;
          nativeBuildInputs = [ zigpkg ];
          dontConfigure = true;
          buildPhase = ''
            export HOME=$TMPDIR
            zig build release -Doptimize=ReleaseFast -Dtarget=x86_64-linux --cache-dir /tmp/zig-cache
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/release/x86_64-linux/here $out/bin/here-linux-x86_64
          '';
        };

        packages.here-linux-aarch64 = pkgs.stdenv.mkDerivation rec {
          pname = "here-linux-aarch64";
          version = "1.0.0";
          src = ./.;
          nativeBuildInputs = [ zigpkg ];
          dontConfigure = true;
          buildPhase = ''
            export HOME=$TMPDIR
            zig build release -Doptimize=ReleaseFast -Dtarget=aarch64-linux --cache-dir /tmp/zig-cache
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/release/aarch64-linux/here $out/bin/here-linux-aarch64
          '';
        };

        packages.here-macos-x86_64 = pkgs.stdenv.mkDerivation rec {
          pname = "here-macos-x86_64";
          version = "1.0.0";
          src = ./.;
          nativeBuildInputs = [ zigpkg ];
          dontConfigure = true;
          buildPhase = ''
            export HOME=$TMPDIR
            zig build release -Doptimize=ReleaseFast -Dtarget=x86_64-macos --cache-dir /tmp/zig-cache
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/release/x86_64-macos/here $out/bin/here-macos-x86_64
          '';
        };

        packages.here-macos-aarch64 = pkgs.stdenv.mkDerivation rec {
          pname = "here-macos-aarch64";
          version = "1.0.0";
          src = ./.;
          nativeBuildInputs = [ zigpkg ];
          dontConfigure = true;
          buildPhase = ''
            export HOME=$TMPDIR
            zig build release -Doptimize=ReleaseFast -Dtarget=aarch64-macos --cache-dir /tmp/zig-cache
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/release/aarch64-macos/here $out/bin/here-macos-aarch64
          '';
        };

        # All cross-compiled binaries
        packages.here-all = pkgs.symlinkJoin {
          name = "here-all";
          paths = [
            self.packages.${system}.here-linux-x86_64
            self.packages.${system}.here-linux-aarch64
            self.packages.${system}.here-macos-x86_64
            self.packages.${system}.here-macos-aarch64
          ];
        };

        formatter = pkgs.nixpkgs-fmt;

        checks = {
          build = self.packages.${system}.default;

          format-check = pkgs.runCommand "format-check" { } ''
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./flake.nix}
            touch $out
          '';
        };
      });
}
