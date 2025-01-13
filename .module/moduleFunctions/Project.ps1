function mergeProjectSetting {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory)]
        [string]$Project
    )

    [hashtable]$baseProjectSettings = $AZDMProjectSettings
    $baseProjectSettings['Name'] = $Project
    
    $pathToProject = Join-Path -Path $AZDMGlobalConfig['azdm_core']['rootfolder'] -ChildPath $Project 
    
    $projectLevelConfigName = Join-Path -Path $pathToProject -ChildPath "$Project.json"
    if (Test-Path -Path $projectLevelConfigName) {
        $baseProjectSettings['FileList'] += $projectLevelConfigName
        # We have a base project config. Continue downwards
        $projectLevelConfig = Get-Content -Path $projectLevelConfigName | ConvertFrom-Json -AsHashtable
        
        if (-Not $projectLevelConfig.Keys -contains 'project') {
            # No project config. Return the base object.
        }
        else {
            if ($projectLevelConfig.Keys -contains 'defaults') {
                foreach ($k in $projectLevelConfig['defaults'].Keys) {
                    if ($baseProjectSettings.Keys -contains $k) {
                        $baseProjectSettings[$k] = $projectLevelConfig['defaults'][$k]
                    }
                }
            }
        }
    }

    $baseProjectSettings
}

function createProject {
    [CmdletBinding()]
    param (
        [hashtable]$ProjectSetting
    )

    $createParams = matchParameter -FunctionName New-ADOPSProject -Hashtable $ProjectSetting
    New-ADOPSProject @createParams -Wait
    
    # Set initial security
    $securitySetting = mergeSecuritySetting -Project $ProjectSetting['Name']
    updateGroupSecurityMember -SecuritySetting $securitySetting
}


function updateProject {
    [CmdletBinding()]
    param (
        [hashtable]$ProjectSetting
    )

    $existingProject = Get-ADOPSProject -Name $ProjectSetting['Name']

    if ($null -eq $existingProject) {
        throw "$($ProjectSetting['Name']) not found."
    }
    
    $updateDiff = diffCheckProject -ProjectSetting $ProjectSetting -ExistingProject $existingProject

    Write-Host "Update project:`n$($ProjectSetting | ConvertTo-Json -Depth 10)"
    
    $matchChanges = matchDifflist -FunctionName Set-ADOPSProject -DiffList $updateDiff
    Set-ADOPSProject -ProjectName $ProjectSetting['Name'] -Wait @matchChanges

    # Update security
    $securitySetting = mergeSecuritySetting -Project $ProjectSetting['Name']
    updateGroupSecurityMember -SecuritySetting $securitySetting
}

function diffCheckProject {
    [CmdletBinding()]
    param(
        [hashtable]$ProjectSetting,
        $ExistingProject,
        [switch]$IncludeEqual
    )

    [array]$diffList = @()

    # Unfortunately there is no easy way to compare this. For now, lets do it manually.
    ## Easy settings:
    [string[]]$easySettings = 'Name', 'Description', 'Visibility'
    foreach($setting in $easySettings) {
        if ((compareNullString "$($ProjectSetting[$setting])" "-ne" "$($existingProject.$($setting))") -or ($IncludeEqual)) {
            $diffList += @{
                Setting = $setting
                AzDMConfiguredValue = $ProjectSetting[$setting]
                AzureDevOpsValue = $existingProject.$($setting)
            }
        }
    }

    $aditionalDetails = (Invoke-ADOPSRestMethod -Uri  "$($existingProject.url)/properties?api-version=7.2-preview.1").value
    ## SourceControlType
    if (-Not ($null -eq ($aditionalDetails.Where({$_.name -eq 'System.SourceControlTfvcEnabled'})).value)) {
        $SourceControlType = 'Tfvc'
    }
    elseif (-Not ($null -eq ($aditionalDetails.Where({$_.name -eq 'System.SourceControlGitEnabled'})).value)) {
        $SourceControlType = 'Git'
    }
    else {
        $SourceControlType = 'Git'
    }
    if (($ProjectSetting['SourceControlType'].ToLower() -ne $SourceControlType.ToLower()) -or ($IncludeEqual)) {
        $diffList += @{
            Setting = 'SourceControlType'
            AzDMConfiguredValue = $ProjectSetting['SourceControlType']
            AzureDevOpsValue = $SourceControlType
        }
    }

    ## ProcessTypeName
    $ProcessTypeName = ($aditionalDetails.Where({$_.name -eq 'System.Process Template'})).value
    if ((compareNullString "$($ProjectSetting['ProcessTypeName'])" "-ne" "$ProcessTypeName") -or ($IncludeEqual)) {
        $diffList += @{
            Setting = 'ProcessTypeName'
            AzDMConfiguredValue = $ProjectSetting['ProcessTypeName']
            AzureDevOpsValue = $ProcessTypeName
        }
    }
    
    $diffList
}
