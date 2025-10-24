#!/bin/bash
# dev-release.sh - Creates a new dev release

# Check if there are changes to commit
if [ -n "$(git status --porcelain)" ]; then
    git add .
    git commit -m "Dev" || { echo "Commit failed!"; exit 1; }
    git push origin main || { echo "Push failed!"; exit 1; }
else
    echo "No changes to commit"
fi

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

git tag -a "$NEW_TAG" -m "Dev release $NEW_TAG" || { echo "Tag creation failed!"; exit 1; }
git push origin "$NEW_TAG" || { echo "Tag push failed!"; exit 1; }

echo "Dev release $NEW_TAG created and pushed!"
