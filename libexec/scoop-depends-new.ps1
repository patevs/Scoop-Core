# Usage: scoop depends [<OPTIONS>] [<APP>]
# Summary: List dependencies for application(s).
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
$Options, $Applications, $_err = Resolve-GetOpt $args 'a:s' 'arch=', 'skip-installed'
$SkipInstalled = $Options.s -or $Options.'skip-installed'

if ($_err) { Stop-ScoopExecution -Message "scoop depends: $_err" -ExitCode 2 }
if (!$Applications) { Stop-ScoopExecution -Message 'Parameter <APP> missing' -Usage (my_usage) }

$Architecture = Resolve-ArchitectureParameter -Architecture $Options.a, $Options.arch

$res = @()
foreach ($app in $Applications) {
    $deps = @(deps $app $Architecture -IncludeInstalled:(!$SkipInstalled))
    if ($deps) { $res += $deps[($deps.Length - 1)..0] }
}

$message = 'No dependencies required'
if ($res.Count -gt 0) { $message = ($res | Select-Object -Unique) -join "`r`n" }

Write-UserMessage -Message $message -Output

exit $ExitCode

