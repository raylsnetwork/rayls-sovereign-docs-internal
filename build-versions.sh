#!/bin/bash
set -e

# Configs
VERSIONS="${VERSIONS:-}"
DEFAULT_VERSION="${DEFAULT_VERSION:-}"
OUTPUT_DIR="${OUTPUT_DIR:-site}"

# Validation
if [ -z "$VERSIONS" ]; then
  echo "Uso: VERSIONS=\"version/2.6.0,version/2.6.1\" ./build-versions.sh"
  exit 1
fi

# Function to extract version number from ref
extract_version() {
  echo "$1" | sed -E 's/^(version[\/\-]?|v)//g'
}

# Save the current branch to return later
ORIGINAL_BRANCH=$(git branch --show-current)

echo "=== Building versioned documentation ==="
echo "Versions: $VERSIONS"
echo ""

IFS=',' read -ra REF_ARRAY <<< "$VERSIONS"
LAST_VERSION=""

for REF in "${REF_ARRAY[@]}"; do
  REF=$(echo "$REF" | xargs)
  VERSION=$(extract_version "$REF")

  echo "----------------------------------------"
  echo "Building: $REF -> $VERSION"

  git checkout "$REF" 2>/dev/null || git checkout -b "$REF" "origin/$REF" || {
    echo "  ERROR: Could not checkout $REF"
    continue
  }

  mike deploy "$VERSION"
  LAST_VERSION="$VERSION"
  echo "  Done!"
done

# Define alias 'latest' to the last built version
if [ -n "$LAST_VERSION" ]; then
  echo ""
  echo "Setting 'latest' alias to: $LAST_VERSION"
  mike deploy --update-aliases "$LAST_VERSION" latest
fi

DEFAULT="${DEFAULT_VERSION:-latest}"
echo "Setting default: $DEFAULT"
mike set-default "$DEFAULT"

# go back to original branch
git checkout "$ORIGINAL_BRANCH"

echo ""
echo "=== Build complete ==="
echo "Static files exported to: $OUTPUT_DIR/"
mike list
