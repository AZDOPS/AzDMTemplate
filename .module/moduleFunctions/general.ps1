function matchParameter {
    [CmdletBinding()]
    param(
        [string]$FunctionName,
        [hashtable]$Hashtable
    )

    $matchHash = @{}
    
    $commandParameterMetaData = (Get-Command $FunctionName).Parameters
    $supportedParameters = $commandParameterMetaData.Keys

    foreach ($key in $Hashtable.Keys) {
        if (
            ($key -in $supportedParameters) -and 
            ((
                $Hashtable[$key]
            ) -or (
                $commandParameterMetaData[$key].SwitchParameter -eq $true -or
                $commandParameterMetaData[$key].Attributes.Mandatory -eq $true -or
                $commandParameterMetaData[$key].Attributes.TypeId.Name -Contains 'AllowEmptyStringAttribute' -or
                $commandParameterMetaData[$key].Attributes.TypeId.Name -Contains 'AllowNullAttribute'
            ) -or (
                $key -eq 'IsDisabled' # Workaround to be able to support disabled params...
            ))
        ) {
            $matchHash[$key] = $Hashtable[$key]  
        }
    }

    $matchHash
}

function matchDifflist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FunctionName,

        [Parameter(Mandatory)]
        $DiffList
    )

    $commandParameterMetaData = (Get-Command $FunctionName).Parameters
    $supportedParameters = $commandParameterMetaData.Keys

    $matchedParams = @{}
    foreach ($changeValue in $DiffList) {
        if ($changeValue.Setting -in $supportedParameters) {
            $matchedParams.Add($changeValue.Setting, $changeValue.AzDMConfiguredValue)
        }
    }

    $matchedParams
}

function getProjectTree {
    [CmdletBinding()]
    Param()
    [array]$projects = foreach ($k in ($AZDMGlobalConfig['projects'].Keys)) {
        $projectPath = Join-Path -Path $AZDMGlobalConfig['azdm_core']['rootfolder'] -ChildPath $k
        $configPath = Join-Path -Path $projectPath -ChildPath "$k.json"
        @{
            Project     = $k
            ProjectPath = $projectPath
            ConfigPath  = $configPath
        }
    }
    $projects
}

function getProjectResources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Project,
        
        [Parameter(Mandatory)]
        $ProjectPath,
        
        [Parameter(Mandatory)]
        $ConfigPath
    )

    Write-Verbose "Getting project $Project"
    [bool]$projectExists = -Not ($null -eq (Get-ADOPSProject -Name $Project))

    #region GetReposSettings
    Write-Verbose "Getting project repos from project $Project"
    try {
        # Get repos folder from config
        $projectReposFolder = Join-Path -Path $ProjectPath -ChildPath $AZDMGlobalConfig['projects'][$Project]['core']['reposFolder']
    }
    catch {
        # If setting is not defined, assume repos folder
        $projectReposFolder = Join-Path -Path $ProjectPath -ChildPath 'repos'
    }
    $projectReposConfigPath = Join-Path -Path $projectReposFolder -ChildPath "$Project.repos.json"
    try {
        [array]$projectReposNames = (Get-Content -Path $projectReposConfigPath -ErrorAction Stop | ConvertFrom-Json).'repos.names' 
    }
    catch {
        # If the reposfile doesnt exist we will end up here.
        [array]$projectReposNames = @()
    }
    
    [array]$projectRepos = foreach ($r in $projectReposNames) {
        try {
            [bool]$repoExists = -Not ($null -eq (Get-ADOPSRepository -Project $Project -Repository $r))
        }
        catch {
            [bool]$repoExists = $false
        }
        @{
            Name   = $r
            Exists = $repoExists
        }
    }
    #endregion


    #region GetPipelinesSettings
    Write-Verbose "Getting project pipelines from project $Project"
    try {
        # Get pipeline folder from config
        $projectPipelinesFolder = Join-Path -Path $ProjectPath -ChildPath $AZDMGlobalConfig['projects'][$Project]['core']['pipelinesFolder']
    }
    catch {
        # If setting is not defined, assume pipelines folder
        $projectPipelinesFolder = Join-Path -Path $ProjectPath -ChildPath 'pipelines'
    }
    $projectPipelinesConfigPath = Join-Path -Path $projectPipelinesFolder -ChildPath "$Project.pipelines.json"
    try {
        [array]$projectPipelinesNames = (Get-Content -Path $projectPipelinesConfigPath -ErrorAction Stop | ConvertFrom-Json).'pipelines.names' 
    }
    catch {
        # If the pipelinesfile doesnt exist we will end up here.
        [array]$projectPipelinesNames = @()
    }

    [array]$projectPipelines = foreach ($p in $projectPipelinesNames) {
        try {
            [bool]$pipelinesExists = -Not ($null -eq (Get-ADOPSPipeline -Project $Project -Name $p))
        }
        catch {
            [bool]$pipelinesExists = $false
        }
        @{
            Name   = $p
            Exists = $pipelinesExists
        }
    }
    #endregion

    #region GetArtifactsSettings
    Write-Verbose "Getting project artifacts from project $Project"
    try {
        # Get pipeline folder from config
        $projectArtifactsFolder = Join-Path -Path $ProjectPath -ChildPath $AZDMGlobalConfig['projects'][$Project]['core']['artifactsFolder']
    }
    catch {
        # If setting is not defined, assume artifacts folder
        $projectArtifactsFolder = Join-Path -Path $ProjectPath -ChildPath 'artifacts'
    }
    $projectArtifactsConfigPath = Join-Path -Path $projectArtifactsFolder -ChildPath "$Project.artifacts.json"
    try {
        [array]$projectArtifactsNames = (Get-Content -Path $projectArtifactsConfigPath -ErrorAction Stop | ConvertFrom-Json).'artifacts.names' 
    }
    catch {
        # If the artifactsfile doesnt exist we will end up here.
        [array]$projectArtifactsNames = @()
    }

    [array]$projectArtifacts = foreach ($a in $projectArtifactsNames) {
        try {
            [bool]$artifactsExists = -Not ($null -eq (Get-ADOPSArtifactFeed -Project $Project -FeedId $a))
        }
        catch {
            [bool]$artifactsExists = $false
        }
        @{
            Name   = $a
            Exists = $artifactsExists
        }
    }
    #endregion
    @{
        Exists    = $projectExists
        Repos     = $projectRepos
        Pipelines = $projectPipelines
        Artifacts = $projectArtifacts
    }
}

