@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('Versions', 'Clear-InstalledVersion'),
    @('manifest', 'Resolve-ManifestInformation')
) | ForEach-Object {
    if (!(Get-Command $_[1] -ErrorAction 'Ignore')) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "$($_[0]).ps1")
    }
}

function Install-ScoopApplication {
    [CmdletBinding()]
    param($ResolvedObject, [String] $Architecture, [Switch] $Global, $Suggested, [Switch] $UseCache, [Switch] $CheckHash)

    process {
        $appName = $ResolvedObject.ApplicationName
        $manifest = $ResolvedObject.ManifestObject
        $version = $ResolvedObject.ManifestObject.version

        if ($version -match '[^\w\.\-\+_]') {
            throw [ScoopException] "Invalid manifest|-Manifest version has unsupported character '$($matches[0])'." # TerminatingError thrown
        }

        if ($version -eq 'nightly') {
            $version = nightly_version
            $CheckHash = $false
        }

        if (!(supports_architecture $manifest $Architecture)) {
            throw [ScoopException] "'$appName' does not support $Architecture architecture" # TerminatingError thrown
        }

        Deny-ArmInstallation -Manifest $manifest -Architecture $architecture

        $buc = if ($ResolvedObject.Bucket) { " [$($ResolvedObject.Bucket)]" } else { '' }
        $dep = if ($ResolvedObject.Dependency -ne $false) { " {Dependency for $($ResolvedObject.Dependency)}" } else { '' }

        Write-UserMessage -Message "Installing '$appName' ($version) [$Architecture]$buc$dep"

        # Show license
        $license = $manifest.license
        if ($license -and ($license -ne 'Unknown')) {
            $id = if ($license.identifier) { $license.identifier } else { $license }
            # Remove [|,]...
            if ($id -like '*...') { $id = $id -replace '[|,]\.{3}' }
            $id = $id -split ','
            $id = $id -split '\|'

            if ($license.url) {
                $s = if ($id.Count -eq 1) { $id } else { $id -join ', ' }
                $toShow = $s + ' (' + $license.url + ')'
            } else {
                $line = if ($id.Count -gt 1) { "`r`n  " } else { '' }
                $id | ForEach-Object {
                    $toShow += "$line$_ (https://spdx.org/licenses/$_.html)"
                }
            }

            Write-UserMessage -Message "By installing you accept following $(pluralize $id.Count 'license' 'licenses'): $toShow" -Warn
        }

        # Variables
        $dir = versiondir $appName $version $Global | Confirm-DirectoryExistence
        $current_dir = current_dir $dir # Save some lines in manifests
        $original_dir = $dir # Keep reference to real (not linked) directory
        $persist_dir = persistdir $appName $Global

        # Suggest installing arm64
        if ((Test-IsArmArchitecture) -and ($Architecture -ne 'arm64') -and ($manifest.'architecture'.'arm64')) {
            Write-UserMessage -Message 'Manifest explicitly supports arm64. Consider to install using arm64 version to achieve best compatibility/performance.' -Success
        }

        # Download and extraction
        Invoke-ManifestScript -Manifest $manifest -ScriptName 'pre_download' -Architecture $Architecture
        # TODOOOOOOOOOO: Extract to better function
        $fname = dl_urls $appName $version $manifest $ResolvedObject.Bucket $Architecture $dir $UseCache $CheckHash

        # Installers
        Invoke-ManifestScript -Manifest $manifest -ScriptName 'pre_install' -Architecture $Architecture
        run_installer $fname $manifest $Architecture $dir $Global
        ensure_install_dir_not_in_path $dir $Global
        $dir = link_current $dir
        create_shims $manifest $dir $Global $Architecture
        create_startmenu_shortcuts $manifest $dir $Global $Architecture
        install_psmodule $manifest $dir $Global
        if ($Global) { ensure_scoop_in_path $Global } # Can assume local scoop is in path
        env_add_path $manifest $dir $Global $Architecture
        env_set $manifest $dir $Global $Architecture

        # Persist data
        persist_data $manifest $original_dir $persist_dir
        #TODOOOO: Eliminate
        persist_permission $manifest $Global

        Invoke-ManifestScript -Manifest $manifest -ScriptName 'post_install' -Architecture $Architecture

        # Save helper files for uninstall and other commands
        Set-ScoopManifestHelperFile -ResolvedObject $ResolvedObject -Directory $dir
        Set-ScoopInfoHelperFile -ResolvedObject $ResolvedObject -Architecture $Architecture -Directory $dir

        if ($manifest.suggest) { $Suggested[$appName] = $manifest.suggest }

        Write-UserMessage -Message "'$appName' ($version) was installed successfully!" -Success

        # Additional info to user
        show_notes $manifest $dir $original_dir $persist_dir

        if ($manifest.changelog) {
            $changelog = $manifest.changelog
            if (!$changelog.StartsWith('http')) { $changelog = friendly_path (Join-Path $dir $changelog) }

            Write-UserMessage -Message "New changes in this release: '$changelog'" -Success
        }
    }
}

function Set-ScoopManifestHelperFile {
    [CmdletBinding()]
    param($ResolvedObject, $Directory)

    process {
        $p = $ResolvedObject.LocalPath
        $name = 'scoop-manifest'

        if ($p -and (Test-Path -LiteralPath $p)) {
            $name = "$name$($p.Extension)"
            $t = Join-Path $Directory $name
            Copy-Item -LiteralPath $ResolvedObject.LocalPath -Destination $t
        } else {
            Write-UserMessage -Message 'Cannot copy local manifest. Creating from object' -Info

            ConvertTo-Manifest -File (Join-Path $Directory "$name.yml") -Manifest $ResolvedObject.ManifestObject
        }
    }
}

function Set-ScoopInfoHelperFile {
    [CmdletBinding()]
    param($ResolvedObject, $Architecture, $Directory)

    process {
        $dep = if ($ResolvedObject.Dependency -ne $false) { $ResolvedObject.Dependency } else { $null }
        $url = if ($ResolvedObject.Url) { $ResolvedObject.Url } else { $ResolvedObject.LocalPath }

        if ($ResolvedObject.Bucket) { $url = $null }

        $info = @{
            'architecture'   = $Architecture
            'bucket'         = $ResolvedObject.Bucket
            'url'            = if ($url) { "$url" } else { $null } # Force string in case of FileInfo
            'dependency_for' = $dep
        }

        $nulls = $info.Keys | Where-Object { $null -eq $info[$_] }
        $nulls | ForEach-Object { $info.Remove($_) } # strip null-valued

        $info | ConvertToPrettyJson | Out-UTF8File -Path (Join-Path $Directory 'scoop-install.json')
    }
}
