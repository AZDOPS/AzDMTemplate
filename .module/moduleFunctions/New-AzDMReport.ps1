function New-AzDMReport {
    [CmdletBinding()]
    param()
        
    # Standard projects
    $AllProjects = getProjectTree
    
    [array]$WhatIfResults = @()
    
    foreach ($Project in $AllProjects) {
        Write-Verbose "Running project $($Project.Project)" -Verbose
        
        $ProjectResourceTree = getProjectResources @Project

        $currentProjectWhatIfResults = @{}
        
        $projectSetting = mergeProjectSetting -Project $Project.Project
        if (-Not ($ProjectResourceTree.Exists)){
            $projectWhatIfResults = @{
                Setting = $project.Project
                AzDMConfiguredValue = 'Created'
                AzureDevOpsValue = 'Not created'
            }
            $currentProjectWhatIfResults.Add("Project§$($project.Project)", [array]$projectWhatIfResults)
        }
        else {
            $existingProject = Get-ADOPSProject -Name $Project.Project
            $currentProjectWhatIfResults.Add("Project§$($project.Project)", [array](diffCheckProject -ProjectSetting $ProjectSetting -ExistingProject $existingProject -IncludeEqual))
        }

        # Check and update repo status
        foreach ($repo in $ProjectResourceTree['Repos']) {
            $h = mergeRepoSetting -project $Project.Project -repoName $repo.Name
            if (-Not ($repo.Exists)) {
                $repoWhatIfResults = @{
                    Setting = $repo.Name
                    AzDMConfiguredValue = 'Created'
                    AzureDevOpsValue = 'Not created'
                }
                $currentProjectWhatIfResults.Add("Repo§$($repo.Name)", [array]$repoWhatIfResults)
            }
            else {
                $existingRepo = Get-ADOPSRepository -Project $h['Project'] -Repository $h['Name']
                if ($null -eq $existingRepo) {
                    # Because disabled repos arent searchable in the same way we try this before failing...
                    $existingRepo = Get-ADOPSRepository -Project $h['Project'] | Where-Object {$_.Name -eq $h['Name']}
                }
                $repoDiffs = diffCheckRepo -RepoSetting $h -existingRepo $existingRepo -IncludeEqual
                $currentProjectWhatIfResults.Add("Repo§$($repo.Name)", [array]$repoDiffs)
            }
        }

        # Check and update pipeline status        
        foreach ($pipeline in $ProjectResourceTree['Pipelines']) {
            $p = mergePipelineSetting -project $Project.Project -PipelineName $pipeline.Name
            if (-Not ($pipeline.Exists)) {
                $pipelineWhatIfResults = @{
                    Setting = $pipeline.Name
                    AzDMConfiguredValue = 'Created'
                    AzureDevOpsValue = 'Not created'
                }
                $currentProjectWhatIfResults.Add("Pipeline§$($pipeline.Name)", [array]$pipelineWhatIfResults)
            }
            else {
                $existingPipeline = Get-ADOPSPipeline -Name $p['Name'] -Project $p['Project']
                [array]$pipelineDefinition = Get-ADOPSBuildDefinition -Project $p['Project'] -Id $($existingPipeline.id)
                $pipelineDiff = diffCheckPipeline -PipelineSetting $p -existingPipeline $existingPipeline -pipelineDefinition $pipelineDefinition -IncludeEqual
                $currentProjectWhatIfResults.Add("Pipeline§$($pipeline.Name)", [array]$pipelineDiff)
            }
        }

        # Check and update artifacts status        
        foreach ($artifact in $ProjectResourceTree['Artifacts']) {
            $a = mergeArtifactsSetting -project $Project.Project -ArtifactsName $artifact.Name
            if (-Not ($artifact.Exists)) {
                $artifactsWhatIfResults = @{
                    Setting = $artifact.Name
                    AzDMConfiguredValue = 'Created'
                    AzureDevOpsValue = 'Not created'
                }
                $currentProjectWhatIfResults.Add("Artifacts§$($artifact.Name)", [array]$artifactsWhatIfResults)
            }
            else {
                $existingArtifactsFeed = Get-ADOPSArtifactFeed -Project $a['Project'] -FeedId $a['Name']
                $artifactDiff = diffCheckArtifacts -ArtifactSetting $a -ExistingArtifacts $existingArtifactsFeed -IncludeEqual
                if (-not ($null -eq $artifactDiff)) {
                    $currentProjectWhatIfResults.Add("Artifact§$($artifact.Name)", [array]$artifactDiff)
                }
            }
        }

        $WhatIfResults += @{
            $($Project.Project) = $currentProjectWhatIfResults
        }
    }

    # Excluded projects
    foreach ($excludedProject in @($AZDMGlobalConfig['core']['excludeProjects'])) {
        Write-Verbose "Running excluded project $excludedProject" -Verbose
        $currentProjectWhatIfResults = @{}

        if (Get-ADOPSProject -Name $excludedProject) {
            $azureDevOpsValue = 'Created'
        }
        else {
            $azureDevOpsValue = 'Not created'
        }

        $projectWhatIfResults = @{
            Setting = $excludedProject
            AzDMConfiguredValue = 'Ignored'
            AzureDevOpsValue = $azureDevOpsValue
        }
        $currentProjectWhatIfResults.Add("Project§$excludedProject", [array]$projectWhatIfResults)

        $WhatIfResults += @{
            "$excludedProject" = $currentProjectWhatIfResults
        }
    }

    # Extensions
    $extensionSettings = @(
        'extensionId'      
        'extensionName'
        'publisherId'
        'publisherName'
        'version'
        'baseUri'
        'fallbackBaseUri'
        'lastPublished'
    )
    $allExtensions = Invoke-ADOPSRestMethod -Uri "https://extmgmt.dev.azure.com/$((Get-ADOPSConnection).Organization)/_apis/extensionmanagement/installedextensions?api-version=7.2-preview.2"
    
    foreach ($ext in $allExtensions.Value) {
        Write-Verbose "Running extension $($ext.extensionName)" -Verbose
        $currentExtensionWhatIfResults = @{}

        $ExtensionWhatIfResults = @()

        foreach ($extSetting in $extensionSettings) {
            $ExtensionWhatIfResults += @{
                Setting = $extSetting
                AzDMConfiguredValue = 'Ignored'
                AzureDevOpsValue = $ext.$extSetting
            }
        }

        $currentExtensionWhatIfResults.Add("Extension§$($ext.extensionName)", [array]$ExtensionWhatIfResults)
        
        $WhatIfResults += @{
            "$($ext.extensionName)" = $currentExtensionWhatIfResults
        }
    }


    $WhatIfResults
}
