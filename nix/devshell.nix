# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: MPL-2.0

_: {
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      # XcodeGen generates the Xcode project; Xcode itself comes from Apple.
      devShells.default = pkgs.mkShell {
        packages = [
          config.treefmt.build.wrapper
          pkgs.just
          pkgs.reuse
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.xcodegen ];
      };

      formatter = config.treefmt.build.wrapper;
    };
}
