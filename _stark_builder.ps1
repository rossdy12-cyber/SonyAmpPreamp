param(
    [ValidateSet("push", "sync", "watch")]
    [string]$Mode = "push",
    [string]$CommitMessage = ""
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BuilderRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $BuilderRoot

$RepoUrl = "https://navidrome.nas-server.co.uk/sidestore/SonyAmpPreamp.git"
$ApiBase = "https://navidrome.nas-server.co.uk/sidestore-api"
$Token   = $env:SIDESTORE_UPLOAD_TOKEN
if (-not $Token) { throw "Set the SIDESTORE_UPLOAD_TOKEN environment variable first." }

$DropDir = Join-Path $BuilderRoot "Drop_App_Here"
$ZipArchiveDir = Join-Path $BuilderRoot "_Processed_Zips"
New-Item -ItemType Directory -Force -Path $DropDir | Out-Null
New-Item -ItemType Directory -Force -Path $ZipArchiveDir | Out-Null

function Write-Header($Title) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  STARK APP STORE // DESKTOP CODEMAGIC M2 IPA BUILDER" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-GitAvailable {
    $null -ne (Get-Command git -ErrorAction SilentlyContinue)
}

function Ensure-GitRepo {
    if (-not (Test-GitAvailable)) {
        Write-Host "[!] Git CLI not found on this PC - using direct HTTPS API mode." -ForegroundColor Yellow
        return $false
    }
    if (-not (Test-Path (Join-Path $BuilderRoot ".git"))) {
        Write-Host "[*] Initializing Git repository connected to TrueNAS ($RepoUrl)..." -ForegroundColor Cyan
        git init -b main | Out-Null
        git config core.autocrlf false
        git config user.name "Ross Dymond"
        git config user.email "ross.dymond@icloud.com"
        git remote add origin $RepoUrl 2>$null
        git fetch origin main
        git checkout -f -B main origin/main
    } else {
        git config core.autocrlf false
        $curUser = git config user.name
        if (-not $curUser) {
            git config user.name "Ross Dymond"
            git config user.email "ross.dymond@icloud.com"
        }
        $curBranch = (git rev-parse --abbrev-ref HEAD 2>$null)
        if ($curBranch -ne "main") {
            Write-Host "[*] Switching repository branch '$curBranch' -> 'main'..." -ForegroundColor Cyan
            git fetch origin main 2>$null
            $hasHead = (git rev-parse --verify HEAD 2>$null)
            if (-not $hasHead) {
                git checkout -f -B main origin/main
            } else {
                git branch -M main 2>$null
            }
        }
    }
    return $true
}

function Convert-ToUnixLineEndings([string]$FilePath) {
    if (Test-Path $FilePath) {
        $raw = [System.IO.File]::ReadAllText($FilePath)
        if ($raw.Contains("`r`n")) {
            $Unix = $raw.Replace("`r`n", "`n")
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($FilePath, $Unix, $utf8NoBom)
        }
    }
}

function Expand-DroppedItems {
    $touchedDirs = @()

    # 1. Process any .zip files in Drop_App_Here or BuilderRoot (excluding system zips)
    $zips = @()
    $zips += Get-ChildItem -Path $DropDir -Filter "*.zip" -File -ErrorAction SilentlyContinue
    $zips += Get-ChildItem -Path $BuilderRoot -Filter "*.zip" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "Stark_IPA_Builder_Kit.zip" }

    foreach ($z in $zips) {
        Write-Host "[*] Extracting dropped archive: $($z.Name)..." -ForegroundColor Cyan
        $tmpExtract = Join-Path $env:TEMP ("stark_unzip_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $tmpExtract | Out-Null
        Expand-Archive -Path $z.FullName -DestinationPath $tmpExtract -Force

        $topItems = Get-ChildItem -Path $tmpExtract | Where-Object { $_.Name -ne "__MACOSX" -and $_.Name -ne ".DS_Store" }
        if ($topItems.Count -eq 1 -and $topItems[0].PSIsContainer) {
            $appFolderName = $topItems[0].Name
            $srcFolder = $topItems[0].FullName
        } else {
            $appFolderName = [System.IO.Path]::GetFileNameWithoutExtension($z.Name) -replace "[^A-Za-z0-9_-]", ""
            $projFile = Join-Path $tmpExtract "project.yml"
            if (Test-Path $projFile) {
                $pContent = Get-Content $projFile -Raw
                if ($pContent -match "(?m)^name:\s*([A-Za-z0-9_-]+)") {
                    $appFolderName = $Matches[1]
                }
            }
            $srcFolder = $tmpExtract
        }

        $destFolder = Join-Path $BuilderRoot $appFolderName
        New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
        Copy-Item -Path (Join-Path $srcFolder "*") -Destination $destFolder -Recurse -Force
        Remove-Item -Path $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue

        $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        Move-Item -Path $z.FullName -Destination (Join-Path $ZipArchiveDir "${stamp}_$($z.Name)") -Force
        Write-Host "[+] Unpacked into folder: $appFolderName" -ForegroundColor Green
        $touchedDirs += $appFolderName
    }

    # 2. Process any folders dropped into Drop_App_Here
    $droppedDirs = Get-ChildItem -Path $DropDir -Directory -ErrorAction SilentlyContinue
    foreach ($d in $droppedDirs) {
        $destFolder = Join-Path $BuilderRoot $d.Name
        Write-Host "[*] Importing dropped app folder: $($d.Name)..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
        Copy-Item -Path (Join-Path $d.FullName "*") -Destination $destFolder -Recurse -Force
        Remove-Item -Path $d.FullName -Recurse -Force
        Write-Host "[+] Imported folder: $($d.Name)" -ForegroundColor Green
        $touchedDirs += $d.Name
    }

    return ($touchedDirs | Select-Object -Unique)
}

