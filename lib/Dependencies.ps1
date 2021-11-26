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
    [OutputType([System.Collections.Hashtable])]
    param([String] $ApplicationQuery, [String] $Architecture, [Switch] $IncludeInstalled)

    begin {
        $resolved = New-Object System.Collections.ArrayList
        $unresolved = New-Object System.Collections.ArrayList
    }

    process {
        Resolve-SpecificQueryDependency -ApplicationQuery $ApplicationQuery -Architecture $Architecture -Resolved $resolved -Unresolved $unresolved -IncludeInstalled:$IncludeInstalled
    }

    end {
        if ($resolved.Count -eq 1) {
            return @{
                'Resolved'   = New-Object System.Collections.ArrayList
                'Unresolved' = New-Object System.Collections.ArrayList
            }
        } # No dependencies

        return @{
            'Resolved'   = $resolved[0..($resolved.Count - 2)]
            'Unresolved' = $unresolved
        }
    }
}

function Resolve-SpecificQueryDependency {
    [CmdletBinding()]
    param(
        [String] $ApplicationQuery,
        [String] $Architecture,
        [System.Collections.ArrayList] $Resolved, # [out] ArrayList of Resolve-ManifestInformation objects
        [System.Collections.Arraylist] $Unresolved, # [out] ArrayList of strings
        [Switch] $IncludeInstalled
    )

    process {
        $resolvedInformation = $null
        $Unresolved.Add($ApplicationQuery)
        try {
            $resolvedInformation = Resolve-ManifestInformation -ApplicationQuery $ApplicationQuery
        } catch {
            # Write-UserMessage -Message "Cannot resolve dependency '$ApplicationQuery' ($($_.Exception.Message))" -Err
            return
        }

        # Just array of strings to be resolved
        $deps = @(Resolve-InstallationDependency -Manifest $resolvedInformation.ManifestObject -Architecture $Architecture -IncludeInstalled:$IncludeInstalled) + `
        @(Resolve-DependsProperty -Manifest $resolvedInformation.ManifestObject) | Select-Object -Unique

        foreach ($dep in $deps) {
            if ($Resolved.ApplicationName -notcontains $dep) {
                if ($Unresolved -contains $dep) {
                    throw [ScoopException] "Circular dependency detected: '$($resolvedInformation.ApplicationName)' -> '$dep'." # TerminatingError thrown
                }
                Resolve-SpecificQueryDependency -ApplicationQuery $dep -Architecture $Architecture -Resolved $Resolved -Unresolved $Unresolved -IncludeInstalled:$IncludeInstalled
            }
        }
        $Resolved.Add($resolvedInformation) | Out-Null
        $Unresolved.Remove($ApplicationQuery) # Consider self as resolved
    }
}

# Create installation objects for all the dependencies and applications
function Resolve-MultipleApplicationDependency {
    [CmdletBinding()]
    [OutputType([System.Collections.HashTable])]
    param([System.Object[]] $Applications, [String] $Architecture, [Switch] $IncludeInstalled)

    begin {
        $failed = @()
        $result = @()
    }

    process {
        foreach ($app in $Applications) {
            $deps = @()
            try {
                $deps = Get-ApplicationDependency $app $Architecture -IncludeInstalled:$IncludeInstalled
                if ($deps.Unresolved.Count -gt 0) {
                    $failed += $deps.Unresolved
                    throw [ScoopException] "Cannot process dependencies for '$($app)': ($($deps.Unresolved -join ', '))" # TerminatingError thrown
                }
            } catch {
                Write-UserMessage -Message $_.Exception.Message -Err
                continue
            }

            foreach ($dep in $deps.Resolved) {
                if ($result.ApplicationName -notcontains $dep.ApplicationName) {
                    $dep | Add-Member -MemberType 'NoteProperty' -Name 'Dependency' -Value $true
                    $result += $dep
                } else {
                    Write-UserMessage -Message "[$app] Dependency entry for $($dep.ApplicationName) already exists as: '$(($result | Where-Object -Property 'ApplicationName' -EQ -Value $dep.ApplicationName).Print))'" -Info
                }
            }

            if ($result.AppliactionName -notcontains $app) {
                $r = Resolve-ManifestInformation -ApplicationQuery $app
                $r | Add-Member -MemberType 'NoteProperty' -Name 'Dependency' -Value $false
                $result += $r
            }
        }
    }

    end {
        return @{
            'Failed'       = $failed
            'Applications' = $result
        }
    }
}
