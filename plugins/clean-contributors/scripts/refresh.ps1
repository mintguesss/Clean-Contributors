<#
.SYNOPSIS
  Force GitHub to recompute a repository's Contributors list.

.DESCRIPTION
  Creates a temporary branch, makes it the default branch, renames the real
  default branch away and back, restores it as the default and deletes the
  temporary branch. Everything goes through the GitHub REST API via gh, so no
  local clone is needed. Requires gh (logged in) and admin on the repository.

.EXAMPLE
  .\refresh.ps1 mintguesss/my-repo
  .\refresh.ps1 mintguesss/my-repo -Yes
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
  [string]$Repo,
  [switch]$Yes
)

# Continue: Windows PowerShell 5.1 turns native stderr into terminating errors under 'Stop'.
# Failures are detected through $LASTEXITCODE in Invoke-Gh instead.
$ErrorActionPreference = 'Continue'
$Tmp = 'tmp-refresh-contributors'

function Fail([string]$msg) { Write-Host "Error: $msg" -ForegroundColor Red; exit 1 }

# Run gh and throw on a non-zero exit code.
function Invoke-Gh {
  $out = & gh @args 2>&1
  if ($LASTEXITCODE -ne 0) { throw "gh $($args -join ' ') failed: $out" }
  return $out
}

# Retry a script block a few times (GitHub applies renames asynchronously).
function Retry([scriptblock]$Block) {
  for ($i = 1; $i -le 5; $i++) {
    try { return & $Block } catch { if ($i -eq 5) { throw }; Start-Sleep -Seconds 2 }
  }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Fail 'gh is not installed: winget install --id GitHub.cli (then reopen PowerShell)'
}
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { Fail 'gh is not logged in. Run: gh auth login' }

try { $Def = Invoke-Gh api "repos/$Repo" --jq .default_branch } catch { Fail "cannot read $Repo" }
$Admin = Invoke-Gh api "repos/$Repo" --jq .permissions.admin
if ($Admin -ne 'true') { Fail "you need admin permission on $Repo" }
$Old = "$Def-old-refresh"

foreach ($b in @($Tmp, $Old)) {
  & gh api "repos/$Repo/branches/$b" *> $null
  if ($LASTEXITCODE -eq 0) { Fail "branch '$b' already exists on $Repo; delete it first" }
}

$Sha = Invoke-Gh api "repos/$Repo/git/ref/heads/$Def" --jq .object.sha
$Protected = Invoke-Gh api "repos/$Repo/branches/$Def" --jq .protected
$OpenPrs = Invoke-Gh api "repos/$Repo/pulls?state=open&per_page=100" --jq length

Write-Host "Repository:      $Repo"
Write-Host "Default branch:  $Def ($Sha)"
Write-Host "Protected:       $Protected"
Write-Host "Open PRs:        $OpenPrs"
Write-Host ''
Write-Host "Steps: create '$Tmp' -> make it default -> rename '$Def' to '$Old' and back"
Write-Host "       -> make '$Def' default again -> delete '$Tmp'"
if (-not $Yes) {
  $ans = Read-Host 'Proceed? [y/N]'
  if ($ans -notmatch '^[Yy]$') { Write-Host 'Aborted.'; exit 1 }
}

$createdTmp = $false; $switched = $false; $renamedAway = $false
try {
  Write-Host "1/5 Creating $Tmp"
  Invoke-Gh api -X POST "repos/$Repo/git/refs" -f "ref=refs/heads/$Tmp" -f "sha=$Sha" --silent | Out-Null
  $createdTmp = $true

  Write-Host "2/5 Setting default branch to $Tmp"
  Retry { Invoke-Gh api -X PATCH "repos/$Repo" -f "default_branch=$Tmp" --silent } | Out-Null
  $switched = $true

  Write-Host "3/5 Renaming $Def -> $Old -> $Def"
  Retry { Invoke-Gh api -X POST "repos/$Repo/branches/$Def/rename" -f "new_name=$Old" --silent } | Out-Null
  $renamedAway = $true
  Retry { Invoke-Gh api -X POST "repos/$Repo/branches/$Old/rename" -f "new_name=$Def" --silent } | Out-Null
  $renamedAway = $false

  Write-Host "4/5 Setting default branch back to $Def"
  Retry { Invoke-Gh api -X PATCH "repos/$Repo" -f "default_branch=$Def" --silent } | Out-Null
  $switched = $false

  Write-Host "5/5 Deleting $Tmp"
  Retry { Invoke-Gh api -X DELETE "repos/$Repo/git/refs/heads/$Tmp" --silent } | Out-Null
  $createdTmp = $false
}
catch {
  Write-Host ''
  Write-Host "Something failed: $_" -ForegroundColor Red
  Write-Host 'Rolling back...' -ForegroundColor Yellow
  if ($renamedAway) {
    try { Retry { Invoke-Gh api -X POST "repos/$Repo/branches/$Old/rename" -f "new_name=$Def" --silent } | Out-Null }
    catch { Write-Host "  ! could not rename '$Old' back to '$Def' - do it in Settings > Branches" }
  }
  if ($switched) {
    try { Retry { Invoke-Gh api -X PATCH "repos/$Repo" -f "default_branch=$Def" --silent } | Out-Null }
    catch { Write-Host "  ! could not set default branch back to '$Def' - do it in Settings > General" }
  }
  if ($createdTmp) {
    try { Retry { Invoke-Gh api -X DELETE "repos/$Repo/git/refs/heads/$Tmp" --silent } | Out-Null }
    catch { Write-Host "  ! could not delete '$Tmp' - delete it in the Branches page" }
  }
  exit 1
}

Write-Host ''
Write-Host "Done. Default branch: $(Invoke-Gh api "repos/$Repo" --jq .default_branch)"
Write-Host 'Contributors (API):'
Invoke-Gh api "repos/$Repo/contributors?per_page=100" --jq '.[].login' | ForEach-Object { "  $_" }
