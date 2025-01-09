param(
    $AzDMRoot = $AZDMGlobalConfig['azdm_core']['rootfolder'],
    $AzDMRootConfigFile = $AZDMGlobalConfig['azdm_core']['rootfolderconfigfile']
)

Describe 'Projects' {
    BeforeDiscovery {
        $testCases = @()
        Get-ChildItem $AzDMRoot -Recurse -Filter *.artifacts.json | ForEach-Object {
            if ($_.Name.Split('.')[0] -notin $AZDMGlobalConfig['core']['excludeProjects']) {
                $testCases += @{
                    Name = $_.Name
                    FullName = $_.FullName
                    Data = (Get-Content $_ | ConvertFrom-Json)
                }
            }
        }
    }

    # https://learn.microsoft.com/en-us/azure/devops/organizations/settings/naming-restrictions?view=azure-devops#azure-artifacts

    # As of this file creation there are no specific limitations on the artifact feeds themselves, and no required properties to be set.
    # I will leave this file here for future references.
}