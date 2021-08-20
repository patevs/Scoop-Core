'core', 'Helpers', 'install', 'decompress' | ForEach-Object {
    . (Join-Path $PSScriptRoot "$_.ps1")
}

# Return array of plain text values to be resolved
function Get-ManifestDependencies {
    param($Manifest, $Architecture)

    process {
        $result = @()

        # TODO: Support requirements property
        # Direct dependencies defined in manifest
        if ($Manifest.depends) { $result += $Manifest.depends }

        $pre_install = arch_specific 'pre_install' $Manifest $Architecture
        $installer = arch_specific 'installer' $Manifest $Architecture
        $post_install = arch_specific 'post_install' $Manifest $Architecture

        # Indirect dependencies
        $result += Get-UrlDependencies -Manifest $Manifest -Architecture $Architecture
        $result += Get-ScriptDependencies -ScriptProperty ($pre_install + $installer.script + $post_install)

        return $result | Select-Object -Unique
    }
}

# TODO: More pretty implementation
function Get-ScriptDependencies {
    param($ScriptProperty)

    process {
        $dependencies = @()
        $s = $ScriptProperty

        if ($ScriptProperty -is [Array]) { $s = $ScriptProperty -join "`n" }

        # Exit immediatelly if there are no expansion functions
        if ([String]::IsNullOrEmpty($s)) { return $dependencies }
        if ($s -notlike '*Expand-*Archive *') { return $dependencies }

        if (($s -like '*Expand-DarkArchive *') -and !(Test-HelperInstalled -Helper 'Dark')) { $dependencies += 'dark' }
        if (($s -like '*Expand-MsiArchive *') -and !(Test-HelperInstalled -Helper 'Lessmsi')) { $dependencies += 'lessmsi' }

        # 7zip
        if (($s -like '*Expand-7zipArchive *') -and !(Test-HelperInstalled -Helper '7zip')) {
            # Do not add if 7ZIPEXTRACT_USE_EXTERNAL is used
            if (($false -eq (get_config '7ZIPEXTRACT_USE_EXTERNAL' $false))) {
                $dependencies += '7zip'
            }
        }

        # Inno; innoextract or innounp
        if ($s -like '*Expand-InnoArchive *') {
            # Use innoextract
            if ((get_config 'INNOSETUP_USE_INNOEXTRACT' $false) -or ($s -like '* -UseInnoextract*')) {
                if (!(Test-HelperInstalled -Helper 'InnoExtract')) { $dependencies += 'innoextract' }
            } else {
                # Default innounp
                if (!(Test-HelperInstalled -Helper 'Innounp')) { $dependencies += 'innounp' }
            }
        }

        # zstd
        if (($s -like '*Expand-ZstdArchive *') -and !(Test-HelperInstalled -Helper 'Zstd')) {
            # Ugly, unacceptable and horrible patch to cover the tar.zstd use cases
            if (!(Test-HelperInstalled -Helper '7zip')) { $dependencies += '7zip' }
            $dependencies += 'zstd'
        }

        return $dependencies | Select-Object -Unique
    }
}

function Get-UrlDependencies {
    param($Manifest, $Architecture)

    process {
        $dependencies = @()
        $urls = url $Manifest $Architecture

        if ((Test-7zipRequirement -URL $urls) -and !(Test-HelperInstalled -Helper '7zip')) { $dependencies += '7zip' }
        if ((Test-LessmsiRequirement -URL $urls) -and !(Test-HelperInstalled -Helper 'Lessmsi')) { $dependencies += 'lessmsi' }

        if ($manifest.innosetup) {
            if (get_config 'INNOSETUP_USE_INNOEXTRACT' $false) {
                if (!(Test-HelperInstalled -Helper 'Innoextract')) { $dependencies += 'innoextract' }
            } else {
                if (!(Test-HelperInstalled -Helper 'Innounp')) { $dependencies += 'innounp' }
            }
        }

        if ((Test-ZstdRequirement -URL $urls) -and !(Test-HelperInstalled -Helper 'Zstd')) {
            # Ugly, unacceptable and horrible patch to cover the tar.zstd use cases
            if (!(Test-HelperInstalled -Helper '7zip')) { $dependencies += '7zip' }
            $dependencies += 'zstd'
        }

        return $dependencies | Select-Object -Unique
    }
}
