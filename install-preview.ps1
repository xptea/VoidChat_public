# RELEASE TEMPLATE. Only release-rendered copies are published. The HTTPS script
# pins an immutable verifier SHA256 before execution; the verifier authenticates
# the signed catalog and downloaded helper before installation.
param([ValidateSet('None','User')][string]$Service='None',[switch]$EnableRemote)
$ErrorActionPreference='Stop'
$taskVersion='0.1.0-preview.1'
$taskCatalogURL='https://raw.githubusercontent.com/xptea/VoidChat_public/main/versions-preview.json'
$taskPublicKey='WXyktmciSitTp6LhDDCcWyOSVwCmCliFIdKD1ZTzsZk='
# BEGIN pairing-readiness
function Get-PairingReady([string]$Executable) {
    $PSNativeCommandUseErrorActionPreference=$false
    for($taskAttempt=0;$taskAttempt -lt 30;$taskAttempt++) {
        $taskInvitation=@(& $Executable invite 2>$null)
        if($LASTEXITCODE -eq 0) {$taskInvitation | Write-Output;return}
        if($taskAttempt -lt 29){Start-Sleep -Seconds 1}
    }
    throw 'Helper installed, but its Tailscale listener is not ready. Install/sign in to Tailscale, then run voidchat-helper invite. No login or network policy was changed.'
}
# END pairing-readiness
if ($taskVersion.Contains('@')) { throw 'Use the generated installer from the public distribution repository.' }
$taskIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
if ((New-Object Security.Principal.WindowsPrincipal($taskIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run without elevation as the ordinary helper account.' }
$taskCPU=$env:PROCESSOR_ARCHITEW6432
if (-not $taskCPU) {$taskCPU=$env:PROCESSOR_ARCHITECTURE}
$taskArch=switch($taskCPU.ToUpperInvariant()) {'AMD64' {'amd64'} 'ARM64' {'arm64'} default {throw 'Windows amd64 or arm64 is required.'}}
$taskHashes=@{
    'darwin-amd64' = 'd3ec4d396750a6d73ec36f28b6f329bc65520a0e69379fa7428a40b4c37c609e'
    'darwin-arm64' = 'e8656e3be0fb8d451b7936ca58c511dc2f72e6bea134e34da10487364ad7f7d8'
    'linux-386' = '46c446cfec0991b1a9267e400cebed36316ee8edabe4d68f224a454bcbb2f348'
    'linux-amd64' = '4dd5cfe482418f91600f2825f3a261204ee44c0c1c5afce21c5e579e3ef65d7e'
    'linux-arm' = '5d1a86f297e74fe2eae81f40d292f2899f0e086eaebc65311f88c0cf49086997'
    'linux-arm64' = '166b637a8aa165ac32ac62a4b6e11fd801bbb252f837c7735f999fc7792e6000'
    'windows-amd64' = 'c1bded7fb5d3d67fa68c32380c3dc5156b49e4e4dbf1c0388dff8e350e0b2f46'
    'windows-arm64' = '8fddc193f9aa2f2941e3cd465ca859a7fc5f3105f714ee1f266e78fe98d88a12'

}
$taskExpected=$taskHashes["windows-$taskArch"]
if (-not $taskExpected) {throw 'No signed helper release for this platform.'}
Add-Type -AssemblyName System.Net.Http
function Get-VerifiedTransportFile([string]$Uri,[string]$Path,[long]$Limit) {
    if (-not $Uri.StartsWith('https://')) {throw 'HTTPS download required.'}
    $taskHttp=[Net.Http.HttpClient]::new();$taskHttp.Timeout=[TimeSpan]::FromMinutes(3)
    try {
        $taskResponse=$taskHttp.GetAsync($Uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $taskResponse.EnsureSuccessStatusCode() | Out-Null
        if ($taskResponse.RequestMessage.RequestUri.Scheme -ne 'https') {throw 'HTTPS redirect required.'}
        $taskInput=$taskResponse.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $taskOutput=[IO.File]::Create($Path)
        try {$taskBuffer=New-Object byte[] 32768;$taskCount=0L;while(($taskRead=$taskInput.Read($taskBuffer,0,$taskBuffer.Length)) -gt 0) {$taskCount+=$taskRead;if($taskCount -gt $Limit){throw 'Download exceeds allowed size.'};$taskOutput.Write($taskBuffer,0,$taskRead)}} finally {$taskOutput.Dispose();$taskInput.Dispose();$taskResponse.Dispose()}
    } finally {$taskHttp.Dispose()}
}
$taskWork=Join-Path ([IO.Path]::GetTempPath()) ('voidchat-install-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskWork | Out-Null
try {
    $taskVerifier=Join-Path $taskWork 'verify.exe'
    Get-VerifiedTransportFile "https://github.com/xptea/VoidChat_public/releases/download/helper-v$taskVersion/voidchat-release-tool-$taskVersion-windows-$taskArch.exe" $taskVerifier 134217728
    if ((Get-FileHash -LiteralPath $taskVerifier -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskExpected) {throw 'Bootstrap verifier SHA256 mismatch; nothing installed.'}
    $taskCatalog=Join-Path $taskWork 'versions.json'
    Get-VerifiedTransportFile $taskCatalogURL $taskCatalog 1048576
    $taskSelected=@(& $taskVerifier resolve --catalog $taskCatalog --component helper --os windows --arch $taskArch)
    if ($LASTEXITCODE -ne 0 -or $taskSelected.Count -ne 4) {throw 'Signed catalog verification failed.'}
    $taskCandidate=Join-Path $taskWork 'voidchat-helper.exe'
    Get-VerifiedTransportFile $taskSelected[0] $taskCandidate ([long]$taskSelected[2])
    & $taskVerifier verify-asset --catalog $taskCatalog --component helper --os windows --arch $taskArch --file $taskCandidate
    if ($LASTEXITCODE -ne 0) {throw 'Helper signature/hash verification failed.'}
    $taskBin=Join-Path $env:LOCALAPPDATA 'Programs/VoidChat/bin'
    $taskTarget=Join-Path $taskBin 'voidchat-helper.exe'
    New-Item -ItemType Directory -Path $taskBin -Force | Out-Null
    if ((Test-Path -LiteralPath $taskTarget) -and (Get-FileHash $taskTarget).Hash -ne (Get-FileHash $taskCandidate).Hash) {
        throw 'An existing helper launcher differs and was preserved. Use its managed update command, or explicitly migrate that installation after active work finishes.'
    }
    if (-not (Test-Path -LiteralPath $taskTarget) -or (Get-FileHash $taskTarget).Hash -ne (Get-FileHash $taskCandidate).Hash) {Copy-Item -LiteralPath $taskCandidate -Destination $taskTarget -Force}
    $taskUserPath=[Environment]::GetEnvironmentVariable('Path','User')
    if (($taskUserPath -split ';') -notcontains $taskBin) {[Environment]::SetEnvironmentVariable('Path',($taskBin+';'+$taskUserPath),'User')}
    if (($env:PATH -split ';') -notcontains $taskBin) {$env:PATH=$taskBin+';'+$env:PATH}
    if ($Service -eq 'User') {
        $taskQuoted=$taskTarget.Replace("'","''")
        $taskCommand="Start-Process -FilePath '$taskQuoted' -ArgumentList 'start' -WindowStyle Hidden -Wait"
        $taskEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($taskCommand))
        $taskAction=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $taskEncoded"
        $taskTrigger=New-ScheduledTaskTrigger -AtLogOn -User $taskIdentity.Name
        $taskPrincipal=New-ScheduledTaskPrincipal -UserId $taskIdentity.Name -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName 'VoidChatHelper' -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Force | Out-Null
        Start-ScheduledTask -TaskName 'VoidChatHelper'
    } else {& $taskTarget start;if($LASTEXITCODE -ne 0){throw 'Helper startup failed.'}}
    Write-Host "Installed helper $($taskSelected[3]) (catalog key primary: $taskPublicKey)."
    if ($EnableRemote) {
        & $taskTarget enable;if($LASTEXITCODE -ne 0){throw 'Could not enable remote access; check Tailscale.'}
        Get-PairingReady $taskTarget
    } else {Write-Host 'Remote access was not changed (off on a first install). To pair this host, rerun with -EnableRemote after signing in to Tailscale.'}
} finally {
    $taskResolved=[IO.Path]::GetFullPath($taskWork)
    $taskTempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if (-not $taskResolved.StartsWith($taskTempRoot,[StringComparison]::OrdinalIgnoreCase) -or $taskResolved -eq $taskTempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)) {throw 'Installer cleanup path escaped the temporary directory.'}
    Remove-Item -LiteralPath $taskResolved -Recurse -Force
}
