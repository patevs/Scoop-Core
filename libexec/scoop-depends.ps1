# Usage: scoop depends [<OPTIONS>] <APP>...
# Summary: List dependencies for application(s).
# Help: All dependencies will be "resolved"/checked, if they are accessible (in case of remote manifests or different versions).
#
# If application was already resolved as a dependency, duplicate will not be added (even when the versions are different).
# 'shovel depends 7zip lessmsi@1.9.0' will resolve just to `main/lessmsi` instead of 'main/lessmsi main/lessmsi@1.9.0'
# Output of depends command could be used for 'shovel cat' command to verify and check all the manifests, which will be installed.
#
# Options:
#   -h, --help                      Show help for this command.
#   -a, --arch <32bit|64bit|arm64>  Use the specified architecture, if the application's manifest supports it.
#   -s, --skip-installed          Do not list dependencies, which are already installed

@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('getopt', 'Resolve-GetOpt'),
    @('help', 'scoop_help'),
    @('Helpers', 'New-IssuePrompt'),
    @('Dependencies', 'Resolve-DependsProperty')
) | ForEach-Object {
    if (!([bool] (Get-Command $_[1] -ErrorAction 'Ignore'))) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "..\lib\$($_[0]).ps1")
    }
}

$ExitCode = 0
$Problems = 0
$Options, $Applications, $_err = Resolve-GetOpt $args 'a:s' 'arch=', 'skip-installed'
$SkipInstalled = $Options.s -or $Options.'skip-installed'

if ($_err) { Stop-ScoopExecution -Message "scoop depends: $_err" -ExitCode 2 }
if (!$Applications) { Stop-ScoopExecution -Message 'Parameter <APP> missing' -Usage (my_usage) }

$Architecture = Resolve-ArchitectureParameter -Architecture $Options.a, $Options.arch

$toInstall = Resolve-MultipleApplicationDependency -Applications $Applications -Architecture $Architecture -IncludeInstalledDeps:(!$SkipInstalled) -IncludeInstalledApps:(!$SkipInstalled)
$_apps = @($toInstall.Resolved | Where-Object -Property 'Dependency' -EQ -Value $false)
$_deps = @($toInstall.Resolved | Where-Object -Property 'Dependency' -NE -Value $false)

if ($toInstall.Failed.Count -gt 0) {
    $Problems = $toInstall.Failed.Count
}

$message = 'No dependencies required'
if ($_deps.Count -gt 0) {
    $message = $_deps.Print -join "`r`n"
}

Write-UserMessage -Message $message -Output
if ($Problems -gt 0) {
    $ExitCode = 10 + $Problems
}

exit $ExitCode
