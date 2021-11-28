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
# Options:
#   -h, --help                      Show help for this command.
#   -a, --arch <32bit|64bit|arm64>  Use the specified architecture, if the application's manifest supports it.
#   -g, --global                    Install the application(s) globally.
#   -i, --independent               Do not install dependencies automatically.
#   -k, --no-cache                  Do not use the download cache.
#   -s, --skip                      Skip hash validation (use with caution!).

@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('getopt', 'Resolve-GetOpt'),
    @('help', 'scoop_help'),
    @('Helpers', 'New-IssuePrompt'),
    @('Applications', 'Get-InstalledApplicationInformation'),
    @('buckets', 'Get-KnownBucket'),
    @('decompress', 'Expand-7zipArchive'),
    @('Dependencies', 'Resolve-DependsProperty'),
    @('Installation', 'Install-Application'),
    @('manifest', 'Resolve-ManifestInformation'),
    @('psmodules', 'install_psmodule'),
    @('shortcuts', 'rm_startmenu_shortcuts'),
    @('Update', 'Update-ScoopCoreClone'),
    @('Versions', 'Clear-InstalledVersion')
) | ForEach-Object {
    if (!([bool] (Get-Command $_[1] -ErrorAction 'Ignore'))) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "..\lib\$($_[0]).ps1")
    }
}

$ExitCode = 0
$Problems = 0
$Options, $Applications, $_err = Resolve-GetOpt $args 'giksa:' 'global', 'independent', 'no-cache', 'skip', 'arch='
if ($_err) { Stop-ScoopExecution -Message "scoop install: $_err" -ExitCode 2 }

$Global = $Options.g -or $Options.global
$Independent = $Options.i -or $Options.independent
$UseCache = !($Options.k -or $Options.'no-cache')
$CheckHash = !($Options.s -or $Options.skip)
$Architecture = Resolve-ArchitectureParameter -Architecture $Options.a, $Options.arch

if (!$Applications) { Stop-ScoopExecution -Message 'Parameter <APP> missing' -Usage (my_usage) }
if ($Global -and !(is_admin)) { Stop-ScoopExecution -Message 'Admin privileges are required to manipulate with globally installed applications' -ExitCode 4 }

Update-Scoop -CheckLastUpdate

$suggested = @{ }
$failedDependencies = @()
$failedApplications = @()
$toInstall = @{
    'Failed'   = @()
    'Resolved' = @()
}

# Properly resolve all dependencies and applications
if ($Independent) {
    foreach ($a in $Applications) {
        $ar = $null
        try {
            $ar = Resolve-ManifestInformation -ApplicationQuery $a
        } catch {
            ++$Problems
            Write-UserMessage -Message "$($_.Exception.Message)" -Err
            continue
        }

        $toInstall.Resolved += $ar
    }
} else {
    $toInstall = Resolve-MultipleApplicationDependency -Applications $Applications -Architecture $Architecture
}

# TODO: Try to rather remove from the array instead of creating new one
# Filter not installed
$new = @()
foreach ($inst in $toInstall.Resolved) {
    if (Test-ResolvedObjectIsInstalled -ResolvedObject $inst -Global:$Global) {
        continue
    }
    $new += $inst
}
$toInstall.Resolved = $new

if ($toInstall.Resolved.Count -eq 0) {
    Stop-ScoopExecution -Message 'Nothing to install' -ExitCode $ExitCode -SkipSeverity
}

foreach ($app in $toInstall.Resolved) {
    # Skip installation of application if any of the dependency failed
    if (($false -eq $Independent)) {
        $applicationSpecificDependencies = ($toInstall.Resolved | Where-Object -Property 'Dependency' -EQ $app.ApplicationName).Print
        if ($null -eq $applicationSpecificDependencies) {
            $applicationSpecificDependencies = @()
        }

        $cmp = Compare-Object $applicationSpecificDependencies $failedDependencies -ExcludeDifferent

        # Skip Installation because required depency failed
        if ($cmp -and ($cmp.InputObject.Count -gt 0)) {
            $f = $cmp.InputObject -join ', '
            Write-UserMessage -Message "'$($app.Print)' cannot be installed due to failed dependency installation ($f)" -Err
            ++$Problems
            continue
        }
    }

    try {
        Install-ScoopApplication -ResolvedObject $app -Architecture $Architecture -Global:$Global -Suggested:$suggested `
            -UseCache:$UseCache -CheckHash:$CheckHash
    } catch {
        ++$Problems

        # Register failed dependencies
        if ($app.Dependency -eq $true) {
            $failedDependencies += $app.Print
        } else {
            $failedApplications += $app.Print
        }

        debug $_.InvocationInfo
        New-IssuePromptFromException -ExceptionMessage $_.Exception.Message -Application $app.ApplicationName -Bucket $app.Bucket

        continue
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

exit $ExitCode
