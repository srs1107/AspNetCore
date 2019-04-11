<#
.SYNOPSIS
    Installs or updates Visual Studio on a local developer machine.
.DESCRIPTION
    This installs Visual Studio along with all the workloads required to contribute to this repository.
.PARAMETER Edition
    Selects which 'offering' of Visual Studio to install. Must be one of these values:
        BuildTools
        Community
        Professional
        Enterprise (the default)
.PARAMETER InstallPath
    The location on disk where Visual Studio should be installed or updated. Default path is location of latest
    existing installation of the specified edition, if any. If that VS edition is not currently installed, default
    path is '${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\`$Edition".
.PARAMETER Passive
    Run the installer without requiring interaction.
.PARAMETER Quiet
    Run the installer without UI and wait for installation to complete.
.LINK
    https://visualstudio.com
    https://github.com/aspnet/AspNetCore/blob/master/docs/BuildFromSource.md
.EXAMPLE
    To install VS 2019 Enterprise, run this command in PowerShell:

        .\InstallVisualStudio.ps1
#>
param(
    [ValidateSet('BuildTools','Community', 'Professional', 'Enterprise')]
    [string]$Edition = 'Enterprise',
    [string]$InstallPath,
    [switch]$Passive,
    [switch]$Quiet
)

if ($Passive -and $Quiet) {
    Write-Host "The -Passive and -Quiet options cannot be used together." -f Red
    Write-Host "Run ``Get-Help $PSCommandPath`` for more details." -f Red
    exit 1
}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1

$intermedateDir = "$PSScriptRoot\obj"
mkdir $intermedateDir -ErrorAction Ignore | Out-Null

$bootstrapper = "$intermedateDir\vsinstaller.exe"
$ProgressPreference = 'SilentlyContinue' # Workaround PowerShell/PowerShell#2138
Invoke-WebRequest -Uri "https://aka.ms/vs/16/release/vs_$($Edition.ToLowerInvariant()).exe" -OutFile $bootstrapper

$responseFile = "$PSScriptRoot\vs.json"
if ("$Edition" -eq "BuildTools") {
    $responseFile = "$PSScriptRoot\vs.buildtools.json"
}

$channelId = (Get-Content $responseFile | ConvertFrom-Json).channelId

$productId = "Microsoft.VisualStudio.Product.$Edition"
if (-not $InstallPath) {
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere)
    {
        $installations = & $vsWhere -version '[16,17)' -format json -sort -prerelease -products $productId | ConvertFrom-Json
        foreach ($installation in $installations) {
            Write-Host "Found '$($installation.installationName)' in '$($installation.installationPath)', channel = '$($installation.channelId)'"
            if ($installation.channelId -eq $channelId) {
                $InstallPath = $installation.installationPath
                break
            }
        }
    }
}

if (-not $InstallPath) {
    $InstallPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\$Edition"
}

# no backslashes - this breaks the installer
$InstallPath = $InstallPath.TrimEnd('\')

[string[]] $arguments = @()
if (Test-path $InstallPath) {
    $arguments += 'modify'
}

$arguments += `
    '--productId', $productId, `
    '--installPath', "`"$InstallPath`"", `
    '--in', "`"$responseFile`"", `
    '--norestart'

if ($Passive) {
    $arguments += '--passive'
}
if ($Quiet) {
    $arguments += '--quiet', '--wait'
}

Write-Host ""
Write-Host "Installing Visual Studio 2019 $Edition" -f Magenta
Write-Host ""
Write-Host "Running '$bootstrapper $arguments'"

foreach ($i in 0, 1, 2) {
    $process = Start-Process -FilePath "$bootstrapper" -ArgumentList $arguments -ErrorAction Continue -PassThru `
        -RedirectStandardError "$intermedateDir\errors.txt" -Verbose -Wait
    Write-Host "Exit code = $($process.ExitCode)."
    if ($process.ExitCode -eq 0) {
        break
    } else {
        # https://docs.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio#error-codes
        if ($process.ExitCode -eq 3010) {
            Write-Error "Installation requires restart to finish the VS update."
            break
        }
        elseif ($process.ExitCode -eq 5007) {
            Write-Error "Operation was blocked - the computer does not meet the requirements."
            break
        }
        elseif (($process.ExitCode -eq 5004) -or ($process.ExitCode -eq 1602)) {
            Write-Error "Operation was canceled."
        }
        else {
            Write-Error "Installation failed for an unknown reason."
        }

        Write-Host ""
        WriteHost "Errors:"
        Get-Content "$intermedateDir\errors.txt" | Write-Error
        Write-Host ""

        $bootstrapperLogs = Get-ChildItem $env:Temp\dd_bootstrapper_*.log |Sort-Object CreationTime
        if ($bootstrapperLogs.Count -ne 0) {
            $bootstrapperLog = $bootstrapperLogs[$bootstrapperLogs.Count - 1]
            Write-Host "${bootstraperLog}:"
            Get-Content "$bootstrapperLog"
            Write-Host ""
        }

        $clientLogs = Get-ChildItem $env:Temp\dd_client_*.log |Sort-Object CreationTime
        if ($clientLogs.Count -ne 0) {
            $clientLog = $clientLogs[$clientLogs.Count - 1]
            Write-Host "${clientLog}:"
            Get-Content "$clientLog"
            Write-Host ""
        }

        $setupLogs = Get-ChildItem $env:Temp\dd_setup_*.log |Sort-Object CreationTime
        if ($setupLogs.Count -ne 0) {
            $setupLog = $setupLogs[$bootstrapperLogs.Count - 1]
            Write-Host "${setupLog}:"
            Get-Content "$setupLog"
            Write-Host ""
        }

        Write-Host "Retrying..."
    }
}

Remove-Item "$intermedateDir\errors.txt" -errorAction SilentlyContinue
exit $process.ExitCode
