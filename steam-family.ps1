# Steam Family Search: runs steam-family-search.user.js on Store pages of the Steam desktop app.
# Uses Steam's own Chromium DevTools (-cef-enable-debugging, 127.0.0.1:8080).
# If Steam runs without it, Steam is restarted with the flag (never while a game is running).
# Exits by itself when Steam closes. Windows PowerShell 5.1, nothing to install, nothing changed on disk.

$ErrorActionPreference = 'Stop'
$DevTools = 'http://127.0.0.1:8080/json'
$ScriptPath = Join-Path $PSScriptRoot 'steam-family-search.user.js'
$Store = '^https://store\.steampowered\.com/'          # attach to every store tab...
$Search = '^https://store\.steampowered\.com/search'   # ...the script itself only acts on search
$GoneLimit = 15                                        # ~15s without DevTools -> Steam closed, exit

# Single instance: a second copy just exits.
$mutex = New-Object Threading.Mutex($false, 'Local\steam-family-search')
if (-not $mutex.WaitOne(0)) { Write-Host 'Already running.'; exit 0 }

# Plain string: Get-Content would add properties that ConvertTo-Json turns into an object.
function Read-UserScript { [IO.File]::ReadAllText($ScriptPath, [Text.Encoding]::UTF8) }

function Get-Targets {
  try { return @(Invoke-RestMethod $DevTools -TimeoutSec 2) } catch { return $null }
}

function Get-SteamReg($name) { (Get-ItemProperty 'HKCU:\Software\Valve\Steam').$name }
function Test-SteamRunning { [bool](Get-Process steam -ErrorAction SilentlyContinue) }

function Start-SteamWithDebugging {
  if (Get-Targets) { return $true }
  $exe = (Get-SteamReg 'SteamExe') -replace '/', '\'

  if (Test-SteamRunning) {
    if (Get-SteamReg 'RunningAppID') { Write-Host 'A game is running - not restarting Steam.'; return $false }
    Write-Host 'Steam is running without DevTools - restarting it...'
    Start-Process $exe '-shutdown'
    for ($i = 0; $i -lt 60 -and (Test-SteamRunning); $i++) { Start-Sleep 1 }
    if (Test-SteamRunning) { Write-Host 'Steam did not close in 60s.'; return $false }
  }

  Write-Host 'Starting Steam with -cef-enable-debugging...'
  Start-Process $exe '-cef-enable-debugging'
  for ($i = 0; $i -lt 120; $i++) {
    if (Get-Targets) { return $true }
    Start-Sleep 1
  }
  Write-Host 'Steam DevTools did not come up in 2 minutes.'
  return $false
}

# --- Minimal DevTools client ---

$none = [Threading.CancellationToken]::None
$script:msgId = 0

function Send-Cdp($conn, $method, $params) {
  $script:msgId++
  $json = @{ id = $script:msgId; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 5
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $conn.Ws.SendAsync([ArraySegment[byte]]::new($bytes), 'Text', $true, $none).Wait()
}

# Replies are not needed, but must be read so they don't pile up.
function Clear-Replies($conn) {
  while ($conn.Recv.IsCompleted) {
    if ($conn.Recv.IsFaulted -or $conn.Ws.State -ne 'Open') { return $false }
    $conn.Recv = $conn.Ws.ReceiveAsync([ArraySegment[byte]]::new($conn.Buf), $none)
  }
  return $true
}

function Connect-Target($target) {
  $ws = New-Object Net.WebSockets.ClientWebSocket
  if (-not $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $none).Wait(3000)) { return $null }
  $buf = New-Object byte[] 65536
  $conn = @{ Ws = $ws; Buf = $buf; Recv = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $none) }
  $source = Read-UserScript
  # Chromium runs it on every page this tab loads, right at load - no waiting for the next poll.
  Send-Cdp $conn 'Page.enable' @{}
  Send-Cdp $conn 'Page.addScriptToEvaluateOnNewDocument' @{ source = $source }
  Send-Cdp $conn 'Runtime.evaluate' @{ expression = $source }  # the page that is already open
  Write-Host "attached: $($target.url)"
  return $conn
}

if (-not (Start-SteamWithDebugging)) { exit 1 }
Write-Host 'Ready. Open Store -> Search in Steam.'

$conns = @{}   # targetId -> connection
$gone = 0
while ($true) {
  Start-Sleep 1
  $targets = Get-Targets
  if (-not $targets) {
    if (++$gone -ge $GoneLimit) { Write-Host 'Steam closed - exiting.'; break }
    continue
  }
  $gone = 0

  foreach ($id in @($conns.Keys)) {
    try { $alive = Clear-Replies $conns[$id] } catch { $alive = $false }
    if (-not $alive) { $conns[$id].Ws.Dispose(); $conns.Remove($id) }
  }

  foreach ($t in $targets) {
    if (-not $t.webSocketDebuggerUrl -or $t.url -notmatch $Store) { continue }
    try {
      if (-not $conns.ContainsKey($t.id)) {
        $conn = Connect-Target $t
        if ($conn) { $conns[$t.id] = $conn }
      } elseif ($t.url -match $Search) {
        # Safety net for anything the new-document hook missed; the script guards itself (window.__sfsLoaded).
        Send-Cdp $conns[$t.id] 'Runtime.evaluate' @{ expression = (Read-UserScript) }
      }
    } catch { Write-Host "error: $($_.Exception.Message)" }
  }
}
