param(
    $AzDMRoot = $AZDMGlobalConfig['azdm_core']['rootfolder'],
    $AzDMRootConfigFile = $AZDMGlobalConfig['azdm_core']['rootfolderconfigfile']
)

Describe 'Projects' {
    BeforeDiscovery {
        $testCases = @()
        Get-ChildItem $AzDMRoot -Recurse -Filter *.repos.json | ForEach-Object {
            if ($_.Name.Split('.')[0] -notin $AZDMGlobalConfig['core']['excludeProjects']) {
                $testCases += @{
                    Name = $_.Name
                    FullName = $_.FullName
                    Data = (Get-Content $_ | ConvertFrom-Json)
                }
            }
        }
    }

    Context 'Naming standards should be followed - <_.Name>' -ForEach $testCases {
        # https://learn.microsoft.com/en-us/azure/devops/organizations/settings/naming-restrictions?view=azure-devops#azure-repos-git
        
        It 'Repo names should not be longer than 64 chars - <_>' -TestCases $_.Data.'repos.names' {
            $_.Length | Should -BeLessOrEqual 64
        }
        It 'Names should follow required characters - <_>' -TestCases $_.Data.'repos.names' {
            $_ | Should -Match '^[^_.][^\/:*?"<>;#$*{},+=[\]|]{1,63}[^.\/:*?"<>;#$*{},+=[\]|]$' -Because 'See https://learn.microsoft.com/en-us/azure/devops/organizations/settings/naming-restrictions?view=azure-devops#project-names'
        }
        It 'Names should not be a reserved name - <_>' -TestCases $_.Data.'repos.names' {
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
            $_ | Should -Not -BeIn $reservedNames
        }
    }
}