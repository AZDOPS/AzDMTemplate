function mergeSecuritySetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Project
    )

    try {
        $baseSecurityObject = $AZDMGlobalConfig['organization']['security']['permissions'].Clone()
        $baseSecurityObject.Add('FileList', @($AZDMGlobalConfig['azdm_core']['rootfolderconfigfile']))
    }
    catch {
        $baseSecurityObject = [ordered]@{
            'FileList' = @()
        }
    }

    $baseSecurityObject.Add('Project', $Project)
    
    $pathToProject = Join-Path -Path $AZDMGlobalConfig['azdm_core']['rootfolder'] -ChildPath $Project 
    
    $projectLevelConfigName += Join-Path -Path $pathToProject -ChildPath "$Project.json"
    if (Test-Path -Path $projectLevelConfigName) {
        $baseSecurityObject['FileList'] += $projectLevelConfigName
        # We have a base project config. Continue downwards
        $projectLevelConfig = Get-Content -Path $projectLevelConfigName | ConvertFrom-Json -AsHashtable
        
        if (-Not $projectLevelConfig.Keys -contains 'project') {
            # No project config. Return the base object.
        }

        else {
            if ($projectLevelConfig['project'].Keys -contains 'security') {
                if ($projectLevelConfig['project']['security'].Keys -contains 'Permissions') {
                    foreach ($k in $projectLevelConfig['project']['security']['Permissions'].Keys) {
                        if ($baseSecurityObject.Keys -contains $k) {
                            $baseSecurityObject[$k] += $projectLevelConfig['project']['security']['Permissions'][$k]
                            # Technically we should probably filter this above, but adding and selecting unique is easier.
                            $baseSecurityObject[$k] = $baseSecurityObject[$k] | Select-Object -Unique
                        }
                        else {
                            $baseSecurityObject.Add($k, $projectLevelConfig['project']['security']['Permissions'][$k])
                        }
                    }
                }
            }
        }
    }

    $baseSecurityObject
}

function updateGroupSecurityMember {
    [CmdletBinding()]
    param(
        $SecuritySetting
    )

    $AZDOGroups = Get-ADOPSGroup
    $groupList = $SecuritySetting.Keys.Where({$_ -notin @('FileList', 'Project')})
    foreach ($groupName in $groupList) {
        $currGroupPrincipalName = "[$($securitySetting['Project'])]\$groupName"
        $currGroup = $AZDOGroups.Where({$_.principalName -eq $currGroupPrincipalName })
        if ($currGroup.Count -eq 0) {
            Write-Error "Group $currGroupPrincipalName doesn't seem to exist"
        }
        else {
            [string[]]$addMembers = $SecuritySetting[$groupName]
            foreach ($member in $addMembers) {
                Write-Host "Adding member $member to group $($currGroup.principalName)"
                $currUser = Get-ADOPSUser -Name $member
                if ($null -eq $currUser) {
                    Write-Error "$member doesnt seem to be a valid user principalName"
                }
                else {
                    $uri = "https://vssps.dev.azure.com/bjornsundling/_apis/graph/memberships/$($currUser.descriptor)/$($currGroup.descriptor)?api-version=7.2-preview.1"
                    $null = Invoke-ADOPSRestMethod -Method PUT -Uri $uri 
                }
            }
        }
    }
}