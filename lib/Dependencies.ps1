'Helpers', 'install', 'decompress' | ForEach-Object {
    . (Join-Path $PSScriptRoot "$_.ps1")
}

# Return array of plain text values to be resolved
function Get-ManifestDependencies {
    param($ManifestObject)

    process {
        $result = @()
        # Direct dependencies defined in manifest
        # TODO: Support requirements property


        return $result
    }
}
