#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [string]$SeasonDirectory,
    [int]$StartingEpisode,
    [string]$HandBrakeCliPath,
    [string]$LibDvdCssPath,
    [string]$SeriesName = 'Everybody Loves Raymond',
    [string]$Preset = 'Fast 1080p30 (Default)'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:LogsRoot = Join-Path -Path $script:ProjectRoot -ChildPath 'logs'
$script:OutputRoot = Join-Path -Path $script:ProjectRoot -ChildPath 'output'
$script:LogFilePath = $null
$script:OriginalPath = $env:PATH

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    return (Resolve-Path -Path $Path).Path
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line

    if ($script:LogFilePath) {
        Add-Content -Path $script:LogFilePath -Value $line
    }
}

function Read-RequiredDirectory {
    param(
        [string]$Prompt
    )

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -Path $value -PathType Container)) {
            return (Resolve-Path -Path $value).Path
        }

        if (-not [string]::IsNullOrWhiteSpace($value) -and $value -match '(?i)^\s*Season\s+\d+\s*$') {
            $createdDirectory = Ensure-Directory -Path (Join-Path -Path $script:OutputRoot -ChildPath $value.Trim())
            Write-Host ('Created directory: {0}' -f $createdDirectory)
            return $createdDirectory
        }

        Write-Host 'Directory not found. Try again.'
    }
}

function Resolve-SeasonDirectoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    if (Test-Path -Path $InputPath -PathType Container) {
        return (Resolve-Path -Path $InputPath).Path
    }

    if ($InputPath -match '(?i)^\s*Season\s+\d+\s*$') {
        return Ensure-Directory -Path (Join-Path -Path $script:OutputRoot -ChildPath $InputPath.Trim())
    }

    throw ('Directory not found: {0}' -f $InputPath)
}

function Read-RequiredInteger {
    param(
        [string]$Prompt,
        [int]$DefaultValue = 0
    )

    while ($true) {
        $promptText = if ($DefaultValue -gt 0) { '{0} [{1}]' -f $Prompt, $DefaultValue } else { $Prompt }
        $value = Read-Host $promptText
        $parsedValue = 0

        if ([string]::IsNullOrWhiteSpace($value)) {
            if ($DefaultValue -gt 0) {
                return $DefaultValue
            }
        }
        elseif ([int]::TryParse($value, [ref]$parsedValue) -and $parsedValue -gt 0) {
            return $parsedValue
        }

        Write-Host 'Enter a positive whole number.'
    }
}

function Resolve-SeasonNumber {
    param(
        [string]$Path
    )

    $folderName = Split-Path -Path $Path -Leaf
    if ($folderName -match '(?i)\bseason\s+(?<Number>\d+)\b') {
        return [int]$Matches.Number
    }

    return Read-RequiredInteger -Prompt 'Season number' -DefaultValue 0
}

function Resolve-HandBrakeCli {
    param(
        [string]$ExplicitPath
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates.Add($ExplicitPath)
    }

    $command = Get-Command -Name 'HandBrakeCLI.exe', 'HandBrakeCLI' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $commandPath = $null
        if ($command.PSObject.Properties['Path']) {
            $commandPath = $command.Path
        }
        elseif ($command.Source) {
            $commandPath = $command.Source
        }
        elseif ($command.Definition) {
            $commandPath = $command.Definition
        }

        if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
            $candidates.Add($commandPath)
        }
    }

    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $candidates.Add((Join-Path -Path $root -ChildPath 'HandBrake\HandBrakeCLI.exe'))
            $candidates.Add((Join-Path -Path $root -ChildPath 'HandBrakeCLI.exe'))
        }
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -Path $candidate -PathType Leaf)) {
            return (Resolve-Path -Path $candidate).Path
        }
    }

    throw 'HandBrakeCLI.exe was not found. Install HandBrake CLI or pass -HandBrakeCliPath.'
}

function Normalize-PresetName {
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $Name
    }

    return ($Name -replace '\s*\(Default\)\s*$', '').Trim()
}

