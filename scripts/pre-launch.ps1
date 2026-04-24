param(
  # Host the pack's `pack.toml` somewhere stable (GitHub raw URL, Modrinth, etc.)
  # The bootstrap reads it and downloads / updates mods into $INST_MC_DIR\mods.
  [string]$PackUrl = "https://raw.githubusercontent.com/fractaal/councilcraft-season2/main/pack.toml",
  [string]$InstanceDir = "",
  [string]$InstJava    = ""
)

# Prism injects $INST_DIR, $INST_MC_DIR, $INST_JAVA as env vars; use those if params weren't passed.
if (-not $InstanceDir) { $InstanceDir = $env:INST_DIR }
if (-not $InstJava)    { $InstJava    = $env:INST_JAVA }
if (-not $InstanceDir) { $InstanceDir = "$PSScriptRoot\.." }
$McDir = Join-Path $InstanceDir "minecraft"
$Bootstrap = Join-Path $PSScriptRoot "packwiz-installer-bootstrap.jar"

# PS 5.1 ('Desktop' edition) lacks $IsWindows — but it's always Windows. PS Core 6+ provides it.
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

# ==========================================================================
# Splash (lifted verbatim from the original pull-before-launch.ps1 — same vibe)
# ==========================================================================
$script:LogoText = "xXxCouncilCraftxXx"

function Show-Notification {
  param(
    [string]$StatusMessage,
    [string]$StatusColor = "Green"
  )
  # WinForms + child powershell.exe aren't available off Windows; fall back to stdout.
  if (-not $OnWindows) {
    Write-Host "[$StatusColor] $StatusMessage"
    return
  }
  $escapedMessage = $StatusMessage -replace "'", "''"
  $logoText = $script:LogoText
  $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
  $code = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

`$form = New-Object System.Windows.Forms.Form
`$form.Text = 'CouncilCraft Mods Sync'
`$form.Size = New-Object System.Drawing.Size(700,400)
`$form.StartPosition = 'CenterScreen'
`$form.FormBorderStyle = 'FixedDialog'
`$form.MaximizeBox = `$false
`$form.MinimizeBox = `$false
`$form.TopMost = `$true
`$form.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)

`$logoBox = New-Object System.Windows.Forms.RichTextBox
`$logoBox.Location = New-Object System.Drawing.Point(40,30)
`$logoBox.Size = New-Object System.Drawing.Size(620,100)
`$logoBox.Text = '$logoText'
`$logoBox.Font = New-Object System.Drawing.Font('Segoe UI',44,[System.Drawing.FontStyle]::Bold)
`$logoBox.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
`$logoBox.BorderStyle = 'None'
`$logoBox.ReadOnly = `$true
`$logoBox.TabStop = `$false
`$logoBox.Cursor = [System.Windows.Forms.Cursors]::Arrow
`$logoBox.SelectionAlignment = 'Center'
`$form.Controls.Add(`$logoBox)

`$statusLabel = New-Object System.Windows.Forms.Label
`$statusLabel.Location = New-Object System.Drawing.Point(20,145)
`$statusLabel.Size = New-Object System.Drawing.Size(660,220)
`$statusLabel.Text = '$escapedMessage'
`$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
`$statusLabel.TextAlign = 'TopCenter'

switch ('$StatusColor') {
  'Green'  { `$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 255, 100) }
  'Red'    { `$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100) }
  'Orange' { `$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 100) }
  'Blue'   { `$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255) }
  default  { `$statusLabel.ForeColor = [System.Drawing.Color]::White }
}
`$form.Controls.Add(`$statusLabel)

