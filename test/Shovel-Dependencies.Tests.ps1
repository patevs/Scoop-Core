. "$PSScriptRoot\Scoop-TestLib.ps1"
. "$PSScriptRoot\..\lib\core.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"
. "$PSScriptRoot\..\lib\Dependencies.ps1"

Describe 'Manifest Dependencies' -Tag 'Scoop' {
    BeforeAll {
        $working_dir = (setup_working 'manifest' | Resolve-Path).Path

        Mock Test-HelperInstalled { return $false }
    }

    It 'Get URL dependencies' {
        $manifest = ConvertFrom-Manifest -LiteralPath "$working_dir\bucket\url_deps.json"
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '64bit'
        $deps | Should -Be @('7zip')

        $manifest.architecture.'32bit'.url = 'https://cosi.com/alfa.tar.zst'
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('7zip', 'zstd')

        $manifest.architecture.'32bit'.url = 'https://cosi.com/alfa.msi'
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('lessmsi')

        $manifest | Add-Member -MemberType 'NoteProperty' -name 'innosetup' -Value $true
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('lessmsi', 'innounp')

        Mock get_config { return $true } -ParameterFilter { $name -eq 'INNOSETUP_USE_INNOEXTRACT' }
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '64bit'
        $deps | Should -Be @('7zip', 'innoextract')
    }

    It 'Get script dependencies' {
        $manifest = ConvertFrom-Manifest -LiteralPath "$working_dir\bucket\url_deps.json"
        $manifest | Add-Member -MemberType 'NoteProperty' -Name 'pre_install' -Value @(
            'Expand-7zipArchive -Path ''cosi'' -Removal'
        )

        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('7zip')

        $manifest.pre_install = 'Expand-ZstdArchive -Removal -Path '''''
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('7zip', 'zstd')

        $manifest.pre_install = 'Expand-DarkArchive -Removal -Path '''''
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('dark')

        $manifest.pre_install = $null
        $manifest | Add-Member -MemberType 'NoteProperty' -Name 'post_install' -Value 'Expand-MsiArchive -Removal -Path '''''
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('lessmsi')

        # innosetup -UseInnoextract
        Mock get_config { return $false } -ParameterFilter { $name -eq 'INNOSETUP_USE_INNOEXTRACT' }
        $manifest.post_install = $null
        $manifest | Add-Member -MemberType 'NoteProperty' -Name 'installer' -Value @{
            'script' = @('Expand-InnoArchive -Path cosi -UseInnoextract')
        }
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('innoextract')

        # innosetup > innounp|innoextract
        $manifest.installer = $null
        $manifest | Add-Member -MemberType 'NoteProperty' -Name 'innosetup' -Value $true
        Mock get_config { return $true } -ParameterFilter { $name -eq 'INNOSETUP_USE_INNOEXTRACT' }
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('innoextract')
        Mock get_config { return $false } -ParameterFilter { $name -eq 'INNOSETUP_USE_INNOEXTRACT' }
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('innounp')

        # No dependencies
        $manifest.innosetup = $null
        $manifest.pre_install = 'Expand-ZstdArchive-Removal -Path '''''
        $manifest.installer = $null
        $manifest.post_install = $null
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @()
    }

    It 'Depends property' {
        $manifest = ConvertFrom-Manifest -LiteralPath "$working_dir\bucket\url_deps.json"
        $manifest | Add-Member -MemberType 'NoteProperty' -Name 'depends' -Value @(
            'cosi',
            'mysql'
        )
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @('cosi', 'mysql')

        $manifest.depends = @()
        $deps = Get-ManifestDependencies -Manifest $manifest -Architecture '32bit'
        $deps | Should -Be @()
    }
}
