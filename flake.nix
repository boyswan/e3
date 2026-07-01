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
            pkgs.libvterm-neovim
          ];
          LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.sdl3
            pkgs.sdl3-ttf
            pkgs.libvterm-neovim
          ];
          NIX_LDFLAGS = "-L${pkgs.sdl3}/lib -L${pkgs.sdl3-ttf}/lib -L${pkgs.libvterm-neovim}/lib";
          buildInputs = with pkgs; [
            odin
            ols
            sdl3
            sdl3-ttf
            fontconfig
            libvterm-neovim
          ];
        };
      });
}
