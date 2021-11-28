# Usage: scoop virustotal [<OPTIONS>] <APP>...
# Summary: Search virustotal database for potential viruses in files provided in manifest(s).
# Help: You can use '*' in place of <APP> to check all installed applications.
#
# The hash of file is also a key to access VirusTotal's scan results.
# This allows to check the safety of the files without even downloading
# them in many cases. If the hash is unknown to VirusTotal, the
# download link is printed and VirusTotal detection is triggered.
#
#   scoop config 'virustotal_api_key' <your API key: 64 lower case hex digits>
#
# Exit codes:
#   0 -> success
#   1 -> problem parsing arguments
#   2 -> at least one package was marked unsafe by VirusTotal
#   4 -> at least one exception was raised while looking for info
#   8 -> at least one package couldn't be queried because its hash type
#        isn't supported by VirusTotal, the manifest couldn't be found
#        or didn't contain a hash
#   Note: the exit codes (2, 4 & 8) may be combined, e.g. 6 -> exit codes
#         2 & 4 combined
#
# Options:
#   -h, --help                      Show help for this command.
#   -a, --arch <32bit|64bit|arm64>  Use the specified architecture, if the manifest supports it.
#   -s, --scan                      For packages where VirusTotal has no information, send download URL for analysis (and future retrieval).
#                                   This requires you to configure your virustotal_api_key (see help entry for config command).
#   -i, --independent               By default, all dependencies are checked. Use this parameter check only the application without dependencies.

@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('getopt', 'Resolve-GetOpt'),
    @('help', 'scoop_help'),
    @('Helpers', 'New-IssuePrompt'),
    @('Dependencies', 'Resolve-DependsProperty'),
    @('VirusTotal', 'Search-VirusTotal')
) | ForEach-Object {
    if (!([bool] (Get-Command $_[1] -ErrorAction 'Ignore'))) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "..\lib\$($_[0]).ps1")
    }
}

# TODO: Drop --scan??

$ExitCode = 0
$Options, $Applications, $_err = Resolve-GetOpt $args 'a:si' 'arch=', 'scan', 'independent'

if ($_err) { Stop-ScoopExecution -Message "scoop virustotal: $_err" -ExitCode 2 }
if (!$Applications) { Stop-ScoopExecution -Message 'Parameter <APP> missing' -Usage (my_usage) }
if (!$VT_API_KEY) { Stop-ScoopExecution -Message 'Virustotal API Key is required' }

$DoScan = $Options.scan -or $Options.s
$Independent = $Options.independent -or $Options.i
$Architecture = Resolve-ArchitectureParameter -Architecture $Options.a, $Options.arch
$toInstall = @{
    'Failed'   = @()
    'Resolved' = @()
}

# Buildup all installed applications
if ($Applications -eq '*') {
    $Applications = installed_apps $false
    $Applications += installed_apps $true
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
    $toInstall = Resolve-MultipleApplicationDependency -Applications $Applications -Architecture $Architecture -IncludeInstalled
}

foreach ($app in $toInstall.Resolved) {
    $appName = $app.ApplicationName
    $manifest = $app.ManifestObject

    if (!$manifest) {
        $ExitCode = $ExitCode -bor $VT_ERR.NoInfo
        Write-UserMessage -Message "${appName}: manifest not found" -Err
        continue
    }

    foreach ($url in (url $manifest $Architecture)) {
        $hash = hash_for_url $manifest $url $Architecture

        if (!$hash) {
            Write-UserMessage -Message "${appName}: Cannot find hash for '$url'" -Warning
            # TODO: Adopt if ($Download) {}
            continue
        }

        try {
            $ExitCode = $ExitCode -bor (Search-VirusTotal $hash $appName)
        } catch {
            $ExitCode = $ExitCode -bor $VT_ERR.Exception

            if ($_.Exception.Message -like '*(404)*') {
                Submit-ToVirusTotal -Url $url -App $appName -DoScan:$DoScan
            } else {
                if ($_.Exception.Message -match '\(204|429\)') {
                    Write-UserMessage -Message "${appName}: VirusTotal request failed: $($_.Exception.Message)"
                    $ExitCode = 3
                    continue
                }
                Write-UserMessage -Message "${appName}: VirusTotal request failed: $($_.Exception.Message)"
            }
        }
    }
}

exit $ExitCode
