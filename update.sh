#!/usr/bin/env bash
set -euo pipefail

# Claude Code GCS distribution
BASE_URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
VERSION_FILE="$(dirname "$0")/version.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Platform mapping: Nix system -> Claude platform
declare -A PLATFORMS=(
  ["x86_64-linux"]="linux-x64"
  ["aarch64-linux"]="linux-arm64"
  ["x86_64-darwin"]="darwin-x64"
  ["aarch64-darwin"]="darwin-arm64"
)

# Get the latest version from GCS
get_latest_version() {
  curl -s "$BASE_URL/latest"
}

# Get the current version from version.json
get_current_version() {
  jq -r '.version' "$VERSION_FILE"
}

# Fetch manifest and extract hash for a platform
get_hash_from_manifest() {
  local version="$1"
  local claude_platform="$2"
  local manifest

  manifest=$(curl -s "$BASE_URL/$version/manifest.json")
  echo "$manifest" | jq -r ".platforms[\"$claude_platform\"].checksum // empty"
}

# Convert hex SHA256 to SRI format
hex_to_sri() {
  local hex="$1"
  nix-hash --type sha256 --to-sri "$hex"
}

# Update version.json with new version and hashes
update_version_file() {
  local new_version="$1"

  echo -e "${GREEN}Updating to version $new_version${NC}"

  # Fetch hashes from manifest and convert to SRI format
  local hash_x86_64_linux hash_aarch64_linux hash_x86_64_darwin hash_aarch64_darwin

  echo -e "${YELLOW}Fetching hashes from manifest...${NC}" >&2

  local hex_hash
  hex_hash=$(get_hash_from_manifest "$new_version" "linux-x64")
  hash_x86_64_linux=$(hex_to_sri "$hex_hash")
  echo -e "  x86_64-linux: $hash_x86_64_linux" >&2

  hex_hash=$(get_hash_from_manifest "$new_version" "linux-arm64")
  hash_aarch64_linux=$(hex_to_sri "$hex_hash")
  echo -e "  aarch64-linux: $hash_aarch64_linux" >&2

  hex_hash=$(get_hash_from_manifest "$new_version" "darwin-x64")
  hash_x86_64_darwin=$(hex_to_sri "$hex_hash")
  echo -e "  x86_64-darwin: $hash_x86_64_darwin" >&2

  hex_hash=$(get_hash_from_manifest "$new_version" "darwin-arm64")
  hash_aarch64_darwin=$(hex_to_sri "$hex_hash")
  echo -e "  aarch64-darwin: $hash_aarch64_darwin" >&2

  # Update version.json
  jq --arg version "$new_version" \
     --arg x86_64_linux "$hash_x86_64_linux" \
     --arg aarch64_linux "$hash_aarch64_linux" \
     --arg x86_64_darwin "$hash_x86_64_darwin" \
     --arg aarch64_darwin "$hash_aarch64_darwin" \
     '.version = $version |
      .hashes["x86_64-linux"] = $x86_64_linux |
      .hashes["aarch64-linux"] = $aarch64_linux |
      .hashes["x86_64-darwin"] = $x86_64_darwin |
      .hashes["aarch64-darwin"] = $aarch64_darwin' \
     "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"

  echo -e "${GREEN}Successfully updated version.json${NC}"
}

# Main script
main() {
  local current_version latest_version

  current_version=$(get_current_version)
  latest_version=$(get_latest_version)

  if [[ -z "$latest_version" ]]; then
    echo -e "${RED}Failed to fetch latest version${NC}"
    exit 1
  fi

  echo "Current version: $current_version"
  echo "Latest version:  $latest_version"

  if [[ "$current_version" == "$latest_version" ]]; then
    echo -e "${GREEN}Already up to date${NC}"
    echo "UPDATE_NEEDED=false"
    exit 0
  fi

  echo -e "${YELLOW}Update available: $current_version -> $latest_version${NC}"
  echo "UPDATE_NEEDED=true"
  echo "NEW_VERSION=$latest_version"

  # If --update flag is passed, perform the update
  if [[ "${1:-}" == "--update" ]]; then
    update_version_file "$latest_version"
  else
    echo -e "${YELLOW}Run with --update to apply the update${NC}"
  fi
}

main "$@"