function Ensure-AppBuildAndCodemagic {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $cmPath = Join-Path $BuilderRoot "codemagic.yaml"
    $cmContent = if (Test-Path $cmPath) { [System.IO.File]::ReadAllText($cmPath).Replace("`r`n", "`n") } else { "workflows:`n" }
    $cmModified = $false

    $subDirs = Get-ChildItem -Path $BuilderRoot -Directory | Where-Object {
        $_.Name -notin @(".git", ".github", "Drop_App_Here", "_Processed_Zips", "Sources")
    }

    foreach ($dir in $subDirs) {
        $dirName = $dir.Name
        $projYml = Join-Path $dir.FullName "project.yml"
        $buildSh1 = Join-Path $dir.FullName "build-and-publish.sh"
        $buildSh2 = Join-Path $dir.FullName "ci\build-and-publish.sh"

        # Ensure any existing .sh script has LF line endings
        Get-ChildItem -Path $dir.FullName -Filter "*.sh" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            Convert-ToUnixLineEndings $_.FullName
        }

        if ((Test-Path $projYml) -and -not (Test-Path $buildSh1) -and -not (Test-Path $buildSh2)) {
            $pText = [System.IO.File]::ReadAllText($projYml)
            $appName = $dirName
            if ($pText -match "(?m)^name:\s*([^\r\n#]+)") { $appName = $Matches[1].Trim().Trim('"').Trim("'") }
            $bundleId = "com.ross.$($dirName.ToLower())"
            if ($pText -match "(?m)PRODUCT_BUNDLE_IDENTIFIER:\s*([^\r\n#]+)") { $bundleId = $Matches[1].Trim().Trim('"').Trim("'") }
            $version = "1.0.0"
            if ($pText -match "(?m)MARKETING_VERSION:\s*([^\r\n#]+)") { $version = $Matches[1].Trim().Trim('"').Trim("'") }

            Write-Host "[*] Auto-generating build-and-publish.sh for $appName ($bundleId v$version)..." -ForegroundColor Cyan
            $shScript = @"
#!/usr/bin/env bash
set -uo pipefail

STORE_URL="https://navidrome.nas-server.co.uk"
TOKEN="`${SIDESTORE_UPLOAD_TOKEN:?set SIDESTORE_UPLOAD_TOKEN}"
VERSION="$version"
BUNDLE_ID="$bundleId"
APP_NAME="$appName"

cd "`$(dirname "`$0")"
LOG="/tmp/$($dirName.ToLower())_build.log"

set +e
(
  set -e
  command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
  xcodegen generate
  xcodebuild \
    -project "`${APP_NAME}.xcodeproj" \
    -target "`${APP_NAME}" \
    -configuration Release \
    -sdk iphoneos \
    SYMROOT="`$PWD/build" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    build
  rm -rf out && mkdir -p out/Payload
  cp -R "build/Release-iphoneos/`${APP_NAME}.app" out/Payload/
  ( cd out && zip -qry "`${APP_NAME}.ipa" Payload )
) > "`$LOG" 2>&1
BUILD_STATUS=`$?

tail -c 5000 "`$LOG" || true
{ echo "----- context (last 25 lines) -----"; tail -n 25 "`$LOG"; echo; echo "===== SWIFT ERRORS ====="; grep -E "error:" "`$LOG" | tail -n 50; echo "===== END ERRORS ====="; } > /tmp/cm_tail.log 2>/dev/null
curl -fsSL -X POST -H "X-Upload-Token: `$TOKEN" --data-binary @/tmp/cm_tail.log \
  "`$STORE_URL/sidestore-api/upload?buildLog=1" || true

if [ "`$BUILD_STATUS" -ne 0 ]; then
  echo "BUILD FAILED (`$BUILD_STATUS)"
  exit "`$BUILD_STATUS"
fi

echo "=== Upload to TrueNAS for 365-day signing ==="
curl -fsSL -X POST \
  -H "X-Upload-Token: `$TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"out/`${APP_NAME}.ipa" \
  "`$STORE_URL/sidestore-api/upload?bundleId=`${BUNDLE_ID}&version=`${VERSION}&name=`${APP_NAME}" \
  | tee out/publish.json
echo
curl -fsSL "`$STORE_URL/sidestore-api/verify-ipa?bundleId=`${BUNDLE_ID}" || true
echo
"@
            $shScript = $shScript.Replace("`r`n", "`n")
            [System.IO.File]::WriteAllText($buildSh1, $shScript, $utf8NoBom)
        }

        $relSh = $null
        if (Test-Path $buildSh1) { $relSh = "$dirName/build-and-publish.sh" }
        elseif (Test-Path $buildSh2) { $relSh = "$dirName/ci/build-and-publish.sh" }

        if ($relSh -and ($cmContent -notmatch [regex]::Escape("'$dirName/**'"))) {
            $wfSlug = ($dirName.ToLower() -replace "[^a-z0-9-]", "-") + "-unsigned-ipa"
            Write-Host "[*] Adding Codemagic M2 workflow '$wfSlug' for folder '$dirName/'..." -ForegroundColor Cyan
            $wfBlock = @"
  ${wfSlug}:
    name: ${dirName} iOS Unsigned IPA
    instance_type: mac_mini_m2
    max_build_duration: 30
    environment:
      xcode: latest
    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true
          source: true
    when:
      changeset:
        includes:
          - '${dirName}/**'
    scripts:
      - name: Build unsigned ${dirName} IPA on M2 and publish through TrueNAS
        script: |
          bash ${relSh}
"@
            $wfBlock = $wfBlock.Replace("`r`n", "`n")
            if (-not $cmContent.EndsWith("`n")) { $cmContent += "`n" }
            $cmContent += $wfBlock
            $cmModified = $true
        }
    }

    if ($cmModified) {
        [System.IO.File]::WriteAllText($cmPath, $cmContent, $utf8NoBom)
        Write-Host "[+] Updated codemagic.yaml with new app workflow(s)." -ForegroundColor Green
    } else {
        Convert-ToUnixLineEndings $cmPath
    }
}

