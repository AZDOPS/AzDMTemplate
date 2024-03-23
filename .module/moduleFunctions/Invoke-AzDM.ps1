# This function is where the push and update happens. 
# It is just outside to keep the pipeline clean and make it easier to develop it in VSCode...

function Invoke-AzDM {
    [CmdletBinding()]
    param(
        [string[]]$GitChanges,
        [switch]$WhatIf
    )

    $AllProjects = getProjectTree
    Write-Host "Found projects $($AllProjects.Project -Join ', ')"
    
    if ($WhatIf.IsPresent) {
        $shouldDeploy = $false
        [array]$WhatIfResults = @()
    }
    else {
        $shouldDeploy = $true
    }

    foreach ($Project in $AllProjects) {
        Write-Host "Running project $($Project.Project)"
        
        $ProjectResourceTree = getProjectResources @Project

        if (-Not $shouldDeploy) {
            $currentProjectWhatIfResults = @{}
        }
        # Check and update project status
        $projectSetting = mergeProjectSetting -Project $Project.Project
        if (-Not ($ProjectResourceTree.Exists)){
            if ($shouldDeploy) {
                Write-Host "Project $($Project.Project) does not exist. Creating"
                createProject -ProjectSetting $projectSetting
            }
            else {
                Write-Host "Project $($Project.Project) does not exist. Adding it to WhatIf result."
                $projectWhatIfResults = @{
                    Setting = $project.Project
                    AzDMConfiguredValue = 'Created'
                    AzureDevOpsValue = 'Not created'
                }
                $currentProjectWhatIfResults.Add('Project', $projectWhatIfResults)
            }
        }
        elseif ( ( compareChanges -OperationFileList $projectSetting.FileList -GitChanges $gitChanges ) ) {
            if ($shouldDeploy) {
                Write-Host "Project $($Project.Project) has changes. Updating" 
                updateProject -ProjectSetting $projectSetting    
            }
            else {
                Write-Host "Project $($Project.Project) has changes. Adding it to WhatIf result."
                $existingProject = Get-ADOPSProject -Name $Project.Project
                $currentProjectWhatIfResults.Add('Project', (diffCheckProject -ProjectSetting $ProjectSetting -ExistingProject $existingProject))
            }
        }
        else {
            Write-Verbose "Project $($Project.Project) has no changes." 
        }

        # Check and update repo status
        foreach ($repo in $ProjectResourceTree['Repos']) {
            $h = mergeRepoSetting -project $Project.Project -repoName $repo.Name
            if (-Not ($repo.Exists)) {
                if ($shouldDeploy) {
                    Write-Host "Repo $($repo.Name) does not exist. Creating" 
                    createRepository -RepoSetting $h
                }
                else {
                    Write-Host "Repo $($repo.Name) does not exist. Adding it to WhatIf result."
                    $repoWhatIfResults = @{
                        Setting = $repo.Name
                        AzDMConfiguredValue = 'Created'
                        AzureDevOpsValue = 'Not created'
                    }
                    $currentProjectWhatIfResults.Add("Repo - $($repo.Name)", $repoWhatIfResults)
                }
            }
            elseif ( (compareChanges -OperationFileList $h.FileList -GitChanges $gitChanges ) ) {
                if ($shouldDeploy) {
                    Write-Host "Repo $($repo.Name) has changes. Updating" 
                    updateRepository -RepoSetting $h     
                }
                else {
                    Write-Host "Repo $($repo.Name) has changes. Adding it to WhatIf result."
                    $existingRepo = Get-ADOPSRepository -Project $h['Project'] -Repository $h['Name']
                    if ($null -eq $existingRepo) {
                        # Because disabled repos arent searchable in the same way we try this before failing...
                        $existingRepo = Get-ADOPSRepository -Project $h['Project'] | Where-Object {$_.Name -eq $h['Name']}
                    }
                    $currentProjectWhatIfResults.Add("Repo - $($repo.Name)", (diffCheckRepo -RepoSetting $h -existingRepo $existingRepo))
                }
            }
            else {
                Write-Verbose "Repo $($repo.Name) has no changes." 
            }
        }

        # Check and update pipeline status        
        foreach ($pipeline in $ProjectResourceTree['Pipelines']) {
            $p = mergePipelineSetting -project $Project.Project -PipelineName $pipeline.Name
            if (-Not ($pipeline.Exists)) {
                if ($shouldDeploy) {
                    Write-Host "Pipeline $($pipeline.Name) does not exist. Creating" 
                    createPipeline -PipelineSetting $p
                }
                else {
                    Write-Host "Pipeline $($pipeline.Name) does not exist. Adding it to WhatIf result."
                    $pipelineWhatIfResults = @{
                        Setting = $pipeline.Name
                        AzDMConfiguredValue = 'Created'
                        AzureDevOpsValue = 'Not created'
                    }
                    $currentProjectWhatIfResults.Add("Pipeline - $($pipeline.Name)", $pipelineWhatIfResults)
                }
            }
            elseif ( (compareChanges -OperationFileList $p.FileList -GitChanges $gitChanges ) ) {
                if ($shouldDeploy) {
                    Write-Host "Pipeline $($pipeline.Name) has changes. Updating" 
                    updatePipeline -PipelineSetting $p
                }
                else {
                    Write-Host "Pipeline $($pipeline.Name) has changes. Adding it to WhatIf result."
                    $existingPipeline = Get-ADOPSPipeline -Name $p['Name'] -Project $p['Project']
                    [array]$pipelineDefinition = Get-ADOPSBuildDefinition -Project $p['Project'] -Id $($existingPipeline.id)

                    $currentProjectWhatIfResults.Add("Pipeline - $($pipeline.Name)", (diffCheckPipeline -PipelineSetting $p -existingPipeline $existingPipeline -pipelineDefinition $pipelineDefinition))
                }
            }
            else {
                Write-Verbose "Pipeline $($pipeline.Name) has no changes." 
            }
        }

        if ($WhatIf.IsPresent -and $currentProjectWhatIfResults.Count -ge 1) {
            $WhatIfResults += @{
                $($Project.Project) = $currentProjectWhatIfResults
            }
        }
    }   

    if ($WhatIf.IsPresent -and $WhatIfResults.Count -ge 1) {
        formatWhatIfResults -WhatIfResults $WhatIfResults
    }
}
