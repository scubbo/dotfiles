{
  description = "My NixOS configuration";

  inputs = {
    # Replace with the branch matching your NixOS release.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }: {
    nixosConfigurations.phi = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./configuration.nix
        (nixos-hardware + "/framework/13-inch/13th-gen-intel")
      ];
    };
  };
}

