function mergeRepoSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Project,
        
        [Parameter(Mandatory)]
        $RepoName
    )

    [hashtable]$baseRepoSettings = $AZDMRepoSettings
    $baseRepoSettings['Name'] = $RepoName
    $baseRepoSettings['Project'] = $Project

    $pathToProject = Join-Path -Path $AZDMGlobalConfig['azdm_core']['rootfolder'] -ChildPath $Project 
    
    $projectLevelConfigName += Join-Path -Path $pathToProject -ChildPath "$Project.json"
    if (Test-Path -Path $projectLevelConfigName) {
        $baseRepoSettings['FileList'] += $projectLevelConfigName
        # We have a base project config. Continue downwards
        $projectLevelConfig = Get-Content -Path $projectLevelConfigName | ConvertFrom-Json -AsHashtable
        
        if (-Not $projectLevelConfig.Keys -contains 'project') {
            # No project config. Return the base object.
        }

        else {
            if ($projectLevelConfig['project'].Keys -contains 'repos') {
                foreach ($k in $projectLevelConfig['project']['repos'].Keys) {
                    if ($baseRepoSettings.Keys -contains $k) {
                        $baseRepoSettings[$k] = $projectLevelConfig['project']['repos'][$k]
                    }
                }
            }
            
            $reposFolder = Join-Path -Path $pathToProject -ChildPath $projectLevelConfig['core']['reposFolder']
            $reposLevelConfigName = Join-Path -Path $reposFolder -ChildPath "$Project.repos.json"
            if (Test-Path -Path $reposLevelConfigName) {
                $baseRepoSettings['FileList'] += $reposLevelConfigName
                # we have a repo level config
                $reposLevelConfig = Get-Content -Path $reposLevelConfigName | ConvertFrom-Json -AsHashtable
                if ($reposLevelConfig.Keys -contains 'defaults') {
                    # We have a base repo config
                    foreach ($k in $reposLevelConfig['defaults'].Keys) {
                        if ($baseRepoSettings.Keys -contains $k) {
                            $baseRepoSettings[$k] = $reposLevelConfig['defaults'][$k]
                        }
                    }
                }
            }

            $currentRepoConfigName = Join-Path -Path $reposFolder -ChildPath $RepoName -AdditionalChildPath "$RepoName.json"
            if (Test-Path -Path $currentRepoConfigName) {
                $baseRepoSettings['FileList'] += $currentRepoConfigName
                # We have a repo specific config
                $currentRepoConfig = Get-Content -Path $currentRepoConfigName | ConvertFrom-Json -AsHashtable
                foreach ($k in $currentRepoConfig.Keys) {
                    if ($baseRepoSettings.Keys -contains $k) {
                        $baseRepoSettings[$k] = $currentRepoConfig[$k]
                    }
                }
            }
        }
    }

    $baseRepoSettings
}

function createRepository {
    [CmdletBinding()]
    param (
        [ValidateScript({
            $_.Keys -contains 'Name' -and
            -Not ([string]::IsNullOrWhiteSpace($_['Name']))
        }, ErrorMessage = 'Name key must be present and not empty')]
        [hashtable]$RepoSetting
    )

    $createParams = matchParameter -FunctionName New-ADOPSRepository -Hashtable $RepoSetting
    $updateParams = matchParameter -FunctionName Set-ADOPSRepository -Hashtable $RepoSetting

    # Create repo
    $createdRepo = New-ADOPSRepository @createParams

    $initializeRepo = Initialize-ADOPSRepository -RepositoryId $createdRepo.id -Readme -Message 'Initialized using AzDM' -Branch $RepoSetting['DefaultBranch']
    
    $SetRepo = Set-ADOPSRepository -RepositoryId $createdRepo.id @updateParams 
}


function updateRepository {
    [CmdletBinding()]
    param (
        [hashtable]$RepoSetting
    )

    $existingRepo = Get-ADOPSRepository -Project $RepoSetting['Project'] -Repository $RepoSetting['Name']
    if ($null -eq $existingRepo) {
        # Because disabled repos arent searchable in the same way we try this before failing...
        $existingRepo = Get-ADOPSRepository -Project $RepoSetting['Project'] | Where-Object {$_.Name -eq $RepoSetting['Name']}
    }
    
    $updateDiff = diffCheckRepo -RepoSetting $RepoSetting -existingRepo $existingRepo

    if ($updateDiff.Count -ge 1) {
        $updateParams = matchParameter -FunctionName Set-ADOPSRepository -Hashtable $RepoSetting
        $updateParams = $updateParams.Keys | Where-Object {$_ -in [pscustomobject]$updateDiff.Setting} | ForEach-Object {
            $keyName = $_
            $keyValue = $RepoSetting[$_]
            @{
                $keyName = $keyValue
            }
        }
        if ($updateParams.Keys -notcontains 'Project') {
            $updateParams['Project'] = $RepoSetting['Project']
        }
        
        Set-ADOPSRepository -RepositoryId $existingRepo.id @updateParams 
    }
}

function diffCheckRepo {
    [CmdletBinding()]
    param(
        [hashtable]$RepoSetting,
        $existingRepo
    )

    [array]$diffList = @()

    # Unfortunately there is no easy way to compare this. For now, lets do it manually.
    ## Easy settings:
    [string[]]$easySettings = 'Name', 'IsDisabled'
    foreach($setting in $easySettings) {
        if ($RepoSetting[$setting] -ne $existingRepo.$($setting)) {
            $diffList += @{
                Setting = $setting
                AzDMConfiguredValue = $RepoSetting[$setting]
                AzureDevOpsValue = $existingRepo.$($setting)
            }
        }
    }

    ## DefaultBranch
    if ($RepoSetting['DefaultBranch'] -notmatch '^refs/.*') {
        # If we use relative branch names we need to compare them to a full branch. /refs/heads/ is standard
        $RepoSetting['DefaultBranch'] = "refs/heads/$($RepoSetting['DefaultBranch'])"
    }
    if ($RepoSetting['DefaultBranch'] -ne $existingRepo.defaultBranch) {
        $diffList += @{
            Setting = 'DefaultBranch'
            AzDMConfiguredValue = $RepoSetting['DefaultBranch']
            AzureDevOpsValue = $existingRepo.defaultBranch
        }
    }
    
    ## Project
    if ($RepoSetting['Project'] -ne $existingRepo.project.name) {
        $diffList += @{
            Setting = 'Project'
            AzDMConfiguredValue = $RepoSetting['Project']
            AzureDevOpsValue = $existingRepo.project.name
        }
    }
    
    $diffList
}
