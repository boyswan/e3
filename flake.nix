{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.sdl3
            pkgs.sdl3-ttf
          ];
          LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.sdl3
            pkgs.sdl3-ttf
          ];
          NIX_LDFLAGS = "-L${pkgs.sdl3}/lib -L${pkgs.sdl3-ttf}/lib";
          buildInputs = with pkgs; [
            odin
            ols
            sdl3
            sdl3-ttf
            fontconfig
            curl
            git
            xz
          ];
          shellHook = ''
            export GHOSTTY_PREFIX="$PWD/vendor/ghostty-vt/$(uname -s)-$(uname -m)"
            export LIBRARY_PATH="$GHOSTTY_PREFIX/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
            export LD_LIBRARY_PATH="$GHOSTTY_PREFIX/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          '';
        };
      });
}
