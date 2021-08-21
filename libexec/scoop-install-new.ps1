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
