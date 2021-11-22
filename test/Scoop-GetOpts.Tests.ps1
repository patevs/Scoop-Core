. "$PSScriptRoot\Scoop-TestLib.ps1"
. "$PSScriptRoot\..\lib\getopt.ps1"

Describe 'getopt' -Tag 'Scoop' {
    It 'handle short option with required argument missing' {
        $null, $null, $err = Resolve-GetOpt '-x' 'x:' ''
        $err | Should -Be 'Option -x requires an argument.'

        $null, $null, $err = Resolve-GetOpt '-xy' 'x:y' ''
        $err | Should -Be 'Option -x requires an argument.'
    }

    It 'handle long option with required argument missing' {
        $null, $null, $err = Resolve-GetOpt '--arb' '' 'arb='
        $err | Should -Be 'Option --arb requires an argument.'
    }

    It 'handle unrecognized short option' {
        $null, $null, $err = Resolve-GetOpt '-az' 'a' ''
        $err | Should -Be 'Option -z not recognized.'
    }

    It 'handle unrecognized long option' {
        $null, $null, $err = Resolve-GetOpt '--non-exist' '' ''
        $err | Should -Be 'Option --non-exist not recognized.'

        $null, $null, $err = Resolve-GetOpt '--global', '--another' 'abc:de:' 'global', 'one'
        $err | Should -Be 'Option --another not recognized.'
    }

    It 'remaining args returned' {
        $opt, $rem, $err = Resolve-GetOpt '-g', 'rem' 'g' ''
        $err | Should -BeNullOrEmpty
        $opt.g | Should -BeTrue
        $rem | Should -Not -BeNullOrEmpty
        $rem.length | Should -Be 1
        $rem[0] | Should -Be 'rem'
    }

    It 'get a long flag and a short option with argument' {
        $a = '--global -a 32bit test' -split ' '
        $opt, $rem, $err = Resolve-GetOpt $a 'ga:' 'global', 'arch='

        $err | Should -BeNullOrEmpty
        $opt.global | Should -BeTrue
        $opt.a | Should -Be '32bit'
    }

    It 'handles regex characters' {
        $a = '-?'
        { $opt, $rem, $err = Resolve-GetOpt $a 'ga:' 'global' 'arch=' } | Should -Not -Throw
        { $null, $null, $null = Resolve-GetOpt $a '?:' 'help' | Should -Not -Throw }
    }

    It 'handles short option without required argument' {
        $null, $null, $err = Resolve-GetOpt '-x' 'x' ''
        $err | Should -BeNullOrEmpty
    }

    It 'handles long option without required argument' {
        $opt, $null, $err = Resolve-GetOpt '--long-arg' '' 'long-arg'
        $err | Should -BeNullOrEmpty
        $opt.'long-arg' | Should -BeTrue
    }

    It 'handles long option with required argument' {
        $opt, $null, $err = Resolve-GetOpt '--long-arg', 'test' '' 'long-arg='
        $err | Should -BeNullOrEmpty
        $opt.'long-arg' | Should -Be 'test'
    }
}
