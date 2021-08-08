if ([String]::IsNullOrEmpty($MyInvocation.PSScriptRoot)) {
    Write-Error 'This script should not be called directly! It has to be imported from a buckets test file!'
    exit 1
}

Describe 'Style constraints for non-binary project files' {
    # gather all files except '*.exe', '*.zip', or any .git repository files
    $files = @(
        $repo_files |
            Where-Object { $_.FullName -inotmatch $($project_file_exclusions -join '|') } |
            Where-Object { $_.FullName -inotmatch '(.exe|.zip|.dll)$' } |
            Where-Object { $_.FullName -inotmatch '(unformated)' }
    )

    $files_exist = ($files.Count -gt 0)

    It $('non-binary project files exist ({0} found)' -f $files.Count) -Skip:$(!$files_exist) {
        if ($files.Count -eq 0) { throw 'No non-binary project were found' }
    }

    It 'files do not contain leading UTF-8 BOM or UTF-16' -Skip:$(!$files_exist) {
        # UTF-8 BOM == 0xEF 0xBB 0xBF
        # UTF-16 BE == 0xFE 0xFF
        # UTF-16 LE == 0xFF 0xFE
        # see http://www.powershellmagazine.com/2012/12/17/pscxtip-how-to-determine-the-byte-order-mark-of-a-text-file @@ https://archive.is/RgT42
        # ref: http://poshcode.org/2153 @@ https://archive.is/sGnnu
        $badFiles = @()

        foreach ($file in $files) {
            $splat = @{
                'LiteralPath' = $file.FullName
                'TotalCount'  = 3
            }
            # PowerShell Core (6.0+) '-Encoding byte' is replaced by '-AsByteStream'
            if ((Get-Command Get-Content).Parameters.ContainsKey('AsByteStream')) {
                $splat.Add('AsByteStream', $true)
            } else {
                $splat.Add('Encoding', 'Byte')
            }
            $content = [char[]](Get-Content @splat) -join ''

            foreach ($prohibited in @('\xEF\xBB\xBF', '\xFF\xFE', '\xFE\xFF')) {
                if ([Regex]::Match($content, "(?ms)^$prohibited").Success) {
                    $badFiles += $file.FullName
                    break
                }
            }
        }

        if ($badFiles.Count -gt 0) {
            throw "The following files have utf-8 BOM or utf-16: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }

    It 'files end with a 1 newline' -Skip:$(!$files_exist) {
        $badFiles = @()

        foreach ($file in $files) {
            # Ignore previous TestResults.xml
            if ($file.Name -eq 'TestResults.xml') { continue }

            $string = [System.IO.File]::ReadAllText($file.FullName)
            # Check for the only 1 newline at the end of the file
            if (($string.Length -gt 0) -and (($string[-1] -ne "`n") -or ($string[-3] -eq "`n"))) {
                $badFiles += $file.FullName
            }
        }

        if ($badFiles.Count -gt 0) {
            throw "The following files do not end with a newline or with multiple empty lines: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }

    It 'file newlines are CRLF' -Skip:$(!$files_exist) {
        $badFiles = @()

        foreach ($file in $files) {
            $content = Get-Content $file.FullName -Raw
            if (!$content) { throw "File contents are null: $($file.FullName)" }

            $lines = [Regex]::Split($content, '\r\n')

            for ($i = 0; $i -lt $lines.Count; ++$i) {
                if ([Regex]::Match($lines[$i], '\r|\n').Success ) {
                    $badFiles += $file.FullName
                    break
                }
            }
        }

        if ($badFiles.Count -gt 0) {
            throw "The following files have non-CRLF line endings: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }

    It 'files have no lines containing trailing whitespace' -Skip:$(!$files_exist) {
        $badLines = @()

        foreach ($file in $files) {
            # Ignore previous TestResults.xml
            if ($file.Name -eq 'TestResults.xml') { continue }

            $lines = [System.IO.File]::ReadAllLines($file.FullName)

            for ($i = 0; $i -lt $lines.Count; ++$i) {
                if ($lines[$i] -match '\s+$') {
                    $badLines += "File: $($file.FullName), Line: $($i + 1)"
                }
            }
        }

        if ($badLines.Count -gt 0) {
            throw "The following $($badLines.Count) lines contain trailing whitespace: `r`n`r`n$($badLines -join "`r`n")"
        }
    }

    It 'any leading whitespace consists only of spaces (excepting makefiles)' -Skip:$(!$files_exist) {
        $badLines = @()

        foreach ($file in $files) {
            if ($file.Name -imatch '^\.?makefile$') { continue }

            $lines = [System.IO.File]::ReadAllLines($file.FullName)

            for ($i = 0; $i -lt $lines.Count; ++$i) {
                if ($lines[$i] -notmatch '^[ ]*(\S|$)') {
                    $badLines += "File: $($file.FullName), Line: $($i + 1)"
                }
            }
        }

        if ($badLines.Count -gt 0) {
            throw "The following $($badLines.Count) lines contain TABs within leading whitespace: `r`n`r`n$($badLines -join "`r`n")"
        }
    }
}