`$hueOffset = 0
`$rgbTimer = New-Object System.Windows.Forms.Timer
`$rgbTimer.Interval = 50
`$rgbTimer.Add_Tick({
  `$script:hueOffset = (`$script:hueOffset + 5) % 360
  `$text = `$logoBox.Text
  `$charSpacing = 360.0 / `$text.Length
  for (`$i = 0; `$i -lt `$text.Length; `$i++) {
    `$charHue = (`$script:hueOffset + (`$i * `$charSpacing)) % 360
    `$h = `$charHue / 60.0
    `$x = (1 - [Math]::Abs((`$h % 2) - 1)) * 255
    if (`$h -lt 1) { `$r=255; `$g=[int]`$x; `$b=0 }
    elseif (`$h -lt 2) { `$r=[int]`$x; `$g=255; `$b=0 }
    elseif (`$h -lt 3) { `$r=0; `$g=255; `$b=[int]`$x }
    elseif (`$h -lt 4) { `$r=0; `$g=[int]`$x; `$b=255 }
    elseif (`$h -lt 5) { `$r=[int]`$x; `$g=0; `$b=255 }
    else { `$r=255; `$g=0; `$b=[int]`$x }
    `$logoBox.Select(`$i, 1)
    `$logoBox.SelectionColor = [System.Drawing.Color]::FromArgb(`$r, `$g, `$b)
  }
  `$logoBox.Select(0, 0)
})
`$rgbTimer.Start()

`$closeTimer = New-Object System.Windows.Forms.Timer
`$closeTimer.Interval = 4000
`$closeTimer.Add_Tick({ `$form.Close(); `$closeTimer.Stop(); `$rgbTimer.Stop() })
`$closeTimer.Start()

`$form.Add_Shown({`$form.Activate()})
[void]`$form.ShowDialog()
"@
  Set-Content -Path $tempScript -Value $code -Encoding UTF8
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tempScript`""
  $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
  $psi.CreateNoWindow = $true
  [System.Diagnostics.Process]::Start($psi) | Out-Null
  Start-Job -ScriptBlock { Start-Sleep -Seconds 10; Remove-Item $args[0] -ErrorAction SilentlyContinue } -ArgumentList $tempScript | Out-Null
}

# ==========================================================================
# Sync via packwiz-installer-bootstrap (replaces the git pull)
# ==========================================================================

# Resolve a Java: prefer the one Prism passes in, else try JAVA_HOME, else `java` on PATH.
if (-not $InstJava -or -not (Test-Path $InstJava)) {
  $javaBin = if ($OnWindows) { "bin\java.exe" } else { "bin/java" }
  if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME $javaBin))) {
    $InstJava = Join-Path $env:JAVA_HOME $javaBin
  } elseif (Get-Command java -ErrorAction SilentlyContinue) {
    $InstJava = (Get-Command java).Path
  } else {
    Show-Notification -StatusMessage "No Java found.`nCan't sync mods.`nLaunching anyway..." -StatusColor "Red"
    exit 0
  }
}

if (-not (Test-Path $Bootstrap)) {
  Show-Notification -StatusMessage "packwiz bootstrap jar missing.`nReinstall the pack.`nLaunching anyway..." -StatusColor "Red"
  exit 0
}

Write-Host "[SYNC] Running packwiz bootstrap against $PackUrl"
Push-Location $McDir
$output = & "$InstJava" -jar "$Bootstrap" -g "$PackUrl" 2>&1 | Out-String
$exit = $LASTEXITCODE
Pop-Location
Write-Host $output

# Parse bootstrap output. Real mod-sync lines look like:
#   (176/180) Downloaded Chunky
#   (177/180) Downloaded Observable
#   (112/180) Skipped Noisium (wrong side)     <-- deliberate, not an error
#   Finished successfully!
# The "Already up to date!" from the bootstrap self-update check is NOT a mod-sync signal.
$changed = @()
$finishedOk = $false
foreach ($line in ($output -split "`r?`n")) {
  if ($line -match "^\s*\(\d+/\d+\)\s+Downloaded\s+(.+?)\s*$") {
    # Ignore .pw.toml and script-file entries — only user-visible changes
    $name = $Matches[1]
    if ($name -notmatch "\.pw\.toml$" -and $name -notmatch "\.ps1$" -and $name -notmatch "\.jar$|bootstrap") {
      $changed += $name
    }
  }
  elseif ($line -match "^\s*Finished successfully!") { $finishedOk = $true }
}

if ($exit -ne 0 -and -not $finishedOk) {
  Show-Notification -StatusMessage "Sync failed (exit $exit).`nLaunching with existing mods..." -StatusColor "Red"
} elseif ($changed.Count -eq 0) {
  Show-Notification -StatusMessage "I'm up to date!`nReady to launch." -StatusColor "Green"
} else {
  $preview = $changed | Select-Object -First 3
  $more = if ($changed.Count -gt 3) { "`n(+ $($changed.Count - 3) more...)" } else { "" }
  $msg = "New updates!`n`n$($preview -join "`n")$more`n`nReady to launch."
  Show-Notification -StatusMessage $msg -StatusColor "Blue"
}

Write-Host "[SYNC] Done. Ready to launch."
