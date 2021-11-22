# Usage: scoop info [<OPTIONS>] <APP>
# Summary: Display information about an application.
# Help: When provided application is installed, all information will be shown based on the locally installed manifest.
#
# Options:
#   -h, --help                      Show help for this command.
#   -a, --arch <32bit|64bit|arm64>  Use the specified architecture, if the application's manifest supports it.
#   -g, --global                    Gather local information from globally installed application, rather then local.
#                                       Usefull for pre-check of installed specific application in automatic deployments.

@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('getopt', 'Resolve-GetOpt'),
    @('help', 'scoop_help'),
    @('Helpers', 'New-IssuePrompt'),
    @('Applications', 'Get-InstalledApplicationInformation'),
    @('buckets', 'Get-KnownBucket'),
    @('depends', 'script_deps'),
    @('install', 'install_app'),
    @('manifest', 'Resolve-ManifestInformation'),
    @('Versions', 'Clear-InstalledVersion')
) | ForEach-Object {
    if (!([bool] (Get-Command $_[1] -ErrorAction 'Ignore'))) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "..\lib\$($_[0]).ps1")
    }
}

$ExitCode = 0
# TODO: Add some --remote parameter to not use installed manifest
#   -r, --remote >    Remote manifest will be used to get all required information. Ignoring locally installed manifest (scoop-manifest.json).
$Options, $Application, $_err = Resolve-GetOpt $args 'a:g' 'arch=', 'global'

if ($_err) { Stop-ScoopExecution -Message "scoop info: $_err" -ExitCode 2 }
if (!$Application) { Stop-ScoopExecution -Message 'Parameter <APP> missing' -Usage (my_usage) }

$Application = $Application[0]
$Architecture = Resolve-ArchitectureParameter -Architecture $Options.a, $Options.arch
$Global = $Options.'g' -or $Options.'global'

$Resolved = $null
try {
    $Resolved = Resolve-ManifestInformation -ApplicationQuery $Application
} catch {
    # Edge case: Check if the application is installed locally
    $_s = app_status $Application $Global
    if ($_s.installed -ne $false) {
        $Resolved = [Ordered] @{
            'ApplicationName' = $Application
            'ManifestObject'  = $_s.manifest
            'Url'             = $_s.url
        }
    } else {
        Stop-ScoopExecution -Message $_.Exception.Message
    }
}

# Variables
$Name = $Resolved.ApplicationName
$Message = @()
$Status = app_status $Name $Global
$Manifest = $Resolved.ManifestObject
$ManifestPath = @($Resolved.LocalPath)

# Application is installed. Could be from different url/bucket/
if ($Status.installed) {
    # Application is installed from url rather than other resolve
    $_r = $null
    if ($Status.url -and !$Resolved.Url) {
        $Status.installed = $false
        $_r = 'UrlNotResolvedUrl'
    }
    # Installed from different bucket
    if ($Status.bucket -and $Resolved.Bucket -and ($Status.bucket -ne $Resolved.Bucket)) {
        $Status.installed = $false
        $_r = 'BucketMismatch'
    }
    # Application is installed from different url
    if ($Resolved.Url -and ($Status.url -ne $Resolved.Url)) {
        $Status.installed = $false
        $_r = 'UrlMismatch'
    }
    $Status.Add('reasonNotInstalled', $_r)
}

$reason = $null
if ($Status.reasonNotInstalled) {
    $Manifest = $Resolved.ManifestObject

    switch ($Status.reasonNotInstalled) {
        'BucketMismatch' {
            $ManifestPath = $Resolved.LocalPath
            $reason = 'Application installed from different bucket'
        }
        'UrlNotResolvedUrl' {
            $ManifestPath = $Resolved.Url
            $reason = "Application installed from URL, request using '$Application'"
        }
        'UrlMismatch' {
            $ManifestPath = $Resolved.Url
            $reason = 'Application installed from different URL'
        }
        'VersionMismatch' {
            try {
                $i = installed_manifest $Name $Manifest.version $Global
                if ($null -eq $i) {
                    throw 'trigger'
                }
                $Manifest = $i
                $ManifestPath = installed_manifest $Name $Manifest.version $Global -PathOnly
            } catch {
                $Status.reasonNotInstalled = 'VersionNotInstalled'
                $reason = 'Application installed with different version'
            }
        }
    }
}
$ManifestPath = $ManifestPath, $Resolved.Url, (installed_manifest $Name $Manifest.version $Global -PathOnly), $Resolved.LocalPath | Where-Object {
    -not [String]::IsNullOrEmpty($_)
}

