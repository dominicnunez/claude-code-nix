# claude-code-nix

Nix flake for [Claude Code](https://claude.ai/code) - Anthropic's agentic coding tool that lives in your terminal.

**Features:**
- Direct binary packaging from Anthropic's official distribution
- Smart Home Manager detection with automatic symlink management
- Pre-built binaries via Cachix for instant installation
- Automated updates for new Claude Code versions
- Linux and macOS support (x86_64 and aarch64)

## Quick Start

**Try without installing:**
```bash
nix run github:dominicnunez/claude-code-nix
```

**Install to your profile:**
```bash
nix profile add github:dominicnunez/claude-code-nix
```

## Cachix Setup

Use the public binary cache to skip building from source.

### Option 1: NixOS Configuration

```nix
{ config, pkgs, ... }:
{
  nix.settings = {
    substituters = [ "https://claude-code-nix.cachix.org" ];
    trusted-public-keys = [ "claude-code-nix.cachix.org-1:VzA1HW3CkJnuSQaPE1t7OfSaleacUnO19VrZ3hJFH+0=" ];
  };
}
```

### Option 2: nix.conf

Add to `~/.config/nix/nix.conf`:
```
extra-substituters = https://claude-code-nix.cachix.org
extra-trusted-public-keys = claude-code-nix.cachix.org-1:VzA1HW3CkJnuSQaPE1t7OfSaleacUnO19VrZ3hJFH+0=
```

### Option 3: Flake nixConfig

```nix
{
  nixConfig = {
    extra-substituters = [ "https://claude-code-nix.cachix.org" ];
    extra-trusted-public-keys = [ "claude-code-nix.cachix.org-1:VzA1HW3CkJnuSQaPE1t7OfSaleacUnO19VrZ3hJFH+0=" ];
  };

  inputs.claude-code-nix.url = "github:dominicnunez/claude-code-nix";
  # ...
}
```

## Installation Methods

### As a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    claude-code-nix.url = "github:dominicnunez/claude-code-nix";
  };

  outputs = { self, nixpkgs, claude-code-nix, ... }: {
    # NixOS configuration
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            claude-code-nix.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

### With Home Manager

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    claude-code-nix.url = "github:dominicnunez/claude-code-nix";
  };

  outputs = { self, nixpkgs, home-manager, claude-code-nix, ... }: {
    homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        ({ pkgs, ... }: {
          home.packages = [
            claude-code-nix.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

### Using the Overlay

```nix
{
  inputs.claude-code-nix.url = "github:dominicnunez/claude-code-nix";

  outputs = { self, nixpkgs, claude-code-nix }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nixpkgs.overlays = [ claude-code-nix.overlays.default ];
          environment.systemPackages = [ pkgs.claude-code ];
        }
      ];
    };
  };
}
```

## Home Manager Integration

This package includes smart Home Manager detection. When running Claude Code:

**If Home Manager is detected:**
- Skips creating `~/.local/bin/claude` symlink
- Cleans up symlinks that were created by this package
- Respects your declarative Home Manager configuration

**If Home Manager is NOT detected:**
- Creates `~/.local/bin/claude` symlink for convenience
- Allows running `claude` from anywhere if `~/.local/bin` is in your PATH

### Detection Indicators

Home Manager is detected if any of these conditions are true:
- `HM_SESSION_VARS` environment variable is set
- `~/.config/home-manager` directory exists
- `/etc/profiles/per-user/$USER` directory exists

### Enabling Verbose Messages

To enable informational messages from the wrapper:

```bash
export CLAUDE_CODE_NIX_VERBOSE=1
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_NIX_VERBOSE` | Set to `1` to enable wrapper messages | unset |
| `DISABLE_AUTOUPDATER` | Set automatically to `1` to disable Claude's auto-updater | `1` |
| `DISABLE_INSTALLATION_CHECKS` | Set automatically to `1` to skip native binary path validation | `1` |

## Contributing

### How Updates Work

1. **Automated Check**: GitHub Actions checks for new Claude Code versions
2. **Version Detection**: Script queries the GCS manifest for latest version
3. **Hash Fetching**: If newer version found, fetches SHA256 hashes from manifest
4. **Validation**: Runs `nix flake check` to verify package builds correctly
5. **PR Creation**: Creates PR with updated `version.json`
6. **Merge**: PR is automatically squash-merged

### Manual Update

```bash
# Check for updates (dry run)
./update.sh

# Check and apply update
./update.sh --update
```

### Local Development

```bash
# Enter development shell
nix develop

# Build the package
nix build

# Run the built package
nix run

# Check flake
nix flake check
```

### Repository Structure

```
.
├── flake.nix           # Flake definition with outputs
├── flake.lock          # Locked dependencies
├── package.nix         # Claude Code package derivation
├── version.json        # Current version and platform hashes
├── update.sh           # Update script for GCS manifest
├── README.md           # This file
└── .github/workflows/
    ├── update.yml      # Automated update check workflow
    ├── ci.yml          # PR build validation workflow
    └── cachix.yml      # Binary cache push workflow
```

## License

The Nix packaging code in this repository is MIT licensed.

Claude Code itself is proprietary software from Anthropic. See [Anthropic's terms](https://www.anthropic.com/legal/consumer-terms) for usage terms.
