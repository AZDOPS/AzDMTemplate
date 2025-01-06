param(
    $AzDMRoot = $AZDMGlobalConfig['azdm_core']['rootfolder'],
    $AzDMRootConfigFile = $AZDMGlobalConfig['azdm_core']['rootfolderconfigfile']
)

Describe "Default config file: settings.json" {
    Context 'Valid and required keys should be in place' {
        BeforeAll {
            $configJsonPath = Split-Path -Path $AzDMRoot
            $configJson = Get-Content (Join-Path $configJsonPath -ChildPath 'settings.json') | ConvertFrom-Json
        }

        It 'Root folder should be a valid folder' {
            Test-Path $AzDMRoot -PathType Container | Should -BeTrue
        }
        It 'Settings config file must contain base key azdm_core'  {
            @($configJson | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) | Should -Contain 'azdm_core'
        }
        
        It 'Settings config file must contain key azdm_core\rootfolder'  {
            @($configJson.azdm_core | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) | Should -Contain 'rootfolder'
        }
    }
}

Describe "Default config file: $AzDMRootConfigFile" {
    Context 'Valid and required root keys should be in place' {
        BeforeDiscovery {
            $testCases = @(
                @{
                    Required = $true
                    Setting  = 'core'
                    Type = 'PSCustomObject'
                },
                @{
                    Required = $true
                    Setting  = 'organization'
                    Type = 'PSCustomObject'
                }
            )
        }

        BeforeAll {
            $rootConf = Get-Content $AzDMRootConfigFile | ConvertFrom-Json
            $rootProps = $rootConf | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
        }

        It 'Root config file must contain base key <_.Setting>' -TestCases $testCases {
            $rootProps | Should -Contain $_.Setting
        }
    }

    Context 'Core config should be set and valid' {
        BeforeDiscovery {
            $testCases = @(
                @{
                    Required = $true
                    Setting  = 'excludeProjects'
                    Type = 'Object[]'
                }
            )
        }

        BeforeAll {
            $coreConf = Get-Content $AzDMRootConfigFile | ConvertFrom-Json
            $coreProps = $coreConf.core | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
        }

        It 'Root config file must contain key <_.Setting>' -TestCases $testCases {
            $coreProps | Should -Contain $_.Setting
        }

        It 'Root config key <_.Setting> should be of type <_.Type>' -TestCases $testCases {
            $coreConf.core."$($_.Setting)".GetType().Name | Should -Be $_.Type 
        }
    }

    Context 'Organization config should be set and valid' {
        BeforeDiscovery {
            $testCases = @(
                @{
                    Required = $true
                    Setting  = 'security'
                    Type = 'PSCustomObject'
                },
                @{
                    Required = $true
                    Setting  = 'project'
                    Type = 'PSCustomObject'
                },
                @{
                    Required = $true
                    Setting  = 'repos'
                    Type = 'PSCustomObject'
                },
                @{
                    Required = $true
                    Setting  = 'pipelines'
                    Type = 'PSCustomObject'
                },
                @{
                    Required = $true
                    Setting  = 'artifacts'
                    Type = 'PSCustomObject'
                }
            )
        }

        BeforeAll {
            $orgConf = Get-Content $AzDMRootConfigFile | ConvertFrom-Json
            $orgProps = $orgConf.organization | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
        }

        It 'Root config file must contain key <_.Setting>' -TestCases $testCases {
            $orgProps | Should -Contain $_.Setting
        }

        It 'Root config key <_.Setting> should be of type <_.Type>' -TestCases $testCases {
            $orgConf.organization."$($_.Setting)" | Should -BeOfType $_.Type 
        }
    }
}
