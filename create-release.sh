#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if tag name is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Tag name required${NC}"
    echo "Usage: $0 <tag-name>"
    echo "Example: $0 v2.1.0"
    exit 1
fi

TAG_NAME="$1"

# Validate tag format - must start with 'v'
if [[ ! "$TAG_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+.*$ ]]; then
    echo -e "${RED}Error: Tag name must start with 'v' and follow semver format (e.g., v2.1.0)${NC}"
    exit 1
fi

# Check if tag already exists
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo -e "${RED}Error: Tag $TAG_NAME already exists${NC}"
    exit 1
fi

# Check working tree is clean
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${RED}Error: Working tree is dirty. Commit or stash changes first.${NC}"
    git status --short
    exit 1
fi

echo -e "${GREEN}Creating release: $TAG_NAME${NC}"
echo

# Generate version.libsonnet with the new tag
SHA=$(git rev-parse HEAD)
cat > version.libsonnet <<EOF
{
  sha: '${SHA}',
  tag: '${TAG_NAME}',
}
EOF

echo -e "${GREEN}✓${NC} Generated version.libsonnet with tag: $TAG_NAME"

# Show the diff
echo
echo "Changes to version.libsonnet:"
git diff version.libsonnet

# Confirm before committing
echo
read -p "Commit these changes? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    git checkout version.libsonnet
    echo -e "${YELLOW}Aborted. version.libsonnet restored.${NC}"
    exit 1
fi

# Commit the version change
git add version.libsonnet
git commit -m "chore: Update version to $TAG_NAME"
COMMIT_SHA=$(git rev-parse HEAD)

# Update version.libsonnet with the new commit SHA
cat > version.libsonnet <<EOF
{
  sha: '${COMMIT_SHA}',
  tag: '${TAG_NAME}',
}
EOF

# Amend the commit with correct SHA
git add version.libsonnet
git commit --amend --no-edit

echo -e "${GREEN}✓${NC} Committed version update"

# Create the tag
git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
echo -e "${GREEN}✓${NC} Created tag: $TAG_NAME"

# Get available remotes
echo
mapfile -t AVAILABLE_REMOTES < <(git remote)

if [ ${#AVAILABLE_REMOTES[@]} -eq 0 ]; then
    echo -e "${YELLOW}No remotes configured. Tag created locally only.${NC}"
    exit 0
fi

echo "Available remotes:"
for remote in "${AVAILABLE_REMOTES[@]}"; do
    url=$(git remote get-url "$remote" 2>/dev/null || echo "")
    echo "  - $remote ($url)"
done

# Build dynamic menu
echo
echo "Push to remote(s):"
menu_index=1
declare -A menu_options

for remote in "${AVAILABLE_REMOTES[@]}"; do
    echo "  $menu_index) $remote"
    menu_options[$menu_index]="$remote"
    ((menu_index++))
done

# Add "all remotes" option if more than one remote
if [ ${#AVAILABLE_REMOTES[@]} -gt 1 ]; then
    all_index=$menu_index
    echo "  $menu_index) all remotes (${AVAILABLE_REMOTES[*]})"
    ((menu_index++))
fi

skip_index=$menu_index
echo "  $menu_index) skip (don't push) [default]"

echo
read -p "Select option [default=$skip_index]: " USER_INPUT

# Use skip as default if no input
if [ -z "$USER_INPUT" ]; then
    USER_INPUT=$skip_index
fi

# Handle selection
if [ "$USER_INPUT" = "$skip_index" ]; then
    echo -e "${YELLOW}Skipping push. You can manually push with:${NC}"
    echo "  git push <remote> main"
    echo "  git push <remote> $TAG_NAME"
    exit 0
elif [ ${#AVAILABLE_REMOTES[@]} -gt 1 ] && [ "$USER_INPUT" = "$all_index" ]; then
    REMOTES=("${AVAILABLE_REMOTES[@]}")
elif [ -n "${menu_options[$USER_INPUT]}" ]; then
    REMOTES=("${menu_options[$USER_INPUT]}")
else
    echo -e "${RED}Invalid option. Aborting.${NC}"
    exit 1
fi

# Push to selected remotes
echo
for remote in "${REMOTES[@]}"; do
    if git remote | grep -q "^${remote}$"; then
        echo -e "${GREEN}Pushing to $remote...${NC}"
        git push "$remote" main
        git push "$remote" "$TAG_NAME"
        echo -e "${GREEN}✓${NC} Pushed to $remote"
    else
        echo -e "${RED}Warning: Remote '$remote' not found. Skipping.${NC}"
    fi
done

echo
echo -e "${GREEN}✓ Release $TAG_NAME created successfully!${NC}"
