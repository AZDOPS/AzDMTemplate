function mergeArtifactsSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Project,
        
        [Parameter(Mandatory)]
        $ArtifactsName
    )

    [hashtable]$baseArtifactsSettings = $AZDMArtifactsSettings
    $baseArtifactsSettings['Name'] = $ArtifactsName
    $baseArtifactsSettings['Project'] = $Project

    $pathToProject = Join-Path -Path $AZDMGlobalConfig['azdm_core']['rootfolder'] -ChildPath $Project 
    
    $projectLevelConfigName += Join-Path -Path $pathToProject -ChildPath "$Project.json"
    if (Test-Path -Path $projectLevelConfigName) {
        $baseArtifactsSettings['FileList'] += $projectLevelConfigName
        # We have a base project config. Continue downwards
        $projectLevelConfig = Get-Content -Path $projectLevelConfigName | ConvertFrom-Json -AsHashtable
        
        if (-Not $projectLevelConfig.Keys -contains 'project') {
            # No project config. Return the base object.
        }

        else {
            if ($projectLevelConfig['project'].Keys -contains 'artifacts') {
                foreach ($k in $projectLevelConfig['project']['artifacts'].Keys) {
                    if ($baseArtifactsSettings.Keys -contains $k) {
                        $baseArtifactsSettings[$k] = $projectLevelConfig['project']['artifacts'][$k]
                    }
                }
            }
            
            try {
                $artifactsFolder = Join-Path -Path $pathToProject -ChildPath $projectLevelConfig['core']['artifactsFolder']
            }
            catch {
                Write-Verbose 'No artifacts folder configured. Trying default "artifacts"'
                $artifactsFolder = Join-Path -Path $pathToProject -ChildPath 'artifacts'
            }
            $artifactsLevelConfigName = Join-Path -Path $artifactsFolder -ChildPath "$Project.artifacts.json"
            
            if (Test-Path -Path $artifactsLevelConfigName) {
                $baseArtifactsSettings['FileList'] += $artifactsLevelConfigName
                # we have a repo level config
                $artifactsLevelConfig = Get-Content -Path $artifactsLevelConfigName | ConvertFrom-Json -AsHashtable
                if ($artifactsLevelConfig.Keys -contains 'defaults') {
                    # We have a base repo config
                    foreach ($k in $artifactsLevelConfig['defaults'].Keys) {
                        if ($baseArtifactsSettings.Keys -contains $k) {
                            $baseArtifactsSettings[$k] = $artifactsLevelConfig['defaults'][$k]
                        }
                    }
                }
            }

            $currentArtifactsConfigName = Join-Path -Path $artifactsFolder -ChildPath $artifactsName -AdditionalChildPath "$artifactsName.json"
            if (Test-Path -Path $currentArtifactsConfigName) {
                $baseArtifactsSettings['FileList'] += $currentartifactsConfigName
                # We have a artifacts specific config
                $currentArtifactsConfig = Get-Content -Path $currentArtifactsConfigName | ConvertFrom-Json -AsHashtable
                foreach ($k in $currentArtifactsConfig.Keys) {
                    if ($baseArtifactsSettings.Keys -contains $k) {
                        $baseArtifactsSettings[$k] = $currentArtifactsConfig[$k]
                    }
                }
            }
        }
    }

    $baseArtifactsSettings
}

function createArtifacts {
    [CmdletBinding()]
    param (
        [ValidateScript({
            $_.Keys -contains 'Name' -and
            -Not ([string]::IsNullOrWhiteSpace($_['Name']))
        }, ErrorMessage = 'Name key must be present and not empty')]
        [hashtable]$ArtifactsSetting
    )

    $createParams = matchParameter -FunctionName New-ADOPSArtifactFeed -Hashtable $ArtifactsSetting

    # Create feed
    $createdArtifactsFeed = New-ADOPSArtifactFeed @createParams
}


function updateArtifacts {
    [CmdletBinding()]
    param (
        [hashtable]$ArtifactSetting
    )

    $existingArtifactsFeed = Get-ADOPSArtifactFeed -Project $ArtifactSetting['Project'] -FeedId $ArtifactSetting['Name']

    $updateDiff = diffCheckArtifacts -ArtifactSetting $ArtifactSetting -ExistingArtifacts $existingArtifactsFeed

    if ($updateDiff.Count -ge 1) {
        $updateParams =  matchParameter -FunctionName Set-ADOPSArtifactFeed -Hashtable $ArtifactsSetting

        Set-ADOPSArtifactFeed -FeedId $existingArtifactsFeed.id @updateParams
    }
}

function diffCheckArtifacts {
    [CmdletBinding()]
    param(
        [hashtable]$ArtifactSetting,
        $existingArtifacts
    )

    [array]$diffList = @()

    # Unfortunately there is no easy way to compare this. For now, lets do it manually.
    ## Easy settings:
    [string[]]$easySettings = 'Name', 'Description'
    foreach($setting in $easySettings) {
        if ($ArtifactSetting[$setting] -ne $existingArtifacts.$($setting)) {
            $diffList += @{
                Setting = $setting
                AzDMConfiguredValue = $ArtifactSetting[$setting]
                AzureDevOpsValue = $existingArtifacts.$($setting)
            }
        }
    }

    ## Project
    if ($ArtifactSetting['Project'] -ne $existingArtifacts.project.name) {
        $diffList += @{
            Setting = 'Project'
            AzDMConfiguredValue = $ArtifactSetting['Project']
            AzureDevOpsValue = $existingArtifacts.project.name
        }
    }

    ## IncludeUpstream
    if ($ArtifactSetting['IncludeUpstream'] -ne $existingArtifacts.upstreamEnabled) {
        $diffList += @{
            Setting = 'IncludeUpstream'
            AzDMConfiguredValue = $ArtifactSetting['IncludeUpstream']
            AzureDevOpsValue = $existingArtifacts.upstreamEnabled
        }
    }
    
    $diffList
}
