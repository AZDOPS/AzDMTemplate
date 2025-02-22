function mergePipelineSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Project,
        
        [Parameter(Mandatory)]
        $PipelineName
    )

    [hashtable]$basePipelineSettings = $AZDMPipelineSettings
    $basePipelineSettings['Project'] = $Project
 
    $pathToProject = Join-Path -Path $AZDMGlobalConfig['azdm_core']['rootfolder'] -ChildPath $Project 
    
    $projectLevelConfigName = Join-Path -Path $pathToProject -ChildPath "$Project.json"
    if (Test-Path -Path $projectLevelConfigName) {
        $basePipelineSettings['FileList'] += $projectLevelConfigName
        # We have a base project config. Continue downwards
        $projectLevelConfig = Get-Content -Path $projectLevelConfigName | ConvertFrom-Json -AsHashtable
        
        if (-Not $projectLevelConfig.Keys -contains 'project') {
            # No project config. Return the base object.
        }

        else {
            if ($projectLevelConfig['project'].Keys -contains 'pipelines') {
                foreach ($k in $projectLevelConfig['project']['pipelines'].Keys) {
                    if ($basePipelineSettings.Keys -contains $k) {
                        $basePipelineSettings[$k] = $projectLevelConfig['project']['pipelines'][$k]
                    }
                }
            }
            
            try {
                $pipelinesFolder = Join-Path -Path $pathToProject -ChildPath $projectLevelConfig['core']['pipelinesFolder']
            }
            catch {
                Write-Verbose 'No pipelines folder configured. Trying default "pipelines"'
                $pipelinesFolder = Join-Path -Path $pathToProject -ChildPath 'pipelines'
            }
            $pipelinesLevelConfigName = Join-Path -Path $pipelinesFolder -ChildPath "$Project.pipelines.json"
            if (Test-Path -Path $pipelinesLevelConfigName) {
                $basePipelineSettings['FileList'] += $pipelinesLevelConfigName
                # we have a pipelines level config
                $pipelinesLevelConfig = Get-Content -Path $pipelinesLevelConfigName | ConvertFrom-Json -AsHashtable
                if ($pipelinesLevelConfig.Keys -contains 'defaults') {
                    # We have a base pipeline config
                    foreach ($k in $pipelinesLevelConfig['defaults'].Keys) {
                        if ($basePipelineSettings.Keys -contains $k) {
                            $basePipelineSettings[$k] = $pipelinesLevelConfig['defaults'][$k]
                        }
                    }
                }
            }

            $currentPipelineConfigName = Join-Path -Path $pipelinesFolder -ChildPath $PipelineName -AdditionalChildPath "$PipelineName.json"
            if (Test-Path -Path $currentPipelineConfigName) {
                $basePipelineSettings['FileList'] += $currentPipelineConfigName
                # We have a pipeline specific config
                $currentPipelineConfig = Get-Content -Path $currentPipelineConfigName | ConvertFrom-Json -AsHashtable
                foreach ($k in $currentPipelineConfig.Keys) {
                    if ($basePipelineSettings.Keys -contains $k) {
                        $basePipelineSettings[$k] = $currentPipelineConfig[$k]
                    }
                }
            }
        }
    }

    StringReplacement -FixObject $basePipelineSettings -PipelineName $PipelineName
}

function StringReplacement {
    [CmdletBinding()]
    param(
        [hashtable]$FixObject,
        [string]$PipelineName
    )

    foreach ($k in $($FixObject.Keys)) {
        if ($FixObject[$k] -eq '{{pipeline.name}}') {
            $FixObject[$k] = $PipelineName
        }
    }

    $FixObject
}

function createPipeline {
    [CmdletBinding()]
    param (
        [ValidateScript({
            $_.Keys -contains 'Name' -and
            $_.Keys -contains 'Project' -and
            $_.Keys -contains 'YamlPath' -and
            $_.Keys -contains 'Repository'
        }, ErrorMessage = 'Name, Project, YamlPath, and Repository keys must be present and not empty')]
        [hashtable]$PipelineSetting
    )

    # Remove opening dots if used to denote relative path.
    $PipelineSetting['YamlPath'] = $PipelineSetting['YamlPath'].TrimStart('.\/')

    # if yaml file does not exist, create it using template
    $repository = Get-ADOPSRepository -Project $PipelineSetting.Project -Repository $PipelineSetting.Repository
    if ($null -eq $repository) {
        throw "Repository $($PipelineSetting.Repository) not found in project $($PipelineSetting.Project)"
    }

    try {
        Get-ADOPSFileContent -Project $PipelineSetting.Project -FilePath $PipelineSetting.YamlPath -RepositoryId $repository.id
    }
    catch {
        createYamlFromTemplateFile -Repository $repository -RepoSetting $PipelineSetting
    }


    $newPipelineParams = matchParameter -FunctionName New-ADOPSPipeline -Hashtable $PipelineSetting
    New-ADOPSPipeline @newPipelineParams
}

function updatePipeline {
    [CmdletBinding()]
    param (
        [hashtable]$PipelineSetting
    )

    try {
        $existingPipeline = Get-ADOPSPipeline -Name $PipelineSetting.Name -Project $PipelineSetting.Project
    }
    catch {
        throw "Pipeline $($PipelineSetting.Name) not found in project $($PipelineSetting.Project)"
    }

    [array]$pipelineDefinition = Get-ADOPSBuildDefinition -Project $($PipelineSetting.Project) -Id $($existingPipeline.id)

    [array]$updateDiff = diffCheckPipeline -PipelineSetting $PipelineSetting -existingPipeline $existingPipeline -pipelineDefinition $pipelineDefinition
    
    if ($updateDiff.Count -ge 1) {
        # NOTE: Since pipelineDefinition is refered to by reference this command will actually also update the original $pipelineDefinition variable.
        # This doesn't really matter right now, but for future debugging Bjompen...
        $updatedPipelineDefinition = updatePipelineDefinition -UpdateDiff $updateDiff -PipelineDefinition $pipelineDefinition[0]

        Set-ADOPSBuildDefinition -DefinitionObject $updatedPipelineDefinition
    }
}

