# This module is required to run AzDM. It sets all kinds of prereqs for the rest of the functions, and standardizes defaults for functionality.

$requiredModules = @(
    @{
        Name = 'AzAuth'
        MinimumVersion = '2.2.4'
    },
    @{
        Name = 'ADOPS'
        MinimumVersion = '2.2.1'
    }
)
foreach ($m in $requiredModules) {
    try {
        Import-Module @m -Scope Global
    }
    catch {
        Throw "Missing or failed to import module $($m.Name)"
    }
}

## Module defaults
$Global:AZDMModuleRoot = $PSScriptRoot
$Global:AZDMGlobalRoot = Split-Path -Path $Global:AZDMModuleRoot
$Global:AZDMGlobalConfig = .$Global:AZDMModuleRoot\moduleScripts\GetConfig.ps1 -SettingsFile $(Join-Path -Path $AZDMGlobalRoot -ChildPath 'settings.json')

## Repo defaults. Set this AsReadOnly() to prevent accidental overwrites of global defaults.
$Global:AZDMRepoSettings = ([ordered]@{
    Name = $Global:AZDMGlobalConfig['organization']['repos']['Name'] ?? [string]::Empty
    DefaultBranch = $Global:AZDMGlobalConfig['organization']['repos']['DefaultBranch'] ?? 'main'
    IsDisabled = $Global:AZDMGlobalConfig['organization']['repos']['IsDisabled'] ?? $false
    Project = [string]::Empty
    FileList = @($AZDMGlobalConfig['azdm_core']['rootfolderconfigfile']) # This property keeps track of files involved in each repo. Populated in mergeRepoSettings 
}).AsReadOnly()

## Pipeline defaults. Set this AsReadOnly() to prevent accidental overwrites of global defaults.
$Global:AZDMPipelineSettings = ([ordered]@{
    Name = $Global:AZDMGlobalConfig['organization']['pipelines']['Name'] ?? [string]::Empty
    FolderPath = $Global:AZDMGlobalConfig['organization']['pipelines']['FolderPath'] ?? '/'
    Repository = $Global:AZDMGlobalConfig['organization']['pipelines']['Repository'] ?? [string]::Empty
    YamlPath = $Global:AZDMGlobalConfig['organization']['pipelines']['YamlPath'] ?? './azure-pipelines.yml'
    Project = [string]::Empty
    FileList = @($AZDMGlobalConfig['azdm_core']['rootfolderconfigfile']) # This property keeps track of files involved in each repo. Populated in mergeRepoSettings 
    QueueStatus = 'enabled'
}).AsReadOnly()

# Project defaults. Set this AsReadOnly() to prevent accidental overwrites of global defaults.
$Global:AZDMProjectSettings = ([ordered]@{
    Name = $Global:AZDMGlobalConfig['organization']['project']['Name'] ?? [string]::Empty
    Description = $Global:AZDMGlobalConfig['organization']['project']['Description'] ?? [string]::Empty
    Visibility = $Global:AZDMGlobalConfig['organization']['project']['Visibility'] ?? 'Private'
    ProcessTypeName = $Global:AZDMGlobalConfig['organization']['project']['ProcessTypeName'] ?? 'Basic'
    SourceControlType = $Global:AZDMGlobalConfig['organization']['project']['SourceControlType'] ?? 'Git'
    FileList = @($AZDMGlobalConfig['azdm_core']['rootfolderconfigfile']) # This property keeps track of files involved in each repo. Populated in mergeRepoSettings 
}).AsReadOnly()


# Import functions
Get-ChildItem -Path $Global:AZDMModuleRoot\moduleFunctions -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}