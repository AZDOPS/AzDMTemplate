[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$SettingsFile
)

$settingsOutput = Get-Content $SettingsFile | ConvertFrom-Json -AsHashtable

# Set rootfolder to fixed path
$settingsOutput['azdm_core']['rootfolder'] = Join-Path -Path (Get-Item $SettingsFile).Directory.FullName -ChildPath $settingsOutput['azdm_core']['rootfolder']
$settingsOutput['azdm_core']['rootfolderconfigfile'] = Join-Path -path $settingsOutput['azdm_core']['rootfolder'] -ChildPath "config.json"
# Append project root settings
$rootConfig = Get-Content $settingsOutput['azdm_core']['rootfolderconfigfile'] | ConvertFrom-Json -AsHashtable
foreach ($k in $rootConfig.keys) {
    $settingsOutput.Add($k, $rootConfig[$k])
}

# Append projects
$projectsToRun = Get-ChildItem $settingsOutput['azdm_core']['rootfolder'] -Directory | Where-Object {
    $_.BaseName -notin $settingsOutput['core']['excludeProjects']
}
$projOutput = @{}
foreach ($k in $projectsToRun.BaseName) {
    $projConfig = Get-Content (Join-Path -path $settingsOutput['azdm_core']['rootfolder'] -ChildPath $k -AdditionalChildPath "$k.json") | ConvertFrom-Json -AsHashtable
    $projOutput.Add($k, $projConfig)
}
$settingsOutput.Add('projects', $projOutput)

$settingsOutput
