{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware";

    # AI Coding agent packages, including opencode2
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, nixos-hardware, llm-agents, ... }: {
    nixosConfigurations.phi = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      specialArgs = {
        inherit llm-agents;
      };

      modules = [
        ./configuration.nix
        (nixos-hardware + "/framework/13-inch/13th-gen-intel")
      ];
    };
  };
}

