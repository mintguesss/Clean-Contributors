---
name: strip-coauthors
description: Rewrite a repository's git history to remove Co-authored-by trailers for a given account (default Claude) and force-push the result. Destructive. Use only when the user wants those trailers removed from history, usually after check-contributors found them.
---

# Strip Co-authored-by trailers from history

This rewrites history: every affected commit gets a new hash, and the result must be force-pushed. Reply in the user's language.

## Before anything
1. Run the `check-contributors` checks if they have not been run in this session, so you know how many commits and which branches are affected. If none are affected, say so and stop.
2. Tools: `git`, `gh` (logged in, push access) and `git-filter-repo` (`pip install git-filter-repo`; on Windows also works via `py -m pip install git-filter-repo`). Install it if missing and the user agrees.
3. Collect what will be hit:
   - Open PRs: `gh api "repos/$REPO/pulls?state=open&per_page=100" --jq '.[] | "#\(.number) \(.head.ref)"'`
   - Branch protection on the branches you will push: `gh api repos/$REPO/branches/<b> --jq .protected`. A protected branch usually rejects force pushes; the user must allow it temporarily or the push will fail.
   - Forks: `gh api repos/$REPO --jq .forks_count`. Forks keep the old commits; this cannot be undone for them.

## Confirm (required, separately from any other step)
Show the user: repository, number of commits to rewrite, branches and tags affected, open PRs, protection, forks, and these consequences:
- all rewritten commits get new hashes; existing clones must re-clone or hard-reset;
- open PRs from rewritten branches may need to be recreated;
- signed commits lose their signatures;
- the old commits stay reachable on GitHub by hash until GitHub garbage-collects them.

Proceed only on an explicit yes for this step. Consent to refreshing the cache does not count.

## Rewrite
Work in a fresh mirror clone, never in the user's working copy:

```bash
git clone --mirror https://github.com/$REPO strip.git
cd strip.git
git bundle create ../backup-$(date +%Y%m%d%H%M%S).bundle --all   # full backup first
git filter-repo --force --message-callback '
import re
pat = re.compile(rb"^co-authored-by:[^\n]*(noreply@anthropic\.com|claude\[bot\])[^\n]*(\n|$)", re.I | re.M)
if not pat.search(message):
    return message
msg = pat.sub(b"", message)
return re.sub(rb"\n{3,}", b"\n\n", msg).rstrip(b"\n") + b"\n"
'
```

The pattern matches by e-mail (`noreply@anthropic.com`, `claude[bot]`), not by name, so a human co-author whose name contains "Claude" is kept; adjust it when the user targets another account. Messages without a match are returned unchanged, so commits that never had the trailer keep their message byte for byte. Then verify:
`git log --all --format=%B | grep -icE '^co-authored-by:.*(noreply@anthropic\.com|claude\[bot\])'` must be `0`, and the commit count must be unchanged (`git rev-list --all --count` before vs after).

`git filter-repo` removes the `origin` remote; add it back and push:
```bash
git remote add origin https://github.com/$REPO
git push --force --mirror origin
```
If `--mirror` is rejected because of `refs/pull/*` (read-only on GitHub), push branches and tags instead:
`git push --force origin 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'`.

## After
- Tell the user where the backup bundle is and that it restores the old history (`git clone backup-*.bundle`).
- Tell them how to update their own clones: `git fetch origin && git reset --hard origin/<branch>` (after saving local work).
- Then run `refresh-contributors-cache`; GitHub keeps showing the old list until the cache is refreshed.
- If the push was refused by a proxy or permission layer, do not retry through another route; report what was and was not pushed and give the exact commands for the user to run on their own machine.
