param(
    $AzDMRoot = $AZDMGlobalConfig['azdm_core']['rootfolder'],
    $AzDMRootConfigFile = $AZDMGlobalConfig['azdm_core']['rootfolderconfigfile']
)

Describe 'Projects' {
    BeforeDiscovery {
        $testCases = @()
        Get-ChildItem $AzDMRoot -Directory | ForEach-Object {
            if ($_.Name -notin $AZDMGlobalConfig['core']['excludeProjects']) {
                $testCases += @{
                    Name = $_.Name
                    FullName = $_.FullName
                }
            }
        }
    }

    Context 'Naming standards should be followed' {
        # https://learn.microsoft.com/en-us/azure/devops/organizations/settings/naming-restrictions?view=azure-devops#project-names
        
        It 'Names should not be longer than 64 chars - <_.Name>' -TestCases $testCases {
            $_.Name.Length | Should -BeLessOrEqual 64
        }
        It 'Names should follow required characters - <_.Name>' -TestCases $testCases {
            $_.Name | Should -Match '^[^_.][^\/:*?"<>;#$*{},+=[\]|]{1,63}[^.\/:*?"<>;#$*{},+=[\]|]$' -Because 'See https://learn.microsoft.com/en-us/azure/devops/organizations/settings/naming-restrictions?view=azure-devops#project-names'
        }
        It 'Names should not be a reserved name - <_.Name>' -TestCases $testCases {
            $reservedNames = @(
                'App_Browsers',
                'App_code',
                'App_Data',
                'App_GlobalResources',
                'App_LocalResources',
                'App_Themes',
                'App_WebResources',
                'bin',
                'web.config',
                'AUX',
                'COM1',
                'COM2',
                'COM3',
                'COM4',
                'COM5',
                'COM6',
                'COM7',
                'COM8',
                'COM9',
                'COM10'
                'CON',
                'DefaultCollection',
                'LPT1',
                'LPT2',
                'LPT3',
                'LPT4',
                'LPT5',
                'LPT6',
                'LPT7',
                'LPT8',
                'LPT9',
                'NUL',
                'PRN',
                'SERVER',
                'SignalR',
                'WEB'

            )
            $_.Name | Should -Not -BeIn $reservedNames
        }
    }

    Context 'Json files and data' {
        It 'Json file should be in place - <_.Name>' -TestCases $testCases {
            $fullPath = Join-Path -Path $_.FullName -ChildPath "$($_.Name).json"
            Test-Path -Path $fullPath -PathType Leaf | Should -Be $true -Because 'We need the projectName.json file to set up our project.'
        }
        It 'Json file should contain the needed settings - <_.Name>' -TestCases $testCases {
            $fullPath = Join-Path -Path $_.FullName -ChildPath "$($_.Name).json"
            $projectSettings = Get-Content $fullPath | ConvertFrom-Json
            $projectSettings.project | Should -Not -Be $null -Because 'projectName.json needs to contain the project key.'
        }
    } 
}