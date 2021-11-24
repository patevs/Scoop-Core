Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
(7z.exe | Select-String -Pattern '7-Zip').ToString()

Write-Host 'Install dependencies ...'
# Force pester v4
Install-Module -Repository 'PSGallery' -Scope 'CurrentUser' -Name 'Pester' -RequiredVersion 4.10.1 -SkipPublisherCheck -Force
Install-Module -Repository 'PSGallery' -Scope 'CurrentUser' -Name 'PSScriptAnalyzer', 'BuildHelpers' -Force

if ($env:CI_WINDOWS -eq $true) {
    # TODO: Adopt native scoop installation
    # Do not force maintainers to have this inside environment appveyor config
    if (!$env:SCOOP_HELPERS) {
        $env:SCOOP_HELPERS = 'C:\projects\helpers'
        [System.Environment]::SetEnvironmentVariable('SCOOP_HELPERS', $env:SCOOP_HELPERS, 'Machine')
    }

    if (!(Test-Path $env:SCOOP_HELPERS)) { New-Item $env:SCOOP_HELPERS -ItemType Directory }
    if (!(Test-Path "$env:SCOOP_HELPERS\lessmsi\lessmsi.exe")) {
        Start-FileDownload 'https://github.com/activescott/lessmsi/releases/download/v1.9.0/lessmsi-v1.9.0.zip' -FileName "$env:SCOOP_HELPERS\lessmsi.zip"
        & 7z.exe x "$env:SCOOP_HELPERS\lessmsi.zip" -o"$env:SCOOP_HELPERS\lessmsi" -y
    }
    if (!(Test-Path "$env:SCOOP_HELPERS\innounp\innounp.exe")) {
        Start-FileDownload 'https://raw.githubusercontent.com/ScoopInstaller/Binary/master/innounp/innounp050.rar' -FileName "$env:SCOOP_HELPERS\innounp.rar"
        & 7z.exe x "$env:SCOOP_HELPERS\innounp.rar" -o"$env:SCOOP_HELPERS\innounp" -y
    }
}

if ($env:CI -eq $true) {
    Write-Host "Load 'BuildHelpers' environment variables ..."
    Set-BuildEnvironment -Force
}

$buildVariables = ( Get-ChildItem -Path 'Env:' ).Where( { $_.Name -match '^(?:BH|CI(?:_|$)|APPVEYOR)' } )
$buildVariables += ( Get-Variable -Name 'CI_*' -Scope 'Script' )
$details = $buildVariables |
    Where-Object -FilterScript { $_.Name -notmatch 'EMAIL' } |
    Sort-Object -Property 'Name' |
    Format-Table -AutoSize -Property 'Name', 'Value' |
    Out-String
Write-Host 'CI variables:'
Write-Host $details -ForegroundColor DarkGray
