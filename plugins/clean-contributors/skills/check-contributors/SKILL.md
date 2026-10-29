---
name: check-contributors
description: Read-only diagnosis of why an unwanted account (such as Claude) shows up in a GitHub repository's Contributors list. Use when the user asks why someone is listed as a contributor, or before stripping co-author trailers or refreshing the contributors cache.
---

# Check contributors

Read-only. Changes nothing. Reply in the user's language.

## Input
A repository as `OWNER/REPO` or a GitHub URL. If the user gives none and the working directory is a git clone, use its `origin`. Optionally the account to look for; default to Claude. Match Claude by e-mail: `noreply@anthropic.com` (Claude Code trailers, any model name) and `claude[bot]` (the Claude GitHub App). Do not match on the name alone; humans can be called Claude.

## Steps
1. `gh auth status` must succeed. If `gh` is missing or not logged in, tell the user exactly what to run (`gh auth login`) and stop.
2. Repository facts:
   `gh api repos/$REPO --jq '{default_branch, private, admin: .permissions.admin}'`
3. Contributors as GitHub currently reports them:
   `gh api "repos/$REPO/contributors?per_page=100" --jq '.[] | "\(.login)\t\(.contributions)"'`
4. Co-author trailers in history. Use the existing clone if it is this repository, otherwise make a temporary bare clone (`git clone --bare --filter=blob:none https://github.com/$REPO tmp-check.git`). Then across all branches:
   `git log --all --format='%H%x09%(trailers:key=Co-authored-by,valueonly,separator=%x2C )' | awk -F'\t' '$2!=""'`
   Count the commits whose trailers match the target account, and list a few short hashes and the branches that contain them (`git branch -a --contains <hash>` for one or two).
5. Also check commit authors/committers for the target (`git log --all --format='%an <%ae>|%cn <%ce>' | sort | uniq -c`).
6. Remove any temporary clone you made.

## Report
A short verdict, then the facts:
- **Trailers or authorship still in history** → the account comes from history. Refreshing the cache alone will not keep it away. Next step: the `strip-coauthors` skill, then `refresh-contributors-cache`.
- **History is clean but the account is still listed** (in the API or on the web page) → stale cache. Next step: `refresh-contributors-cache`.
- **History is clean and the API no longer lists the account** → say so plainly. If the user reports the web page still shows it, that is still a stale cache: offer `refresh-contributors-cache`.

Do not suggest incognito windows, waiting, or changing Claude Code attribution settings: users reach this plugin after those did not help.
