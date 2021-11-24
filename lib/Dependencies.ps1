@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('Helpers', 'New-IssuePrompt'),
    @('decompress', 'Expand-7zipArchive'),
    @('install', 'install_app')
) | ForEach-Object {
    if (!([bool] (Get-Command $_[1] -ErrorAction 'Ignore'))) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "$($_[0]).ps1")
    }
}

function Resolve-DependsProperty {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param($Manifest)

    process {
        # TODO: Adopt requirements property
        if ($Manifest.depends) { return $Manifest.depends }

        return @()
    }
}

function Resolve-DependenciesInScriptProperty {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param($Script, [Switch] $IncludeInstalled)

    begin {
        $dependencies = @()
        if ($Script -is [Array]) { $Script = $Script -join "`n" }
        if ([String]::IsNullOrEmpty($Script)) { return $dependencies }
    }

    process {
        switch -Wildcard ($Script) {
            'Expand-7ZipArchive *' {
                if ($IncludeInstalled -or !(Test-HelperInstalled -Helper '7zip')) { $dependencies += '7zip' }
            }
            'Expand-MsiArchive *' {
                if ((get_config 'MSIEXTRACT_USE_LESSMSI' $true) -and ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'Lessmsi'))) {
                    $dependencies += 'lessmsi'
                }
            }
            'Expand-InnoArchive *' {
                if ((get_config 'INNOSETUP_USE_INNOEXTRACT' $false) -or ($script -like '* -UseInnoextract *')) {
                    if ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'InnoExtract')) { $dependencies += 'innoextract' }
                } else {
                    if ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'Innounp')) { $dependencies += 'innounp' }
                }
            }
            '*Expand-ZstdArchive *' {
                # Ugly, unacceptable and horrible patch to cover the tar.zstd use cases
                if ($IncludeInstalled -or !(Test-HelperInstalled -Helper '7zip')) { $dependencies += '7zip' }
                if ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'Zstd')) { $dependencies += 'zstd' }
            }
            '*Expand-DarkArchive *' {
                if ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'Dark')) { $dependencies += 'dark' }
            }
        }
    }

    end { return $dependencies }
}

function Resolve-InstallationDependency {
    [CmdletBinding()]
    param($Manifest, [String] $Architecture, [Switch] $IncludeInstalled)

    begin {
        $dependencies = @()
        $urls = url $Manifest $Architecture
    }

    process {
        if (Test-7zipRequirement -URL $urls) {
            if ($IncludeInstalled -or !(Test-HelperInstalled -Helper '7zip')) { $dependencies += '7zip' }
        }
        if (Test-LessmsiRequirement -URL $urls) {
            if ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'Lessmsi')) { $dependencies += 'lessmsi' }
        }

        if ($Manifest.innosetup) {
            if (get_config 'INNOSETUP_USE_INNOEXTRACT' $false) {
                if ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'Innoextract')) { $dependencies += 'innoextract' }
            } else {
                if ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'Innounp')) { $dependencies += 'innounp' }
            }
        }

        if (Test-ZstdRequirement -URL $urls) {
            # Ugly, unacceptable and horrible patch to cover the tar.zstd use cases
            if ($IncludeInstalled -or !(Test-HelperInstalled -Helper '7zip')) { $dependencies += '7zip' }
            if ($IncludeInstalled -or !(Test-HelperInstalled -Helper 'Zstd')) { $dependencies += 'zstd' }
        }

        $pre_install = arch_specific 'pre_install' $Manifest $Architecture
        $installer = arch_specific 'installer' $Manifest $Architecture
        $post_install = arch_specific 'post_install' $Manifest $Architecture

        $dependencies += Resolve-DependenciesInScriptProperty $pre_install -IncludeInstalled:$IncludeInstalled
        $dependencies += Resolve-DependenciesInScriptProperty $installer.script -IncludeInstalled:$IncludeInstalled
        $dependencies += Resolve-DependenciesInScriptProperty $post_install -IncludeInstalled:$IncludeInstalled
    }

    end { return $dependencies | Select-Object -Unique }
}

}
