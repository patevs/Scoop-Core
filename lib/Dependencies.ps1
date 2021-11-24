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

function Get-ApplicationDependency {
    [CmdletBinding()]
    param([String] $ApplicationQuery, [String] $Architecture, [Switch] $IncludeInstalled)

    begin {
        $resolved = New-Object System.Collections.ArrayList
    }

    process {
        Resolve-SpecificQueryDependency -ApplicationQuery $ApplicationQuery -Architecture $Architecture -Resolved $resolved -Unresolved @() -IncludeInstalled:$IncludeInstalled
    }

    end {
        if ($resolved.Count -eq 1) { return @() } # No dependencies
        return $resolved[0..($resolved.Count - 2)]
    }
}

function Resolve-SpecificQueryDependency {
    [CmdletBinding()]
    param(
        [String] $ApplicationQuery,
        [String] $Architecture,
        [System.Collections.ArrayList] $Resolved, # [out]
        [System.Object[]] $Unresolved, # [out]
        [Switch] $IncludeInstalled
    )

    process {
        $resolvedInformation = $null
        try {
            $resolvedInformation = Resolve-ManifestInformation -ApplicationQuery $ApplicationQuery
        } catch {
            Write-UserMessage -Message "Cannot resolve '$ApplicationQuery'" -Err
            return
        }
        $Unresolved += $ApplicationQuery
        $bucket = $resolvedInformation.Bucket
        $appName = $resolvedInformation.ApplicationName

        if (!$resolvedInformation.ManifestObject) {
            if ($bucket -and ((Get-LocalBucket) -notcontains $bucket)) {
                Write-UserMessage -Message "Bucket '$bucket' not installed. Add it with 'scoop bucket add $bucket' or 'scoop bucket add $bucket <repo>'." -Warning
            }

            $mes = "Could not find manifest for '$appName'"
            if ($bucket) { "$mes from '$bucket' bucket" }

            throw [ScoopException] $mes # TerminatingError thrown
        }

        $deps = @(Resolve-InstallationDependency -Manifest $resolvedInformation.ManifestObject -Architecture $Architecture -IncludeInstalled:$IncludeInstalled) + `
        @(Resolve-DependsProperty -Manifest $resolvedInformation.ManifestObject) | Select-Object -Unique

        foreach ($dep in $deps) {
            if ($Resolved -notcontains $dep) {
                if ($Unresolved -contains $dep) {
                    throw [ScoopException] "Circular dependency detected: '$appName' -> '$dep'." # TerminatingError thrown
                }
                Resolve-SpecificQueryDependency -ApplicationQuery $dep -Architecture $Architecture -Resolved $Resolved -Unresolved $Unresolved -IncludeInstalled:$IncludeInstalled
            }
        }
        $Resolved.Add($appName) | Out-Null
        $Unresolved = $Unresolved -ne $appName # Remove from unresolved
    }
}

function __alfa {
}
