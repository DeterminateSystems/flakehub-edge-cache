{
  inputs = {
    nixpkgs.follows = "minnows/nixpkgs";

    minnows.url = "https://flakehub.com/f/DeterminateSystems/minnows/*";
    minnows-platform-qemu.url = "https://flakehub.com/f/DeterminateSystems/minnows-platform-qemu/*";
  };

  outputs = inputs: {
    minnowsSystems.aarch64-linux.testvm = import ./system.nix {
      inherit inputs;
      system = "aarch64-linux";
    };
  };
}