<# compareChanges.
    This function compares the result of a git diff and the files that is in effect when creating or updating a repo or pipeline.
    If any object is in both lists we return true to run an object update.
#> 
function compareChanges {
    [CmdletBinding()]
    param(
        $OperationFileList,
        $GitChanges
    )

    $equalObjects = Compare-Object -ReferenceObject $OperationFileList -DifferenceObject $GitChanges -ExcludeDifferent

    if ($equalObjects.count -ge 1) {
        $true
    }
    else {
        $false
    }
}

function formatWhatIfResults {
    param(
        $WhatIfResults
    )

    $outputAsString = [string]::Empty

    foreach ($result in $WhatIfResults) {
        $outputAsString += "-----------------`r`n$($result.Keys)`r`n-----------------`r`n"
        foreach ($change in $result[$($result.Keys)].Keys) {
            try {
                $outputAsString += "`t$change`r`n"
                foreach ($setting in $result[$($result.Keys)][$change]) {
                    $outputAsString += "`t`tSetting`t`t`t- $($setting['Setting'])`r`n"
                    $outputAsString += "`t`tAzDM Configured value`t- $($setting['AzDMConfiguredValue'])`r`n"
                    $outputAsString += "`t`tAzure DevOps value`t- $($setting['AzureDevOpsValue'])`r`n"
                }
            }
            catch {
                $outputAsString += "`t`tFailed to parse changes. Data as Json follows`r`n"
                $outputAsString += "`t`t$change`r`n`t`t$($result[$($result.Keys)][$change] | ConvertTo-Json -Depth 10)`r`n"
            }
        }
        $outputAsString += "-----------------`r`n`r`n`r`n"
    }

    $outputAsString
}

function compareNullString {
    param(
        $ReferenceObject,
        $operator,
        $DifferenceObject
    )

    if (
        [string]::IsNullOrEmpty($ReferenceObject) -or
        [string]::IsNullOrWhiteSpace($ReferenceObject)
    ) {
        $ReferenceObject = [string]::Empty
    }

    if (
        [string]::IsNullOrEmpty($DifferenceObject) -or
        [string]::IsNullOrWhiteSpace($DifferenceObject)
    ) {
        $DifferenceObject = [string]::Empty
    }
    
    Invoke-Expression """$ReferenceObject"" $operator ""$DifferenceObject"""
}

function getGitDiff {
    param()

    [string[]]$gitChanges = git diff HEAD^ HEAD --name-status
    $result = foreach ($change in $gitChanges) {
        $null = $change -match '^(?<type>\w)\s+(?<path>.*)$'
        
        $type = switch ($Matches['type']) {
            'A' { 'Added' }
            'C' { 'Copied' }
            'D' { 'Deleted' }
            'M' { 'Modified' }
            'R' { 'Renamed' }
            'T' { 'TypeChanged' }
            'U' { 'Unmerged' }
            'X' { 'Unknown' }
            'B' { 'Broken' }
        }

        $Path = $Matches['path'] -replace '[\\\/]', [System.IO.Path]::DirectorySeparatorChar | 
        ForEach-Object {
            Join-Path -Path $AZDMGlobalRoot -ChildPath $_
        } 

        @{
            Type = $type
            Path = $Path
        }
    }

    $result
}