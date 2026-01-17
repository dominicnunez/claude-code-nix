{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  # Runtime dependencies
  procps,
  # Linux sandbox dependencies
  bubblewrap,
  socat,
}:

let
  versionInfo = lib.importJSON ./version.json;
  version = versionInfo.version;
  hashes = versionInfo.hashes;

  # Map Nix system to Claude Code platform suffix
  platformMap = {
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
    "x86_64-darwin" = "darwin-x64";
    "aarch64-darwin" = "darwin-arm64";
  };

  # GCS bucket base URL for Claude Code releases
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  isDarwin = stdenv.hostPlatform.isDarwin;
  isLinux = stdenv.hostPlatform.isLinux;

  system = stdenv.hostPlatform.system;
  platform = platformMap.${system} or (throw "Unsupported system: ${system}");
  hash = hashes.${system} or (throw "No hash for system: ${system}");

  src = fetchurl {
    url = "${baseUrl}/${version}/${platform}/claude";
    inherit hash;
  };

  # Home Manager detection wrapper script
  wrapperScript = ''
    #!/usr/bin/env bash

    # Verbose output (opt-in via CLAUDE_CODE_NIX_VERBOSE=1)
    verbose=''${CLAUDE_CODE_NIX_VERBOSE:-0}

    # Home Manager detection function
    is_home_manager_active() {
      [[ -n "''${HM_SESSION_VARS:-}" ]] ||
      [[ -d "$HOME/.config/home-manager" ]] ||
      [[ -d "/etc/profiles/per-user/$USER" ]]
    }

    # Symlink management (only when target changes)
    manage_symlink() {
      local target_dir="$HOME/.local/bin"
      local symlink_path="$target_dir/claude"
      local binary_path="@out@/bin/.claude-unwrapped"

      # If Home Manager is active, clean up our symlink if it exists and skip creation
      if is_home_manager_active; then
        if [[ -L "$symlink_path" ]]; then
          local link_target
          link_target="$(readlink "$symlink_path" 2>/dev/null || echo "")"
          # Match exact current path OR any older version of this package
          if [[ "$link_target" == "$binary_path" ]] || \
             [[ "$link_target" == /nix/store/*-claude-code-* ]]; then
            rm -f "$symlink_path"
            [[ "$verbose" == "1" ]] && echo "[claude-code-nix] Removed symlink (Home Manager now manages claude)" >&2
          fi
        fi
        return 0
      fi

      # Check if symlink already points to the correct target
      local current_target
      current_target="$(readlink -f "$symlink_path" 2>/dev/null || echo "")"

      if [[ "$current_target" == "$binary_path" ]]; then
        return 0  # Already correct
      fi

      # Create or update symlink
      mkdir -p "$target_dir"
      ln -sf "$binary_path" "$symlink_path"
      [[ "$verbose" == "1" ]] && echo "[claude-code-nix] Created symlink: $symlink_path -> $binary_path" >&2
    }

    # Run symlink management
    manage_symlink

    # Execute the actual binary
    exec "@out@/bin/.claude-unwrapped" "$@"
  '';
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit version;

  # Source is a single binary file, not an archive
  dontUnpack = true;

  # The Claude Code binary is a self-contained Bun executable
  # Stripping it corrupts the embedded JavaScript bundle
  dontStrip = true;

  nativeBuildInputs = [
    makeWrapper
  ];

  installPhase = ''
        runHook preInstall

        mkdir -p $out/bin

        # Install the binary
        install -m755 ${src} $out/bin/.claude-unwrapped

        # Install wrapper script with Home Manager detection
        cat > $out/bin/claude << 'WRAPPER_EOF'
    ${wrapperScript}
    WRAPPER_EOF
        chmod +x $out/bin/claude

        # Substitute @out@ placeholder
        substituteInPlace $out/bin/claude --replace-quiet "@out@" "$out"

        # Wrap with runtime dependencies, disable auto-updater, and skip installation checks
        # DISABLE_INSTALLATION_CHECKS prevents false "installMethod is native, but claude
        # command not found at ~/.local/bin/claude" errors since Nix manages the binary path
        wrapProgram $out/bin/claude \
          --set DISABLE_AUTOUPDATER 1 \
          --set DISABLE_INSTALLATION_CHECKS 1 \
          --prefix PATH : ${
            lib.makeBinPath (
              [
                procps # For pgrep/ps used by node-tree-kill
              ]
              ++ lib.optionals isLinux [
                bubblewrap # Linux sandbox
                socat # Network proxy for sandbox
              ]
            )
          }

        runHook postInstall
  '';

  meta = with lib; {
    description = "Claude Code - Anthropic's agentic coding tool that lives in your terminal";
    homepage = "https://claude.ai/code";
    license = licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "claude";
  };
}
