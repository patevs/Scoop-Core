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
    <#
    .SYNOPSIS
        Process manifest object and return all possible dependencies as simple array, which is intended to be resolved.
    .DESCRIPTION
        Returns dependencies detected vis:
           Depends property
           Dependencies for installation types analyzed from URL/specific properties (innounp, lessmsi, 7zip, zstd, ...)
           Dependencies used in scripts (pre_install, installer.script, ...) (lessmsi, 7zip, zstd, ...)
    .PARAMETER Architecture
        Specifies the desired architecture to use while processing manifest properties.
    .PARAMETER IncludeInstalled
        Specifies to include include applications/dependencies in final resolved array even when they are already installed (locally, globally).
    #>
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

function Resolve-SpecificQueryDependency {
    <#
    .SYNOPSIS
        Resolve the application based on the query and all dependencies.
    .DESCRIPTION
        Produce the arraylist of Resolved objects, where the latest one will be the application itself.
    .PARAMETER ApplicationQuery
        Specifies the application query to be resolved.
    .PARAMETER Architecture
        Specifies the desired architecture to use while processing manifest properties.
    .PARAMETER Resolved
        Specifies the arraylist of already resolved objects. Mainly used as [out]
    .PARAMETER Unresolved
        Specifies the arraylist/array of unresolved objects. Mainly used as [out]
    .PARAMETER IncludeInstalled
        Specifies to include include applications or dependencies in final resolved array even when they are already installed (locally, globally).
    .PARAMETER Manifest
        Specifies to use explicit manifest instead of resolving.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $ApplicationQuery,
        [String] $Architecture,
        [System.Collections.ArrayList] $Resolved, # [out] ArrayList of Resolve-ManifestInformation objects
        [System.Collections.Arraylist] $Unresolved, # [out] ArrayList of strings
        [Switch] $IncludeInstalled,
        $Manifest
    )

    $information = $null
    if ($Manifest) {
        $information = @{}
        $information.ApplicationName = $ApplicationQuery
        $information.ManifestObject = $Manifest
    } else {
        try {
            $information = Resolve-ManifestInformation -ApplicationQuery $ApplicationQuery
        } catch {
            throw [ScoopException] "'$ApplicationQuery' -> $($_.Exception.Message)"
        }
    }

    $deps = @(Resolve-InstallationDependency -Manifest $information.ManifestObject -Architecture $Architecture -IncludeInstalled:$IncludeInstalled) + `
    @(Resolve-DependsProperty -Manifest $information.ManifestObject) | Select-Object -Unique

    foreach ($dep in $deps) {
        if ($Resolved.ApplicationName -notcontains $dep) {
            if ($Unresolved -contains $dep) {
                throw [ScoopException] "Circular dependency detected: '$($information.ApplicationName)' -> '$dep'." # TerminatingError thrown
            }

            Resolve-SpecificQueryDependency -ApplicationQuery $dep -Architecture $Architecture -Resolved $Resolved -Unresolved $Unresolved -IncludeInstalled:$IncludeInstalled
        } else {
            Write-UserMessage -Message "[$ApplicationQuery] There is already registered dependency '$(($Resolved | Where-Object -Property 'ApplicationName' -EQ -Value $dep).Print)' for '$dep'" -Info
        }
    }
    $Resolved.Add($information) | Out-Null
    $Unresolved = $Unresolved -ne $ApplicationQuery # Remove from unresolved
}

function Get-ApplicationDependency {
    <#
    .SYNOPSIS
        Wrapper arround Resolve-SpecificQueryDependency.
    .DESCRIPTION
        Return hashtable with Application (self resolved object) and Deps (all required dependencies)
    .PARAMETER ApplicationQuery
        Specifies the string to be resolved.
    .PARAMETER Architecture
        Specifies the desired architecture to use while processing manifest properties.
    .PARAMETER IncludeInstalled
        Specifies to include include applications in final resolved array even when they are already installed (locally, globally).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param([String] $ApplicationQuery, [String] $Architecture, [Switch] $IncludeInstalled)

    $resolved = New-Object System.Collections.ArrayList
    $unresolved = @()
    $deps = @()
    $self = $null

    Resolve-SpecificQueryDependency -ApplicationQuery $ApplicationQuery -Architecture $Architecture -Resolved $resolved -Unresolved $unresolved -IncludeInstalled:$IncludeInstalled

    if ($resolved.Count -eq 1) {
        $self = $Resolved[0]
    } else {
        $self = $Resolved[($Resolved.Count - 1)]
        $deps = $Resolved[0..($Resolved.Count - 2)]
    }

    return @{
        'Application' = $self
        'Deps'        = $deps
    }
}

function Resolve-MultipleApplicationDependency {
    <#
    .SYNOPSIS
        Properly process and sort dependencies and applications to be installed/processed in future.
    .PARAMETER Applications
        Specifies the list of strings to be resolved.
    .PARAMETER Architecture
        Specifies the desired architecture to use while processing manifest properties.
    .PARAMETER IncludeInstalledDeps
        Specifies to include include dependencies in final resolved array even when they are already installed (locally, globally).
    .PARAMETER IncludeInstalledApps
        Specifies to include include applications in final resolved array even when they are already installed (locally, globally).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param([System.Object[]] $Applications, [String] $Architecture, [Switch] $IncludeInstalledDeps, [Switch] $IncludeInstalledApps)

    begin {
        $toInstall = @()
        $failed = @()
    }

    process {
        foreach ($app in $Applications) {
            $deps = @{}
            try {
                $deps = Get-ApplicationDependency -ApplicationQuery $app -Architecture $Architecture -IncludeInstalled:($IncludeInstalledDeps -or $IncludeInstalledApps)
            } catch {
                Write-UserMessage -Message $_.Exception.Message -Err
                $failed += $app
                continue
            }

            # Application itself
            $s = $deps.Application

            foreach ($dep in $deps.Deps) {
                # TODOOOO: Better handle the different versions
                if ($toInstall.ApplicationName -notcontains $dep.ApplicationName) {
                    $dep | Add-Member -MemberType 'NoteProperty' -Name 'Dependency' -Value $s.ApplicationName
                    if ($IncludeInstalledDeps -or !(installed $dep.ApplicationName)) {
                        $toInstall += $dep
                    }
                } else {
                    Write-UserMessage -Message "[$app] Dependency entry for $($dep.ApplicationName) already exists as: '$(($toInstall | Where-Object -Property 'ApplicationName' -EQ -Value $dep.ApplicationName).Print))'" -Info
                }
            }

            # TODOOOO: Better handle the different versions
            if ($toInstall.ApplicationName -notcontains $s.ApplicationName) {
                $s | Add-Member -MemberType 'NoteProperty' -Name 'Dependency' -Value $false

                if ($IncludeInstalledApps -or !(installed $s.ApplicationName)) {
                    $toInstall += $s
                }
            } else {
                Write-UserMessage -Message "'$app' was already resolved before as: '$(($toInstall | Where-Object -Property 'ApplicationName' -EQ -Value $s.ApplicationName).Print)'" -Info
            }
        }

        return @{
            'Failed'   = $failed
            'Resolved' = $toInstall
        }
    }
}
