{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    complement = {
      url = "github:matrix-org/complement?ref=main";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils

    , fenix
    , crane

    , complement
    }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;

        overlays = [
          (final: prev: {
            rocksdb = prev.rocksdb.overrideAttrs (old:
              let
                version = "8.8.1";
              in
              {
                inherit version;
                src = pkgs.fetchFromGitHub {
                  owner = "facebook";
                  repo = "rocksdb";
                  rev = "v${version}";
                  hash = "sha256-eE29iojVhR660mXTdX7yT+oqFk5oteBjZcLkmgHQWaY=";
                };
              });
          })
        ];
      };

      stdenv = if pkgs.stdenv.isLinux then
        pkgs.stdenvAdapters.useMoldLinker pkgs.stdenv
      else
        pkgs.stdenv;

      # Nix-accessible `Cargo.toml`
      cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);

      # The Rust toolchain to use
      toolchain = fenix.packages.${system}.toolchainOf {
        # Use the Rust version defined in `Cargo.toml`
        channel = cargoToml.package.rust-version;

        # THE rust-version HASH
        sha256 = "sha256-gdYqng0y9iHYzYPAdkC/ka3DRny3La/S5G8ASj0Ayyc=";
      };

      mkToolchain = fenix.packages.${system}.combine;

      buildToolchain = mkToolchain (with toolchain; [
        cargo
        rustc
      ]);

      devToolchain = mkToolchain (with toolchain; [
        cargo
        clippy
        rust-src
        rustc

        # Always use nightly rustfmt because most of its options are unstable
        fenix.packages.${system}.latest.rustfmt
      ]);

      builder =
        ((crane.mkLib pkgs).overrideToolchain buildToolchain).buildPackage;

      nativeBuildInputs = (with pkgs.rustPlatform; [
        bindgenHook
      ]);

      env = {
        ROCKSDB_INCLUDE_DIR = "${pkgs.rocksdb}/include";
        ROCKSDB_LIB_DIR = "${pkgs.rocksdb}/lib";
      };
    in
    {
      packages.default = builder {
        src = ./.;

        doCheck = false;

        inherit
          env
          nativeBuildInputs
          stdenv;

        meta.mainProgram = "conduit";
      };

      packages.oci-image =
      let
        package = self.outputs.packages.${system}.default;
        config = pkgs.writeText "conduit.toml" ''
          [global]
          database_path = "/database"
          database_backend = "rocksdb"
          port = [8008, 8448]
          address = "0.0.0.0"
          allow_federation = true
          allow_registration = true
        '';
      in
      pkgs.dockerTools.buildImage {
        name = package.pname;
        tag = "latest";

        copyToRoot = pkgs.buildEnv {
          name = "root";

          paths = [
            package
          ];

          pathsToLink = [
            "/bin"
          ];
        };

        config = {
          Env = [
            "CONDUIT_CONFIG=${config}"
          ];

          Entrypoint = [
            "${pkgs.lib.getExe' pkgs.tini "tini"}"
            "--"
          ];

          Cmd = [
            "${pkgs.lib.getExe package}"
          ];

          ExposedPorts = {
            "8008" = {};
            "8448" = {};
          };
        };
      };

      devShells.default = (pkgs.mkShell.override { inherit stdenv; }) {
        env = env // {
          # Rust Analyzer needs to be able to find the path to default crate
          # sources, and it can read this environment variable to do so. The
          # `rust-src` component is required in order for this to work.
          RUST_SRC_PATH = "${devToolchain}/lib/rustlib/src/rust/library";

          COMPLEMENT_SRC = complement.outPath;
        };

        # Development tools
        nativeBuildInputs = nativeBuildInputs ++ [
          devToolchain
        ] ++ (with pkgs; [
          engage

          # Needed for Complement
          go
          olm
        ]);
      };
    });
}
