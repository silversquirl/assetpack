{
  inputs = {
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";
  };

  outputs = inputs:
    inputs.zig.inputs.flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import inputs.zig.inputs.nixpkgs {inherit system;};
      zig = inputs.zig.packages.${system}.master;
      zls = inputs.zls.packages.${system}.zls;
      zig-stable = pkgs.linkFarm "zig-stable" [
        {
          name = "bin/zig-stable";
          path = "${inputs.zig.packages.${system}."0.14.1"}/bin/zig";
        }
      ];
    in {
      devShells.default = pkgs.mkShellNoCC {
        packages = [zig zls zig-stable];
      };
    });
}
