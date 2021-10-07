# Usage: scoop install [<OPTIONS>] <APP>...
# Summary: Install specific application(s).
# Help: The usual way to install an application (uses your local 'buckets'):
#   scoop install git
#   scoop install extras/googlechrome
#
# To install an application from a manifest at a URL:
#   scoop install https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/runat.json
#
# To install an application from a manifest on your computer:
#   scoop install D:\path\to\app.json
#   scoop install ./install/pwsh.json
#
# To install specific version of manifest
#   scoop install bat@0.15.0
#   scoop install extras/cmder@1.0.0
#
# Options:
#   -h, --help                      Show help for this command.
#   -a, --arch <32bit|64bit|arm64>  Use the specified architecture, if the application's manifest supports it.
#   -g, --global                    Install the application(s) globally.
#   -f, --force                     Force application to be reinstalled, effectively overriding current installation.
#   -i, --independent               Do not install dependencies automatically.
#   -k, --no-cache                  Do not use the download cache.
#   -s, --skip                      Skip hash validation (use with caution!).

'core', 'buckets', 'decompress', 'Dependencies', 'getopt', 'help', 'Helpers', 'manifest', 'shortcuts', 'psmodules', 'Update', 'Versions', 'install' | ForEach-Object {
    . (Join-Path $PSScriptRoot "..\lib\$_.ps1")
}

$ExitCode = 0
$Problems = 0
$Options, $ProvidedApplications, $_err = Resolve-GetOpt $args 'gfiksa:' 'global', 'force', 'independent', 'no-cache', 'skip', 'arch='

if ($_err) { Stop-ScoopExecution -Message "scoop install: $_err" -ExitCode 2 }

$Global = $Options.g -or $Options.global
$Force = $Options.f -or $Options.force
$SkipHashCheck = $Options.s -or $Options.skip
$Independent = $Options.i -or $Options.independent
$NoCache = !($Options.k -or $Options.'no-cache')
$Architecture = Resolve-ArchitectureParameter -Architecture $Options.a, $Options.arch

if (!$ProvidedApplications) { Stop-ScoopExecution -Message 'Parameter <APP> missing' -Usage (my_usage) }
if ($Global -and !(is_admin)) { Stop-ScoopExecution -Message 'Admin privileges are required to manipulate with globally installed applications' -ExitCode 4 }

if (is_scoop_outdated) { Update-Scoop }

# First resolve what applications to install
$suggested = @{ }
$toInstall = @()
$dependenciesToInstall = @()
$failedDependencies = @()
$failedApplications = @()

# Parse the provided values
foreach ($toResolve in $ProvidedApplications) {
    $resolved = $null
    try {
        $resolved = Resolve-ManifestInformation -ApplicationQuery $toResolve
    } catch {
        ++$Problems
        $failedApplications += $toResolve

        debug $_.InvocationInfo
        New-IssuePromptFromException -ExceptionMessage $_.Exception.Message

        continue
    }

    $toInstall += $resolved
}

if ($toInstall.Count -eq 0) { Stop-ScoopExecution -Message 'Nothing to install' }

$ApplicationsToInstall = Resolve-InstallationQueueDependency -ResolvedManifestInformatin $toInstall -Architecture $Architecture

Write-Host $ApplicationsToInstall -f red

exit 0







# Iterate in all resolved manifests and resolve dependencies
foreach ($dep in $toInstall) {
}

if (!$Independent) {
    try {
        $apps = install_order $toInstall $Architecture # Add dependencies
    } catch {
        New-IssuePromptFromException -ExceptionMessage $_.Exception.Message
    }
}










show_suggestions $suggested

if ($failedApplications) {
    $pl = pluralize $failedApplications.Count 'This application' 'These applications'
    Write-UserMessage -Message "$pl failed to install: $($failedApplications -join ', ')" -Err
}

if ($failedDependencies) {
    $pl = pluralize $failedDependencies.Count 'This dependency' 'These dependencies'
    Write-UserMessage -Message "$pl failed to install: $($failedDependencies -join ', ')" -Err
}

if ($Problems -gt 0) { $ExitCode = 10 + $Problems }

exit $exitCode







# Iterate in all provided values
# Recursively resolve dependencies


# Install everything














foreach ($app in $toInstall) {
    # Install
    try {
        install_app $app $architecture $global $suggested $use_cache $check_hash
    } catch {
        ++$Problems

        # Register failed dependencies
        if ($explicit_apps -notcontains $app) { $failedDependencies += $app } else { $failedApplications += $app }

        debug $_.InvocationInfo
        New-IssuePromptFromException -ExceptionMessage $_.Exception.Message -Application $cleanApp -Bucket $bucket

        continue
    }
}

#===============================================================
# TODO: Export
# TODO: Cleanup
function is_installed($app, $global, $version) {
    if ($app.EndsWith('.json')) {
        $app = [System.IO.Path]::GetFileNameWithoutExtension($app)
    }

    if (installed $app $global) {
        function gf($g) { if ($g) { ' --global' } }

        # Explicitly provided version indicate local workspace manifest with older version of already installed application
        if ($version) {
            $all = @(Get-InstalledVersion -AppName $app -Global:$global)
            return $all -contains $version
        }

        $version = Select-CurrentVersion -AppName $app -Global:$global
        if (!(install_info $app $version $global)) {
            Write-UserMessage -Err -Message @(
                "It looks like a previous installation of '$app' failed."
                "Run 'scoop uninstall $app$(gf $global)' before retrying the install."
            )
            return $true
        }
        Write-UserMessage -Warning -Message @(
            "'$app' ($version) is already installed.",
            "Use 'scoop update $app$(gf $global)' to install a new version."
        )

        return $true
    }

    return $false
}


# Get any specific versions that need to be handled first
$specific_versions = $apps | Where-Object {
    $null, $null, $version = parse_app $_
    return $null -ne $version
}

# Compare object does not like nulls
if ($specific_versions.Length -gt 0) {
    $difference = Compare-Object -ReferenceObject $apps -DifferenceObject $specific_versions -PassThru
} else {
    $difference = $apps
}

$specific_versions_paths = @()
foreach ($sp in $specific_versions) {
    $app, $bucket, $version = parse_app $sp
    if (installed_manifest $app $version) {
        Write-UserMessage -Warn -Message @(
            "'$app' ($version) is already installed.",
            "Use 'scoop update $app$global_flag' to install a new version."
        )
        continue
    } else {
        try {
            $specific_versions_paths += generate_user_manifest $app $bucket $version
        } catch {
            Write-UserMessage -Message $_.Exception.Message -Color DarkRed
            ++$problems
        }
    }
}
$apps = @(($specific_versions_paths + $difference) | Where-Object { $_ } | Sort-Object -Unique)

# Remember which were explictly requested so that we can
# differentiate after dependencies are added
$explicit_apps = $apps

# This should not be breaking error in case there are other apps specified
if ($apps.Count -eq 0) { Stop-ScoopExecution -Message 'Nothing to install' }

$apps = ensure_none_failed $apps $global

if ($apps.Count -eq 0) { Stop-ScoopExecution -Message 'Nothing to install' }

$apps, $skip = prune_installed $apps $global

$skip | Where-Object { $explicit_apps -contains $_ } | ForEach-Object {
    $app, $null, $null = parse_app $_
    $version = Select-CurrentVersion -AppName $app -Global:$global
    Write-UserMessage -Message "'$app' ($version) is already installed. Skipping." -Warning
}
