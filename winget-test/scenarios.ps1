# Checks how winget treats a package manifest that offers both an MSI (wix)
# and a portable zip, on a clean runner:
#   validate  winget validate on the generated manifest
#   A         fresh install with defaults: which installer does winget pick?
#   B         fresh install with --installer-type portable: is the zip still reachable?
#   C         an existing user: install the previous version from the winget
#             source (portable), then winget upgrade to the local manifest
# Each scenario starts and ends with the package removed. Results go to the
# log and to the job summary.
param(
    [Parameter(Mandatory)] [string] $Id,
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $Manifest,
    [Parameter(Mandatory)] [string] $Previous
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$common = @('--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
$link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\$Exe"
$summary = [System.Collections.Generic.List[string]]::new()

function Note([string] $line) { Write-Host $line; $summary.Add($line) }

function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Get-State {
    Update-Path
    $l = Get-Item $link -Force -ErrorAction SilentlyContinue
    $arp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -match [regex]::Escape(($Exe -replace '\.exe$')) } |
        ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion) [$($_.PSChildName)]$(if ($_.WindowsInstaller -eq 1) { ' msi' })" }
    $where = (where.exe $Exe 2>$null) -join ', '
    $first = (where.exe $Exe 2>$null | Select-Object -First 1)
    $ver = if ($first) { (& $first --version 2>&1) -join ' ' } else { 'not on PATH' }
    [pscustomobject]@{
        Link    = if ($l) { "$($l.LinkType) -> $($l.Target)" } else { 'none' }
        Arp     = if ($arp) { $arp -join '; ' } else { 'none' }
        Where   = if ($where) { $where } else { 'none' }
        Runs    = $ver
    }
}

function Show-State([string] $label) {
    $s = Get-State
    Note "  $label"
    Note "    WinGet link:   $($s.Link)"
    Note "    Apps entries:  $($s.Arp)"
    Note "    where.exe:     $($s.Where)"
    Note "    first on PATH: $($s.Runs)"
    Write-Host '    winget list:'
    winget list --id $Id --exact --disable-interactivity 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "      $_" }
}

function Invoke-Winget([string] $what, [string[]] $wargs) {
    Write-Host "  > winget $($wargs -join ' ')"
    $out = winget @wargs 2>&1 | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*[-\\|/]\s*$' -and $_ -notmatch '█|▒' }
    $code = $LASTEXITCODE
    $out | ForEach-Object { Write-Host "    $_" }
    $chosen = ($out | Select-String -Pattern 'Found .*|Starting package install|Successfully installed|Installer hash|No applicable|No available upgrade|failed|error' | ForEach-Object { $_.Line.Trim() }) -join ' | '
    Note "  $what -> exit $code; $chosen"
}

function Remove-All {
    for ($i = 0; $i -lt 3; $i++) {
        $listed = winget list --id $Id --exact --disable-interactivity 2>&1 | Select-String -SimpleMatch $Id
        if (-not $listed) { break }
        winget uninstall --id $Id --exact --all-versions --disable-interactivity --force 2>&1 | Out-Null
    }
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.WindowsInstaller -eq 1 -and $_.DisplayName -match [regex]::Escape(($Exe -replace '\.exe$')) } |
        ForEach-Object { Start-Process msiexec.exe -ArgumentList '/x', $_.PSChildName, '/qn' -Wait }
    $s = Get-State
    if ($s.Link -ne 'none' -or $s.Arp -ne 'none') { Note "  WARNING: cleanup left: link $($s.Link); apps $($s.Arp)" }
}

$arch = $env:PROCESSOR_ARCHITECTURE
Note "## $Id on $arch ($((Get-CimInstance Win32_OperatingSystem).Caption))"
Note "winget $(winget --version)"
Note ''

Note '### validate'
winget validate --manifest $Manifest 2>&1 | ForEach-Object { Note "  $_" }
Note ''

Note '### A. fresh install, defaults'
Remove-All
Invoke-Winget 'install' (@('install', '--manifest', $Manifest) + $common)
Show-State 'after install'
Remove-All
Note ''

Note '### B. fresh install, --installer-type portable'
Invoke-Winget 'install' (@('install', '--manifest', $Manifest, '--installer-type', 'portable') + $common)
Show-State 'after install'
Remove-All
Note ''

Note "### C. existing user: $Previous from the winget source, then upgrade to the local manifest"
Invoke-Winget "install $Previous" (@('install', '--id', $Id, '--exact', '--version', $Previous, '--source', 'winget') + $common)
Show-State "after installing $Previous"
Invoke-Winget 'upgrade' (@('upgrade', '--manifest', $Manifest) + $common)
Show-State 'after upgrade'
Remove-All
Note ''

if ($env:GITHUB_STEP_SUMMARY) {
    @('```') + $summary + @('```') | Add-Content $env:GITHUB_STEP_SUMMARY
}