function Resolve-LibDvdCssDirectory {
    param(
        [string]$ExplicitPath,
        [string]$HandBrakeCli
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if ((Test-Path -Path $ExplicitPath -PathType Container)) {
            $candidates.Add((Join-Path -Path $ExplicitPath -ChildPath 'libdvdcss-2.dll'))
        }
        else {
            $candidates.Add($ExplicitPath)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($HandBrakeCli)) {
        $handBrakeDirectory = Split-Path -Path $HandBrakeCli -Parent
        $candidates.Add((Join-Path -Path $handBrakeDirectory -ChildPath 'libdvdcss-2.dll'))
    }

    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $candidates.Add((Join-Path -Path $root -ChildPath 'VideoLAN\VLC\libdvdcss-2.dll'))
            $candidates.Add((Join-Path -Path $root -ChildPath 'HandBrake\libdvdcss-2.dll'))
        }
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -Path $candidate -PathType Leaf)) {
            return (Split-Path -Path $candidate -Parent)
        }
    }

    return $null
}

function Initialize-LibDvdCssSupport {
    param(
        [string]$HandBrakeCli,
        [string]$ExplicitPath
    )

    $directory = Resolve-LibDvdCssDirectory -ExplicitPath $ExplicitPath -HandBrakeCli $HandBrakeCli
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        if ($env:PATH -notlike ('*' + $directory + '*')) {
            $env:PATH = '{0};{1}' -f $directory, $env:PATH
        }

        Write-Log ('libdvdcss path added: {0}' -f $directory)
        return $true
    }

    Write-Log 'libdvdcss was not found on a common path.'
    return $false
}

