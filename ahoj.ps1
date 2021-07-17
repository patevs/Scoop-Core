@(@('core', 'Test-ScoopDebugEnabled') ,@()) | ForEach-Object {
    Write-Host $_[0] -f Magenta
    Write-Host $_[1] -f REd
}
