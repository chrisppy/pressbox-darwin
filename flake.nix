# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: MPL-2.0

{
  description = "pressbox-darwin: the iPhone, iPad and Mac app for the pressbox feed reader";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    devfmt = {
      url = "github:red-oxide/devfmt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.devfmt.lib.mkFlake { inherit inputs; } {
      imports = [
        (inputs.devfmt.lib.importTree ./nix)
      ];
    };
}
