---
name: refresh-contributors-cache
description: Force GitHub to recompute a repository's Contributors list by temporarily switching the default branch and renaming it away and back. Use when an unwanted account (such as Claude) stays in Contributors even though the commits were fixed or removed.
---

# Refresh the GitHub Contributors cache

Reply in the user's language. Users invoke this after reloading, incognito windows, waiting and changing attribution settings did not help, so do not suggest those, and do not talk the user out of running it because the API list already looks clean (the web page is cached separately). Just run it.

## Where it can run
It needs `gh` logged in as a repository admin on a machine that can write repository settings. Cloud or sandboxed sessions whose GitHub proxy refuses settings writes (HTTP 403 such as "Repository settings writes are not permitted through this proxy") cannot run it. In that case do the read-only checks, create nothing, and hand the user the script command below to run on their own machine. Do not switch to a browser or another route to perform the same change.

## Checks (read-only)
1. `gh auth status` succeeds. If `gh` is missing: `winget install --id GitHub.cli` (Windows, then reopen the terminal), `brew install gh` (macOS), or https://cli.github.com; then `gh auth login`.
2. `gh api repos/$REPO --jq '{default_branch, admin: .permissions.admin}'`: `admin` must be `true`. `$DEF` is the default branch.
3. `gh api repos/$REPO/branches/$DEF --jq .protected` and `gh api "repos/$REPO/pulls?state=open&per_page=100" --jq length`. Mention protection rules and open PRs in the confirmation; PRs normally follow a branch rename, protection rules may need a manual look.
4. Neither `tmp-refresh-contributors` nor `$DEF-old-refresh` may exist already: `gh api repos/$REPO/git/matching-refs/heads/<name> --jq '.[].ref'` must not print `refs/heads/<name>`. Do not use `gh api repos/$REPO/branches/<name>` for this: it follows renames, so after any earlier refresh `$DEF-old-refresh` resolves to the real default branch and looks like it exists. If one exists from an earlier failed run, include deleting or restoring it in the plan.
5. If the `check-contributors` skill found Co-authored-by trailers or authorship for the account still in history, say that the account will come back after the refresh and offer `strip-coauthors` first.

## Confirm once
List repository, default branch, check results and the steps below in one message and wait for an explicit yes. If the user already said to just run it when invoking, that is the yes. After that, run to the end without asking again.

## Run
Preferred: the bundled script, which does every step through the API (no clone needed) and rolls back on failure. The scripts are in this plugin's `scripts/` folder, two levels up from this skill's base directory (`<base>/../../scripts/`). If they are not there, run the manual steps below.

- macOS/Linux/Git Bash: `bash <scripts>/refresh.sh -y OWNER/REPO`
- Windows PowerShell: `powershell -ExecutionPolicy Bypass -File <scripts>\refresh.ps1 OWNER/REPO -Yes`

Manual steps, each as its own command so a failure shows where it stopped:
```bash
REPO=OWNER/REPO; DEF=main; TMP=tmp-refresh-contributors; OLD=$DEF-old-refresh
SHA=$(gh api repos/$REPO/git/ref/heads/$DEF --jq .object.sha)
gh api -X POST repos/$REPO/git/refs -f ref=refs/heads/$TMP -f sha=$SHA      # 1 temp branch
gh api -X PATCH repos/$REPO -f default_branch=$TMP                          # 2 make it default
gh api -X POST repos/$REPO/branches/$DEF/rename -f new_name=$OLD            # 3 rename away
gh api -X POST repos/$REPO/branches/$OLD/rename -f new_name=$DEF            #   and back
gh api -X PATCH repos/$REPO -f default_branch=$DEF                          # 4 restore default
gh api -X DELETE repos/$REPO/git/refs/heads/$TMP                            # 5 delete temp
```
GitHub applies renames asynchronously; if a step right after a rename fails with 404/422, wait two seconds and retry it (up to five times).

## If a step fails
1. Read the state: `gh api repos/$REPO --jq .default_branch` and `gh api "repos/$REPO/branches?per_page=100" --jq '.[].name'`.
2. Undo in this order, whatever applies: rename `$OLD` back to `$DEF`; set the default branch back to `$DEF`; delete `$TMP`.
3. If the failure is a permission or proxy refusal, do not retry the same change another way. Report exactly what was done and what remains, and give the user the remaining commands (or the script command) to run on their own machine.

## Finish
Report: default branch restored, temporary branch deleted, and the output of `gh api "repos/$REPO/contributors?per_page=100" --jq '.[].login'`. Results only, no extra advice.
