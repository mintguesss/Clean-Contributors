#!/usr/bin/env bash
# Force GitHub to recompute a repository's Contributors list.
#
# How: create a temporary branch, make it the default branch, rename the real
# default branch away and back, restore it as the default, delete the
# temporary branch. Everything goes through the GitHub REST API, so no local
# clone is needed.
#
# Usage: ./refresh.sh [-y] OWNER/REPO
#   -y   skip the confirmation prompt
#
# Requires: gh (logged in, admin on the repository).

set -euo pipefail

YES=0; REPO=""
for arg in "$@"; do
  case "$arg" in
    -y|--yes) YES=1 ;;
    *) REPO="$arg" ;;
  esac
done
if [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "Usage: $0 [-y] OWNER/REPO" >&2
  exit 2
fi
TMP="tmp-refresh-contributors"

die() { echo "Error: $*" >&2; exit 1; }

command -v gh >/dev/null || die "gh is not installed: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"

DEF=$(gh api "repos/$REPO" --jq .default_branch) || die "cannot read $REPO"
ADMIN=$(gh api "repos/$REPO" --jq .permissions.admin)
[[ "$ADMIN" == "true" ]] || die "you need admin permission on $REPO"
OLD="${DEF}-old-refresh"

if gh api "repos/$REPO/branches/$TMP" >/dev/null 2>&1; then
  die "branch '$TMP' already exists on $REPO; delete it first"
fi
if gh api "repos/$REPO/branches/$OLD" >/dev/null 2>&1; then
  die "branch '$OLD' already exists on $REPO; delete or rename it first"
fi
SHA=$(gh api "repos/$REPO/git/ref/heads/$DEF" --jq .object.sha)
PROTECTED=$(gh api "repos/$REPO/branches/$DEF" --jq .protected)
OPEN_PRS=$(gh api "repos/$REPO/pulls?state=open&per_page=100" --jq length)

echo "Repository:      $REPO"
echo "Default branch:  $DEF ($SHA)"
echo "Protected:       $PROTECTED"
echo "Open PRs:        $OPEN_PRS"
echo
echo "Steps: create '$TMP' -> make it default -> rename '$DEF' to '$OLD' and back"
echo "       -> make '$DEF' default again -> delete '$TMP'"
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Proceed? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# Track progress so a failure can be rolled back.
CREATED_TMP=0; SWITCHED=0; RENAMED_AWAY=0

retry() {  # retry a command a few times (GitHub applies renames asynchronously)
  local n=0
  until "$@"; do
    n=$((n + 1)); [[ $n -ge 5 ]] && return 1
    sleep 2
  done
}

rollback() {
  echo
  echo "Something failed. Rolling back..." >&2
  if [[ $RENAMED_AWAY -eq 1 ]]; then
    retry gh api -X POST "repos/$REPO/branches/$OLD/rename" -f new_name="$DEF" --silent \
      || echo "  ! could not rename '$OLD' back to '$DEF' - do it in Settings > Branches" >&2
  fi
  if [[ $SWITCHED -eq 1 ]]; then
    retry gh api -X PATCH "repos/$REPO" -f default_branch="$DEF" --silent \
      || echo "  ! could not set default branch back to '$DEF' - do it in Settings > General" >&2
  fi
  if [[ $CREATED_TMP -eq 1 ]]; then
    retry gh api -X DELETE "repos/$REPO/git/refs/heads/$TMP" --silent \
      || echo "  ! could not delete '$TMP' - delete it in the Branches page" >&2
  fi
  echo "Current default branch: $(gh api "repos/$REPO" --jq .default_branch 2>/dev/null || echo unknown)" >&2
}
trap 'rollback' ERR

echo "1/5 Creating $TMP"
gh api -X POST "repos/$REPO/git/refs" -f ref="refs/heads/$TMP" -f sha="$SHA" --silent
CREATED_TMP=1

echo "2/5 Setting default branch to $TMP"
retry gh api -X PATCH "repos/$REPO" -f default_branch="$TMP" --silent
SWITCHED=1

echo "3/5 Renaming $DEF -> $OLD -> $DEF"
retry gh api -X POST "repos/$REPO/branches/$DEF/rename" -f new_name="$OLD" --silent
RENAMED_AWAY=1
retry gh api -X POST "repos/$REPO/branches/$OLD/rename" -f new_name="$DEF" --silent
RENAMED_AWAY=0

echo "4/5 Setting default branch back to $DEF"
retry gh api -X PATCH "repos/$REPO" -f default_branch="$DEF" --silent
SWITCHED=0

echo "5/5 Deleting $TMP"
retry gh api -X DELETE "repos/$REPO/git/refs/heads/$TMP" --silent
CREATED_TMP=0

trap - ERR
echo
echo "Done. Default branch: $(gh api "repos/$REPO" --jq .default_branch)"
echo "Contributors (API):"
gh api "repos/$REPO/contributors?per_page=100" --jq '.[].login' | sed 's/^/  /'