$dir = (versiondir $Name $Manifest.version $Global).TrimEnd('\')
$original_dir = (versiondir $Name $Resolved.Version $Global).TrimEnd('\')
$persist_dir = (persistdir $Name $Global).TrimEnd('\')
$up = if ($Status.outdated) { 'Yes' } else { 'No' }

$Message = @("Name: $Name")
$Message += "Version: $($Manifest.Version)"
if ($Manifest.description) { $Message += "Description: $($Manifest.description)" }
if ($Manifest.homepage) { $Message += "Website: $($Manifest.homepage)" }

# Show license
# TODO: Rework
if ($Manifest.license) {
    $license = $Manifest.license
    if ($Manifest.license.identifier -and $Manifest.license.url) {
        $license = "$($Manifest.license.identifier) ($($Manifest.license.url))"
    } elseif ($Manifest.license -match '^((ht)|f)tps?://') {
        $license = "$($Manifest.license)"
    } elseif ($Manifest.license -match '[|,]') {
        $licurl = $Manifest.license.Split('|,') | ForEach-Object { "https://spdx.org/licenses/$_.html" }
        $license = "$($Manifest.license) ($($licurl -join ', '))"
    } else {
        $license = "$($Manifest.license) (https://spdx.org/licenses/$($Manifest.license).html)"
    }
    $Message += "License: $license"
}

if ($Manifest.changelog) {
    $ch = $Manifest.changelog
    if (!$ch.StartsWith('http')) {
        if ($Status.installed) {
            $ch = Join-Path $dir $ch
        } else {
            $ch = "Could be found in file '$ch' inside application directory. Install application to see a recent changes"
        }
    }
    $Message += "Changelog: $ch"
}

# Manifest file
$Message += @('Manifest:')
foreach ($m in $ManifestPath) { $Message += "  $m" }

$arm64Support = 'No'
if ($Manifest.architecture.arm64) { $arm64Support = 'Yes' }
$Message += "arm64 Support: $arm64Support"

# Show installed versions
if ($Status.installed) {
    $Message += 'Installed: Yes'
    $v = Get-InstalledVersion -AppName $Name -Global:$Global
    if ($v.Count -gt 0) {
        $Message += "Installed versions: $($v )"
    }
    $Message += "Update available: $up"

    $InstallInfo = install_info $Name $Manifest.version $Global
    $Architecture = $InstallInfo.architecture
} else {
    $inst = 'Installed: No'
    if ($reason) { $inst = "$inst ($reason)" }
    $Message += $inst
}
$binaries = @(arch_specific 'bin' $Manifest $Architecture)
if ($binaries) {
    $Message += 'Binaries:'
    $add = ' '
    foreach ($b in $binaries) {
        $addition = "$b"
        if ($b -is [System.Array]) {
            $addition = $b[0]
            if ($b[1]) {
                $addition = "$($b[1]).exe"
            }
        }
        $add = "$add $addition"
    }
    $Message += $add
}

#region Environment
$env_set = arch_specific 'env_set' $Manifest $Architecture
$env_add_path = @(arch_specific 'env_add_path' $Manifest $Architecture)

if ($env_set -or $env_add_path) {
    $m = 'Environment:'
    if (!$Status.installed) { $m += ' (simulated)' }
    $Message += $m
}

if ($env_set) {
    foreach ($es in $env_set | Get-Member -MemberType 'NoteProperty') {
        $value = env $es.Name $Global
        if (!$value) {
            $value = format $env_set.$($es.Name) @{ 'dir' = $dir }
        }
        $Message += "  $($es.Name)=$value"
    }
}
if ($env_add_path) {
    # TODO: Should be path rather joined on one line or with multiple PATH=??
    # Original:
    # PATH=%PATH%;C:\SCOOP\apps\yarn\current\global\node_modules\.bin
    # PATH=%PATH%;C:\SCOOP\apps\yarn\current\Yarn\bin
    # vs:
    # PATH=%PATH%;C:\SCOOP\apps\yarn\current\global\node_modules\.bin;C:\SCOOP\apps\yarn\current\Yarn\bin
    foreach ($ea in $env_add_path | Where-Object { $_ }) {
        $to = "$dir"
        if ($ea -ne '.') {
            $to = "$to\$ea"
        }
        $Message += "  PATH=%PATH%;$to"
    }
}
#endregion Environment

# Available versions:
$vers = Find-BucketDirectory -Name $Resolved.Bucket | Join-Path -ChildPath "old\$Name" | Get-ChildItem -ErrorAction 'SilentlyContinue' -File |
    Where-Object -Property 'Name' -Match -Value "\.($ALLOWED_MANIFEST_EXTENSION_REGEX)$"

if ($vers.Count -gt 0) { $Message += "Available Versions: $($vers.BaseName -join ', ')" }

Write-UserMessage -Message $Message -Output

# Show notes
show_notes $Manifest $dir $original_dir $persist_dir

exit $ExitCode
