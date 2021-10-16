. "$PSScriptRoot\Scoop-TestLib.ps1"
. "$PSScriptRoot\..\lib\json.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"

Describe 'Pretty json formating' -Tag 'Scoop' {
    BeforeAll {
        $format = "$PSScriptRoot\fixtures\format"
        $manifests = Get-ChildItem "$format\formated" -File -Filter '*.json'
    }

    Context 'Beautify manifest' {
        $manifests | ForEach-Object {
            $name = if ($PSVersionTable.PSVersion.Major -gt 5) { $_.Name } else { $_ } # Fix for pwsh

            It "$name" {
                $pretty_json = (parse_json "$format\unformated\$name") | ConvertToPrettyJson
                $correct = (Get-Content "$format\formated\$name") -join "`r`n"
                $correct.CompareTo($pretty_json) | Should Be 0
            }
        }
    }
}
