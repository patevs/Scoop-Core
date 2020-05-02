# Usage: scoop checkup
# Summary: Check for potential problems
# Help: Performs a series of diagnostic tests to try to identify things that may
# cause problems with Scoop.

'core', 'Diagnostic' | ForEach-Object {
    . "$PSScriptRoot\..\lib\$_.ps1"
}

$issues = 0
$issues += !(Test-WindowsDefender)
$issues += !(Test-WindowsDefender -Global)
$issues += !(Test-MainBucketAdded)
$issues += !(Test-LongPathEnabled)
$issues += !(Test-EnvironmentVariable)
$issues += !(Test-HelpersInstalled)
$issues += !(Test-Drive)
$issues += !(Test-Config)

if ($issues) {
    Write-UserMessage -Message "Found $issues potential $(pluralize $issues 'problem' 'problems')." -Warning
    $exitCode = 1
} else {
    Write-UserMessage -Message 'No problems identified!' -Success
    $exitCode = 0
}

exit $exitCode
