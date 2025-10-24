#!/bin/bash
# dev-release.sh - Creates a new dev release

# Commit all changes
git add .
git commit -m "Dev" || { echo "Commit failed!"; exit 1; }
git push origin main || { echo "Push failed!"; exit 1; }

# Get the latest dev tag
LATEST=$(git tag -l "dev-*" | sort -V | tail -n 1)

if [ -z "$LATEST" ]; then
    # First dev release
    NEW_TAG="dev-v0.1.0"
else
    # Increment version (simple increment)
    VERSION=$(echo $LATEST | sed 's/dev-v//')
    NEW_TAG="dev-v$(echo $VERSION | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g')"
fi

echo "Creating new dev release: $NEW_TAG"

git tag -a "$NEW_TAG" -m "Dev release $NEW_TAG"
git push origin "$NEW_TAG"

# Create GitHub release with install.sh as downloadable asset
if command -v gh &> /dev/null; then
    gh release create "$NEW_TAG" install/install.sh \
        --prerelease \
        --title "Dev Release $NEW_TAG" \
        --notes "Development release - download install.sh to get started"
    echo "GitHub release created with install.sh attached!"
else
    echo "Dev release $NEW_TAG created and pushed!"
    echo "To attach install.sh as a release asset, install GitHub CLI: https://cli.github.com/"
fi