function diffCheckPipeline {
    [CmdletBinding()]
    param(
        [hashtable]$PipelineSetting,
        $existingPipeline,
        $pipelineDefinition,
        [switch]$IncludeEqual
    )

    [array]$diffList = @()

    # Unfortunately there is no easy way to compare this. For now, lets do it manually.
    ## Project
    if ((compareNullString "$($PipelineSetting['Project'])" "-ne" "$($pipelineDefinition.project.name)") -or ($IncludeEqual)) {
        $diffList += @{
            Setting = 'Project'
            AzDMConfiguredValue = $PipelineSetting['Project']
            AzureDevOpsValue = $pipelineDefinition.project.name
        }
    }
    ## QueueStatus
    if ((compareNullString "$($PipelineSetting['QueueStatus'])" "-ne" "$($pipelineDefinition.QueueStatus)") -or ($IncludeEqual)) {
        $diffList += @{
            Setting = 'QueueStatus'
            AzDMConfiguredValue = $PipelineSetting['QueueStatus']
            AzureDevOpsValue = $pipelineDefinition.QueueStatus
        }
    }
    ## YamlPath
    if ((compareNullString "$($PipelineSetting['YamlPath'].TrimStart('.\/'))" "-ne" "$($existingPipeline.configuration.path)") -or ($IncludeEqual)) {
        $diffList += @{
            Setting = 'YamlPath'
            AzDMConfiguredValue = $PipelineSetting['YamlPath'].TrimStart('.\/')
            AzureDevOpsValue = $existingPipeline.configuration.path
        }
    }
    ## Repository
    if ((compareNullString "$($PipelineSetting['Repository'])" "-ne" "$($pipelineDefinition.repository.name)") -or ($IncludeEqual)) {
        $diffList += @{
            Setting = 'Repository'
            AzDMConfiguredValue = $PipelineSetting['Repository']
            AzureDevOpsValue = $pipelineDefinition.repository.name
        }
    }
    ## Name
    if ((compareNullString "$($PipelineSetting['Name'])" "-ne" "$($existingPipeline.name)") -or ($IncludeEqual)) {
        $diffList += @{
            Setting = 'Name'
            AzDMConfiguredValue = $PipelineSetting['Name']
            AzureDevOpsValue = $existingPipeline.name
        }
    }
    ## FolderPath. Since this setting depends on runner and platform, use some replace to get them correct.
    if ((compareNullString "$($PipelineSetting['FolderPath'] -replace '[\\\/]', [System.IO.Path]::DirectorySeparatorChar)" "-ne" "$($existingPipeline.folder -replace '[\\\/]', [System.IO.Path]::DirectorySeparatorChar)") -or ($IncludeEqual)) {
        $diffList += @{
            Setting = 'FolderPath'
            AzDMConfiguredValue = $PipelineSetting['FolderPath']
            AzureDevOpsValue = $existingPipeline.folder
        }
    }

    $diffList
}

function updatePipelineDefinition {
    [CmdletBinding()]
    param(
        $UpdateDiff,
        $PipelineDefinition
    )

    # Again,  no easy way to do this. For now, lets do it manually.
    # Only include settings we can avtually change.
    ## QueueStatus
    if ($updateDiff.Where({$_.Setting -eq 'QueueStatus'}).count -ge 1) {
        $pipelineDefinition.queueStatus = $UpdateDiff.Where({$_.Setting -eq 'QueueStatus'}).AzDMConfiguredValue
    }

    ## YamlPath
    if ($updateDiff.Where({$_.Setting -eq 'YamlPath'}).count -ge 1) {
        $pipelineDefinition.process.yamlFilename = $UpdateDiff.Where({$_.Setting -eq 'YamlPath'}).AzDMConfiguredValue
    }

    ## Name
    if ($updateDiff.Where({$_.Setting -eq 'Name'}).count -ge 1) {
        $pipelineDefinition.name = $UpdateDiff.Where({$_.Setting -eq 'Name'}).AzDMConfiguredValue
    }
    
    ## FolderPath. Since this setting depends on runner and platform, use some replace to get them correct.
    if ($updateDiff.Where({$_.Setting -eq 'FolderPath'}).count -ge 1) {
        $pipelineDefinition.path = $UpdateDiff.Where({$_.Setting -eq 'FolderPath'}).AzDMConfiguredValue
    }

    $PipelineDefinition
}

function createYamlFromTemplateFile {
    [CmdletBinding()]
    param (
        $Repository,
        $RepoSetting,
        $YAMLTemplateFile = "$AZDMGlobalRoot/.templates/NewPipeline.yaml"
    )

    $gitFileSplat = @{
        Project = $RepoSetting.Project 
        Repository = $RepoSetting.Repository 
        File = $YAMLTemplateFile
        FileName = $RepoSetting['YamlPath']
        Path = $RepoSetting['FolderPath']
        CommitMessage = "Added Pipeline Yaml from AzDM Template"
    }
    New-ADOPSGitFile @gitFileSplat
}