function Invoke-PushAndBuild([string]$CustomMsg = "", [switch]$NonInteractive) {
    $hasGit = Ensure-GitRepo
    $imported = Expand-DroppedItems
    Ensure-AppBuildAndCodemagic

    if ($hasGit) {
        git add -A
        $statusLines = git status --porcelain
        git fetch origin main 2>$null
        $unpushedCount = 0
        try {
            $unpushedCount = [int](git rev-list --count origin/main..HEAD 2>$null)
        } catch {
            $unpushedCount = 0
        }

        if (-not $statusLines -and $unpushedCount -le 0) {
            Write-Host "[*] No file changes detected in working tree." -ForegroundColor Yellow
            if (-not $NonInteractive) {
                $ans = Read-Host "Which app folder do you want to force-rebuild on Codemagic? (e.g. nocturne, prism, CarbPrep, or press Enter to cancel)"
                if ([string]::IsNullOrWhiteSpace($ans)) {
                    return
                }
                $targetDir = Join-Path $BuilderRoot $ans.Trim()
                if (Test-Path $targetDir) {
                    $stampFile = Join-Path $targetDir ".build-trigger"
                    "Triggered at $((Get-Date).ToUniversalTime().ToString('o'))" | Set-Content -Path $stampFile -Encoding UTF8
                    git add -A
                    $CustomMsg = "Rebuild $($ans.Trim()) on Codemagic M2"
                    $statusLines = git status --porcelain
                } else {
                    Write-Host "[!] Folder '$ans' not found in $BuilderRoot" -ForegroundColor Red
                    return
                }
            } else {
                return
            }
        }

        if ($statusLines) {
            if ([string]::IsNullOrWhiteSpace($CustomMsg)) {
                if ($imported -and $imported.Count -gt 0) {
                    $CustomMsg = "Build & publish $($imported -join ', ') via Stark Desktop Builder"
                } else {
                    $CustomMsg = "Build & publish via Stark Desktop Builder ($((Get-Date).ToString('yyyy-MM-dd HH:mm')))"
                }
            }

            Write-Host "[*] Committing changes: $CustomMsg" -ForegroundColor Cyan
            git commit -m $CustomMsg
        } else {
            Write-Host "[*] Found $unpushedCount unpushed commit(s) ready to push..." -ForegroundColor Cyan
        }

        git branch -M main 2>$null
        Write-Host "[*] Syncing latest remote history from TrueNAS..." -ForegroundColor Cyan
        git pull --rebase -X ours origin main

        Write-Host "[*] Pushing to TrueNAS Git (HEAD:main) & firing Codemagic M2 webhook..." -ForegroundColor Cyan
        git push origin HEAD:main
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "[+] SUCCESS! Pushed to TrueNAS Git (main) and triggered Codemagic M2 build!" -ForegroundColor Green
            Write-Host "    Store Page : https://navidrome.nas-server.co.uk/sidestore/" -ForegroundColor Cyan
            Write-Host "    Build Log  : https://navidrome.nas-server.co.uk/sidestore-api/ops" -ForegroundColor Cyan
        } else {
            Write-Host "[!] git push returned exit code $LASTEXITCODE" -ForegroundColor Red
        }
    } else {
        # Fallback when Git is not installed on the PC: upload via /sidestore-api/git-commit
        $targetFolder = if ($imported -and $imported.Count -gt 0) { $imported[0] } else { Read-Host "Enter app folder name to upload (e.g. nocturne)" }
        if ([string]::IsNullOrWhiteSpace($targetFolder)) { return }
        $fullTarget = Join-Path $BuilderRoot $targetFolder
        if (-not (Test-Path $fullTarget)) {
            Write-Host "[!] Folder not found: $fullTarget" -ForegroundColor Red
            return
        }
        Write-Host "[*] Packaging files in '$targetFolder' for direct HTTPS API commit..." -ForegroundColor Cyan
        $filesB64 = @{}
        Get-ChildItem -Path $fullTarget -Recurse -File | Where-Object { $_.FullName -notmatch "\\(build|out|\.git)\\" } | ForEach-Object {
            $rel = $_.FullName.Substring($BuilderRoot.Length + 1).Replace("\", "/")
            $filesB64[$rel] = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_.FullName))
        }
        $cmPath = Join-Path $BuilderRoot "codemagic.yaml"
        if (Test-Path $cmPath) {
            $filesB64["codemagic.yaml"] = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($cmPath))
        }
        $payload = @{
            message = "Build & publish $targetFolder via Stark Desktop Builder API"
            filesBase64 = $filesB64
            triggerCodemagic = $true
        } | ConvertTo-Json -Depth 6 -Compress

        $resp = Invoke-RestMethod -Uri "$ApiBase/git-commit?token=$Token" -Method Post -ContentType "application/json" -Body $payload
        Write-Host "[+] Server response: $($resp | ConvertTo-Json -Compress)" -ForegroundColor Green
    }
}