function Get-LoadedDvdDrive {
    $drives = @(Get-CimInstance -ClassName Win32_CDROMDrive | Where-Object { $_.MediaLoaded -eq $true })

    if ($drives.Count -eq 0) {
        throw 'No optical drive with media loaded was found.'
    }

    if ($drives.Count -eq 1) {
        return ((($drives[0].Drive).TrimEnd('\')) + '\')
    }

    Write-Host 'Multiple loaded optical drives were found:'
    for ($index = 0; $index -lt $drives.Count; $index++) {
        Write-Host ('[{0}] {1} {2}' -f ($index + 1), $drives[$index].Drive, $drives[$index].Name)
    }

    while ($true) {
        $choice = Read-Host 'Select a drive number'
        $selected = 0
        if ([int]::TryParse($choice, [ref]$selected)) {
            if ($selected -ge 1 -and $selected -le $drives.Count) {
                return ((($drives[$selected - 1].Drive).TrimEnd('\')) + '\')
            }
        }

        Write-Host 'Enter one of the listed numbers.'
    }
}

function Convert-SecondsToDuration {
    param(
        [int]$Seconds
    )

    $timeSpan = [TimeSpan]::FromSeconds($Seconds)
    return ('{0:00}:{1:00}:{2:00}' -f [int]$timeSpan.TotalHours, $timeSpan.Minutes, $timeSpan.Seconds)
}

function Convert-HandBrakeEtaToSeconds {
    param(
        [string]$EtaText
    )

    if ([string]::IsNullOrWhiteSpace($EtaText)) {
        return $null
    }

    if ($EtaText -match '^(?<Hours>\d+)h(?<Minutes>\d+)m(?<Seconds>\d+)s$') {
        return ([int]$Matches.Hours * 3600) + ([int]$Matches.Minutes * 60) + [int]$Matches.Seconds
    }

    return $null
}

function Write-HandBrakeProgress {
    param(
        [string]$Line,
        [string]$Activity,
        [int]$ProgressId
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return
    }

    if ($Line -match 'Encoding: task (?<Task>\d+) of (?<Total>\d+), (?<Percent>\d+(?:\.\d+)?) %(?:.*?ETA (?<Eta>\d+h\d+m\d+s))?') {
        $percent = [double]$Matches.Percent
        $etaText = $Matches.Eta
        $etaSeconds = Convert-HandBrakeEtaToSeconds -EtaText $etaText

        $status = 'Encoding: task {0} of {1}, {2:N2} %' -f $Matches.Task, $Matches.Total, $percent
        if (-not [string]::IsNullOrWhiteSpace($etaText)) {
            $status = '{0} ETA {1}' -f $status, $etaText
        }

        $progressParameters = @{
            Id              = $ProgressId
            Activity        = $Activity
            Status          = $status
            PercentComplete = [math]::Max(0, [math]::Min(100, $percent))
        }

        if ($null -ne $etaSeconds -and $etaSeconds -ge 0) {
            $progressParameters.SecondsRemaining = $etaSeconds
        }

        Write-Progress @progressParameters
    }
}

function Write-HandBrakeProgressFromText {
    param(
        [string]$Text,
        [string]$Activity,
        [int]$ProgressId,
        [hashtable]$State
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $pattern = 'Encoding: task (?<Task>\d+) of (?<Total>\d+), (?<Percent>\d+(?:\.\d+)?) %(?:.*?ETA (?<Eta>\d+h\d+m\d+s))?'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -eq 0) {
        return
    }

    $latest = $matches[$matches.Count - 1].Value
    if ($State.LastToken -eq $latest) {
        return
    }

    $State.LastToken = $latest
    Write-HandBrakeProgress -Line $latest -Activity $Activity -ProgressId $ProgressId
}

function Get-Median {
    param(
        [int[]]$Values
    )

    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) {
        return 0
    }

    $middle = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        return [int]$sorted[$middle]
    }

    return [int][math]::Round(($sorted[$middle - 1] + $sorted[$middle]) / 2)
}

function Parse-HandBrakeScanTitles {
    param(
        [string[]]$Lines
    )

    $titles = New-Object System.Collections.Generic.List[object]
    $current = $null

    foreach ($line in $Lines) {
        if ($line -match '^\s*\+\s*title\s+(?<Number>\d+):') {
            if ($null -ne $current) {
                $titles.Add([pscustomobject]$current)
            }

            $current = [ordered]@{
                Number         = [int]$Matches.Number
                DurationSeconds = $null
                Duration       = $null
                ChapterCount   = $null
                RawLines       = New-Object System.Collections.Generic.List[string]
            }

            $current.RawLines.Add($line)
            continue
        }

        if ($null -ne $current) {
            $current.RawLines.Add($line)

            if ($line -match 'duration:\s*(?<Hours>\d+):(?<Minutes>\d+):(?<Seconds>\d+)') {
                $durationSeconds = ([int]$Matches.Hours * 3600) + ([int]$Matches.Minutes * 60) + [int]$Matches.Seconds
                $current.DurationSeconds = $durationSeconds
                $current.Duration = Convert-SecondsToDuration -Seconds $durationSeconds
            }
            elseif ($line -match 'chapters:\s*(?<Count>\d+)') {
                $current.ChapterCount = [int]$Matches.Count
            }
        }
    }

    if ($null -ne $current) {
        $titles.Add([pscustomobject]$current)
    }

    return @($titles | Sort-Object Number)
}

function Select-EpisodeTitles {
    param(
        [object[]]$Titles
    )

    $Titles = @($Titles | ForEach-Object {
        if ($_ -is [System.Array]) {
            $_
        }
        else {
            $_
        }
    })

    $withDurations = @($Titles | Where-Object { $_.DurationSeconds -ne $null } | Sort-Object Number)
    if ($withDurations.Count -eq 0) {
        return [pscustomobject]@{
            Selected   = @()
            Ambiguous  = $true
            Reason     = 'No title durations were parsed from the scan output.'
        }
    }

    $longTitles = @($withDurations | Where-Object { $_.DurationSeconds -ge 900 })
    if ($longTitles.Count -eq 0) {
        return [pscustomobject]@{
            Selected   = @()
            Ambiguous  = $true
            Reason     = 'No episode-length titles were found.'
        }
    }

    $medianDuration = Get-Median -Values @($longTitles.DurationSeconds)
    $threshold = [math]::Max(900, [int][math]::Round($medianDuration * 0.85))

    $selected = @($withDurations | Where-Object { $_.DurationSeconds -ge $threshold } | Sort-Object Number)
    $excludedLongTitles = @($longTitles | Where-Object { $_.DurationSeconds -lt $threshold })

    $reasons = New-Object System.Collections.Generic.List[string]

    if ($selected.Count -eq 0) {
        $reasons.Add('No titles matched the episode cluster.')
    }

    if ($excludedLongTitles.Count -gt 0) {
        $reasons.Add('Some medium-length titles were excluded from the main cluster.')
    }

    if ($selected.Count -gt 0) {
        $durations = @($selected.DurationSeconds)
        $spread = ($durations | Measure-Object -Maximum).Maximum - ($durations | Measure-Object -Minimum).Minimum
        if ($spread -gt 600) {
            $reasons.Add('Selected titles vary too much in duration for a confident auto-selection.')
        }
    }

    $ambiguous = $reasons.Count -gt 0
    $reasonText = if ($ambiguous) { $reasons -join ' ' } else { $null }

    return [pscustomobject]@{
        Selected  = $selected
        Ambiguous = $ambiguous
        Reason    = $reasonText
    }
}

function Get-EpisodeTemplate {
    param(
        [string]$Path,
        [string]$SeriesName
    )

    $existingFiles = @(Get-ChildItem -Path $Path -File -Filter '*.mp4' -ErrorAction SilentlyContinue)
    if (@($existingFiles).Count -eq 0) {
        $seasonNumber = Resolve-SeasonNumber -Path $Path
        $seasonText = $seasonNumber.ToString('D2')

        return [pscustomobject]@{
            Prefix      = '{0} - s{1}e' -f $SeriesName, $seasonText
            Width       = 2
            Suffix      = ''
            NextEpisode = 1
        }
    }

    $matches = foreach ($file in $existingFiles) {
        if ($file.BaseName -match '^(?<Prefix>.*?)(?<Number>\d+)(?<Suffix>[^\d]*)$') {
            [pscustomobject]@{
                File   = $file
                Prefix = $Matches.Prefix
                Number = [int]$Matches.Number
                Width  = $Matches.Number.Length
                Suffix = $Matches.Suffix
            }
        }
    }

    $matches = @($matches)
    if (@($matches).Count -eq 0) {
        return $null
    }

    $sample = $matches | Sort-Object Number | Select-Object -Last 1
    $suffix = $sample.Suffix
    if ($suffix -match '[A-Za-z0-9]') {
        $suffix = ''
    }

    return [pscustomobject]@{
        Prefix = $sample.Prefix
        Width  = $sample.Width
        Suffix = $suffix
        NextEpisode = ($sample.Number + 1)
    }
}

function New-EpisodeFileName {
    param(
        [object]$Template,
        [int]$EpisodeNumber
    )

    if ($null -eq $Template) {
        return ('Episode {0}.mp4' -f $EpisodeNumber)
    }

    $formattedNumber = $EpisodeNumber.ToString('D{0}' -f $Template.Width)
    return '{0}{1}{2}.mp4' -f $Template.Prefix, $formattedNumber, $Template.Suffix
}

function Invoke-HandBrakeScan {
    param(
        [string]$HandBrakeCli,
        [string]$InputPath
    )

    $attempts = 2
    $lastOutput = $null
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        Write-Log ('Scanning disc (attempt {0}/{1})...' -f $attempt, $attempts)
        $result = Invoke-HandBrakeProcess -HandBrakeCli $HandBrakeCli -Arguments @('--title', '0', '--scan', '--input', $InputPath)
        $text = $result.Output
        $exitCode = $result.ExitCode
        $lastOutput = $text

        if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }

        Write-Log ('Scan attempt {0} failed with exit code {1}.' -f $attempt, $exitCode)
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-Log 'HandBrake scan output:'
            foreach ($line in ($text -split '\r?\n')) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-Log $line
                }
            }
        }
        if ($attempt -lt $attempts) {
            Start-Sleep -Seconds 3
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($lastOutput) -and $lastOutput -match 'Encrypted DVD support unavailable') {
        throw 'HandBrakeCLI cannot decrypt this DVD because libdvdcss is not available to it. Put libdvdcss-2.dll beside HandBrakeCLI.exe or on PATH, then try again.'
    }

    if (-not [string]::IsNullOrWhiteSpace($lastOutput)) {
        throw ('HandBrakeCLI scan failed. Last output: {0}' -f ($lastOutput -replace '\s+', ' ').Trim())
    }

    throw 'HandBrakeCLI scan failed. If this disc usually needs VLC opened first, try that workaround and run the script again.'
}

