# RELEASE TEMPLATE. Only release-rendered copies are published. The HTTPS script
# pins an immutable verifier SHA256 before execution; the verifier authenticates
# the signed catalog and downloaded helper before installation.
param([ValidateSet('None','User')][string]$Service='None',[switch]$EnableRemote)
$ErrorActionPreference='Stop'
$taskVersion='0.1.2'
$taskCatalogURL='https://raw.githubusercontent.com/xptea/VoidChat_public/main/versions.json'
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
Write-Host 'Installing VoidChat helper...'
$taskIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
if ((New-Object Security.Principal.WindowsPrincipal($taskIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run without elevation as the ordinary helper account.' }
$taskCPU=$env:PROCESSOR_ARCHITEW6432
if (-not $taskCPU) {$taskCPU=$env:PROCESSOR_ARCHITECTURE}
$taskArch=switch($taskCPU.ToUpperInvariant()) {'AMD64' {'amd64'} default {throw 'New Windows helper releases support amd64 only.'}}
$taskHashes=@{
    'darwin-arm64' = '842ed70f783687566f4e1cf3570237da5e2d6e856c2580ecbb9dce50a3e37fe3'
    'linux-386' = 'fead152f270e26930babbaa4cff7305c685870e46993f4112de93ab793369d68'
    'linux-amd64' = '90f065f770c457d1f1de89dd0e1bb45d823172250786216cb4e815c53b818687'
    'linux-arm' = '4147061a88bd5c883d6a11372f91a44b145133eec0cbaa5189ff6a3b338d5d62'
    'linux-arm64' = '653c71ae785b9c3b756a2f2be80e4e19f1565496b9e2d2e3b45c9e7abaf07b7a'
    'windows-amd64' = 'fea6033e96e8eb65d714b4ce85001cfb08ed5078191c75aa5e98b317282bf35c'

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
    & $taskVerifier verify-asset --catalog $taskCatalog --component helper --os windows --arch $taskArch --file $taskCandidate | Out-Null
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
    } else {& $taskTarget start | Out-Null;if($LASTEXITCODE -ne 0){throw 'Helper startup failed.'}}
    Write-Host "`nVoidChat helper $($taskSelected[3]) installed."
    if ($EnableRemote) {
        & $taskTarget enable;if($LASTEXITCODE -ne 0){throw 'Could not enable remote access; check Tailscale.'}
        Get-PairingReady $taskTarget
    } else {Write-Host 'To pair this computer, run: voidchat-helper enable; voidchat-helper invite'}
} finally {
    $taskResolved=[IO.Path]::GetFullPath($taskWork)
    $taskTempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if (-not $taskResolved.StartsWith($taskTempRoot,[StringComparison]::OrdinalIgnoreCase) -or $taskResolved -eq $taskTempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)) {throw 'Installer cleanup path escaped the temporary directory.'}
    Remove-Item -LiteralPath $taskResolved -Recurse -Force
}