if ($Mode -eq "sync") {
    Write-Header "SYNC LATEST APPS & SOURCE FROM TRUENAS"
    if (Ensure-GitRepo) {
        git fetch origin main
        git checkout -f -B main origin/main
        git reset --hard origin/main
        Write-Host "[+] Desktop folder is up to date with TrueNAS (branch: main)!" -ForegroundColor Green
    }
} elseif ($Mode -eq "push") {
    Write-Header "ONE-CLICK GIT PUSH -> CODEMAGIC M2 -> 365-DAY SIGNED IPA"
    Invoke-PushAndBuild -CustomMsg $CommitMessage
} elseif ($Mode -eq "watch") {
    Write-Header "LIVE AUTO-WATCHER (DROP ZIP OR APP FOLDER INTO 'Drop_App_Here')"
    Write-Host "[*] Watching folder: $DropDir" -ForegroundColor Green
    Write-Host "    Any .zip or app folder dropped into 'Drop_App_Here' will automatically"
    Write-Host "    unpack, wire codemagic.yaml, git push to TrueNAS, and build on Codemagic M2!"
    Write-Host "    (Press Ctrl+C to stop watching)"
    Write-Host ""
    while ($true) {
        $items = Get-ChildItem -Path $DropDir -ErrorAction SilentlyContinue
        if ($items -and $items.Count -gt 0) {
            Start-Sleep -Seconds 2
            Write-Host "[*] Detected new files in Drop_App_Here! Starting auto-push..." -ForegroundColor Cyan
            Invoke-PushAndBuild -NonInteractive
            Write-Host "[*] Resuming watch on $DropDir..." -ForegroundColor Green
        }
        Start-Sleep -Seconds 3
    }
}