function Invoke-HandBrakeProcess {
    param(
        [string]$HandBrakeCli,
        [string[]]$Arguments
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        $quotedArguments = @(
            foreach ($argument in $Arguments) {
                if ($null -eq $argument) { continue }
                $text = [string]$argument
                if ($text -match '[\s"]') {
                    '"{0}"' -f ($text -replace '"', '\"')
                }
                else {
                    $text
                }
            }
        ) -join ' '

        $process = Start-Process -FilePath $HandBrakeCli `
            -ArgumentList $quotedArguments `
            -NoNewWindow `
            -PassThru `
            -Wait `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        $stdout = if (Test-Path -Path $stdoutFile) { Get-Content -Path $stdoutFile -Raw } else { '' }
        $stderr = if (Test-Path -Path $stderrFile) { Get-Content -Path $stderrFile -Raw } else { '' }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = @($stdout, $stderr) -join [Environment]::NewLine
        }
    }
    finally {
        Remove-Item -Path $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    }
}

function Invoke-HandBrakeProcessWithProgress {
    param(
        [string]$HandBrakeCli,
        [string[]]$Arguments,
        [string]$ProgressActivity
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $outputLines = [System.Collections.Generic.List[string]]::new()
    $progressId = 1
    $progressState = @{ LastToken = $null }
    $stdoutSnapshot = ''
    $stderrSnapshot = ''

    try {
        $quotedArguments = @(
            foreach ($argument in $Arguments) {
                if ($null -eq $argument) { continue }
                $text = [string]$argument
                if ($text -match '[\s"]') {
                    '"{0}"' -f ($text -replace '"', '\"')
                }
                else {
                    $text
                }
            }
        ) -join ' '

        $process = Start-Process -FilePath $HandBrakeCli `
            -ArgumentList $quotedArguments `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 250

            $currentStdout = if (Test-Path -Path $stdoutFile) { Get-Content -Path $stdoutFile -Raw } else { '' }
            $currentStderr = if (Test-Path -Path $stderrFile) { Get-Content -Path $stderrFile -Raw } else { '' }

            if ($currentStdout.Length -gt $stdoutSnapshot.Length) {
                $outputLines.Add($currentStdout.Substring($stdoutSnapshot.Length))
            }
            if ($currentStderr.Length -gt $stderrSnapshot.Length) {
                $outputLines.Add($currentStderr.Substring($stderrSnapshot.Length))
            }

            $stdoutSnapshot = $currentStdout
            $stderrSnapshot = $currentStderr

            Write-HandBrakeProgressFromText -Text (@($currentStdout, $currentStderr) -join [Environment]::NewLine) -Activity $ProgressActivity -ProgressId $progressId -State $progressState
        }

        $finalStdout = if (Test-Path -Path $stdoutFile) { Get-Content -Path $stdoutFile -Raw } else { '' }
        $finalStderr = if (Test-Path -Path $stderrFile) { Get-Content -Path $stderrFile -Raw } else { '' }

        if ($finalStdout.Length -gt $stdoutSnapshot.Length) {
            $outputLines.Add($finalStdout.Substring($stdoutSnapshot.Length))
        }
        if ($finalStderr.Length -gt $stderrSnapshot.Length) {
            $outputLines.Add($finalStderr.Substring($stderrSnapshot.Length))
        }

        Write-HandBrakeProgressFromText -Text (@($finalStdout, $finalStderr) -join [Environment]::NewLine) -Activity $ProgressActivity -ProgressId $progressId -State $progressState

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = @($outputLines.ToArray()) -join [Environment]::NewLine
        }
    }
    finally {
        Write-Progress -Id $progressId -Activity $ProgressActivity -Completed
        Remove-Item -Path $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    }
}

function Confirm-Selection {
    param(
        [object[]]$Titles,
        [object[]]$Selected,
        [string]$Reason
    )

    Write-Host ''
    Write-Host 'Title scan results:'
    foreach ($title in $Titles) {
        $flag = if (@($Selected.Number) -contains $title.Number) { 'yes' } else { 'no' }
        $duration = if ($title.Duration) { $title.Duration } else { 'unknown' }
        Write-Host ('Title {0}: {1} selected={2}' -f $title.Number, $duration, $flag)
    }

    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        Write-Host ''
        Write-Host ('Selection is ambiguous: {0}' -f $Reason)
    }

    while ($true) {
        $answer = Read-Host 'Proceed with the selected titles? [Y/n/edit]'
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(y|yes)$') {
            return 'Yes'
        }

        if ($answer -match '^(n|no)$') {
            return 'No'
        }

        if ($answer -match '^(e|edit)$') {
            return 'Edit'
        }

        Write-Host 'Enter Y, N, or edit.'
    }
}

function Read-ManualTitleSelection {
    param(
        [object[]]$Titles
    )

    $availableNumbers = @($Titles.Number)

    while ($true) {
        $rawValue = Read-Host 'Enter title numbers separated by commas (example: 1,2,3)'
        if ([string]::IsNullOrWhiteSpace($rawValue)) {
            Write-Host 'Enter at least one title number.'
            continue
        }

        $requestedNumbers = @(
            $rawValue -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object {
                    $parsed = 0
                    if ([int]::TryParse($_, [ref]$parsed) -and $parsed -gt 0) {
                        $parsed
                    }
                    else {
                        $null
                    }
                } |
                Where-Object { $_ -ne $null }
        )

        if ($requestedNumbers.Count -eq 0) {
            Write-Host 'Enter one or more positive whole numbers.'
            continue
        }

        $invalidNumbers = @($requestedNumbers | Where-Object { $availableNumbers -notcontains $_ })
        if ($invalidNumbers.Count -gt 0) {
            Write-Host ('Unknown title number(s): {0}' -f ($invalidNumbers -join ', '))
            continue
        }

        $selected = foreach ($title in $Titles) {
            if ($requestedNumbers -contains $title.Number) {
                $title
            }
        }

        if (@($selected).Count -eq 0) {
            Write-Host 'No matching titles were selected.'
            continue
        }

        return @($selected)
    }
}

if ([string]::IsNullOrWhiteSpace($SeasonDirectory)) {
    $SeasonDirectory = Read-RequiredDirectory -Prompt 'Season directory'
}
else {
    $SeasonDirectory = Resolve-SeasonDirectoryPath -InputPath $SeasonDirectory
}

Ensure-Directory -Path $script:LogsRoot | Out-Null
Ensure-Directory -Path $script:OutputRoot | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFilePath = Join-Path -Path $script:LogsRoot -ChildPath ('handbrake-rip-{0}.log' -f $timestamp)

Write-Log ('Season directory: {0}' -f $SeasonDirectory)
Write-Log ('Series name: {0}' -f $SeriesName)
Write-Log ('Logs directory: {0}' -f $script:LogsRoot)
Write-Log ('Output root: {0}' -f $script:OutputRoot)

$handBrakeCli = Resolve-HandBrakeCli -ExplicitPath $HandBrakeCliPath
Write-Log ('HandBrakeCLI: {0}' -f $handBrakeCli)
$Preset = Normalize-PresetName -Name $Preset
Write-Log ('Preset: {0}' -f $Preset)

Initialize-LibDvdCssSupport -HandBrakeCli $handBrakeCli -ExplicitPath $LibDvdCssPath | Out-Null

$dvdDrive = Get-LoadedDvdDrive
Write-Log ('Loaded DVD drive: {0}' -f $dvdDrive)

$scanText = Invoke-HandBrakeScan -HandBrakeCli $handBrakeCli -InputPath $dvdDrive
Add-Content -Path $script:LogFilePath -Value ''
Add-Content -Path $script:LogFilePath -Value '=== HandBrake scan output ==='
Add-Content -Path $script:LogFilePath -Value $scanText
Add-Content -Path $script:LogFilePath -Value '=== End scan output ==='

$scanLines = @($scanText -split '\r?\n')
$titles = @(Parse-HandBrakeScanTitles -Lines $scanLines)
if (@($titles).Count -eq 0) {
    throw 'No titles were parsed from the HandBrake scan output.'
}

Write-Log ('Parsed {0} title(s).' -f (@($titles).Count))

$selection = Select-EpisodeTitles -Titles $titles
$selectedTitles = @($selection.Selected)

if ($selection.Ambiguous) {
    $choice = Confirm-Selection -Titles $titles -Selected $selectedTitles -Reason $selection.Reason
    if ($choice -eq 'No') {
        Write-Log 'User declined to proceed.'
        exit 0
    }

    if ($choice -eq 'Edit') {
        $selectedTitles = @(Read-ManualTitleSelection -Titles $titles)
        $selectedNumbers = @($selectedTitles.Number) -join ', '
        Write-Log ('User manually selected title(s): {0}' -f $selectedNumbers)
    }
}
else {
    Write-Log 'Title selection was clear; continuing without confirmation.'
}

if (@($selectedTitles).Count -eq 0) {
    throw 'No episode titles were selected.'
}

$template = Get-EpisodeTemplate -Path $SeasonDirectory -SeriesName $SeriesName
$startingEpisodeNumber = $StartingEpisode
if ($startingEpisodeNumber -le 0 -and $null -ne $template) {
    $startingEpisodeNumber = $template.NextEpisode
}

if ($startingEpisodeNumber -le 0) {
    $startingEpisodeNumber = Read-RequiredInteger -Prompt 'Starting episode number' -DefaultValue 1
}

Write-Log ('Starting episode number: {0}' -f $startingEpisodeNumber)

for ($index = 0; $index -lt @($selectedTitles).Count; $index++) {
    $episodeNumber = $startingEpisodeNumber + $index
    $outputName = New-EpisodeFileName -Template $template -EpisodeNumber $episodeNumber
    $outputPath = Join-Path -Path $SeasonDirectory -ChildPath $outputName
    $titleNumber = $selectedTitles[$index].Number

    if (Test-Path -Path $outputPath) {
        throw ('Output file already exists: {0}' -f $outputPath)
    }

    Write-Log ('Encoding title {0} to {1}' -f $titleNumber, $outputPath)
    $encodeResult = Invoke-HandBrakeProcessWithProgress -HandBrakeCli $handBrakeCli -ProgressActivity ('Encoding title {0}' -f $titleNumber) -Arguments @(
        '--preset', $Preset,
        '--format', 'av_mp4',
        '--input', $dvdDrive,
        '--title', [string]$titleNumber,
        '--output', $outputPath
    )
    $encodeExitCode = $encodeResult.ExitCode

    if (-not [string]::IsNullOrWhiteSpace($encodeResult.Output)) {
        Add-Content -Path $script:LogFilePath -Value ''
        Add-Content -Path $script:LogFilePath -Value ('=== Encode output for title {0} ===' -f $titleNumber)
        Add-Content -Path $script:LogFilePath -Value $encodeResult.Output
        Add-Content -Path $script:LogFilePath -Value ('=== End encode output for title {0} ===' -f $titleNumber)
    }

    if ($encodeExitCode -ne 0) {
        throw ('HandBrakeCLI failed while encoding title {0}.' -f $titleNumber)
    }
}

Write-Log 'All selected titles were encoded successfully.'
