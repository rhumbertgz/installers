$DOWNLOADS_PATH = "mlaas-downloads"
$TOOL_NAME = "mlaas-cli"

function Cleanup {
    if (Test-Path -Path $DOWNLOADS_PATH) {
        Remove-Item -Path $DOWNLOADS_PATH -Recurse -Force
    }
}

# Register the cleanup function to run on exit
$global:cleanupAction = { Cleanup }
Register-EngineEvent PowerShell.Exiting -Action $cleanupAction

function Log-Info {
    param($Message)
    Write-Host $Message
}

function Log-Error {
    param($Message)
    Write-Host $Message -ForegroundColor Red
}

function Log-Warn {
    param($Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Verify-ScoopInstallation{
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        if ($?) {
            Verify-GitInstallation
            & scoop bucket add versions
        } else {
            Log-Error "Scoop could not be installed, but it is needed to install Python. See log messages for more info."
            exit 1
        }
    }
}

function Verify-GitInstallation {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        & scoop install git
        if (-not $?) {
            Log-Error "Git could not be installed but it is needed by Scoop. See log messages for more info."
            exit 1
        }
    } 
}

function Verify-RefreshEnvInstallation {
    if (-not (Get-Command RefreshEnv -ErrorAction SilentlyContinue)) {
        & scoop install refreshenv
        if (-not $?) {
            Log-Error "refreshenv could not be installed. Open a new the terminal to reload the user's PATH environment variable."
            exit 1
        }
    } 
    RefreshEnv
}

function Verify-PipxInstallation{
    Verify-RefreshEnvInstallation
    if (-not (Get-Command pipx -ErrorAction SilentlyContinue)) {
        Verify-ScoopInstallation
        Log-Warn "pipx is not installed, but it is required to install the MLaaS CLI."
        $RESPONSE = Read-Host "Do you want to install pipx? (Yes/No)"

        if ($RESPONSE -eq "Yes" -or $RESPONSE -eq "Y") {
            & scoop install pipx
            if ($?) {
                Verify-GitInstallation
            } else {
                Log-Error "pipx could not be installed. See log messages for more info."
                exit 1
            }
            & pipx ensurepath

        }   elseif ($RESPONSE -eq "No" -or $RESPONSE -eq "N"){
            Log-Error "Aborting MLaaS CLI installation."
            exit 1

        } else {
            Log-Error "Invalid response, please try again."
            exit 1
        }  
    } 
}

function Install-Python {
    try {
        $OPTIONS = @("3.11", "3.12", "latest")
        for ($i = 0; $i -lt $OPTIONS.Count; $i++){
            Write-Host "$($i + 1). $($OPTIONS[$i])"
        }

        $SELECTION = Read-Host "Please select an option (1-$($OPTIONS.Count))"
        Verify-ScoopInstallation

        if ($SELECTION -gt 0 -and $SELECTION -le $OPTIONS.Count-1) {
            $SELECTED_VERSION = $OPTIONS[$SELECTION - 1]
            $VERSION = $SELECTED_VERSION -replace "\.", ""
            $COMMAND = "scoop install python$VERSION"
            Invoke-Expression $COMMAND
        } elseif ($SELECTION -eq 3) {
            Log-Info "Installing latest Python version ..."
            & scoop install python
        } else {
            Log-Error "Invalid response, please try again."
            exit 1
        }
        $OUTPUT = & python --version 2>&1
        $VERSION = $OUTPUT -replace "Python ", ""
        return $VERSION
        
    } catch {
        Log-Error "Python could not be installed."
        Write-Host $_
        exit 1
    }    
}

function Get-PythonVersion {
    try {
        $OUTPUT = & python --version 2>&1
        if ($OUTPUT -like "*Python 3*") {
            $VERSION = $OUTPUT -replace "Python ", ""
            return $VERSION
        } else {
            Log-Warn "Python 3 is not installed."
            return Install-Python
        }
    } catch {
        return Install-Python
    }
}

function Verify-PythonInstallation {
    $PYTHON_VERSION = Get-PythonVersion
    # The above is needed because sometimes shim's logs are unexpectable added to return value
    $PYTHON_VERSION = @"
    $PYTHON_VERSION
"@

    if ($PYTHON_VERSION -match "\((.*?)\)") {
        $PYTHON_VERSION = $matches[1]
    }

    $PYTHON_MAJOR, $PYTHON_MINOR, $PYTHON_PATCH = $PYTHON_VERSION  -split "\."

    if ([int]$PYTHON_MAJOR -lt 3 -or ([int]$PYTHON_MAJOR -eq 3 -and [int]$PYTHON_MINOR -lt 11)) {
        Log-Warn "Python 3.11 or newer is required. Current version: $PYTHON_VERSION"
        Install-Python
    }
}

function Install-Tool {      
    Verify-RefreshEnvInstallation  
    Log-Info "Installing MLaaS CLI v$PACKAGE_VERSION ..."

    if (Test-Path -Path $DOWNLOADS_PATH) {
        Remove-Item -Path $DOWNLOADS_PATH -Recurse -Force
    } else {
        New-Item -ItemType Directory -Path $DOWNLOADS_PATH | Out-Null
    }

    $PACKAGE_URL = "https://gitlabe2.ext.net.nokia.com/api/v4/projects/96502/packages/generic/mlaas-cli/${PACKAGE_VERSION}/mlaas_cli-${PACKAGE_VERSION}.tar.gz"
    $OUTPUT_PATH = "${DOWNLOADS_PATH}/mlaas_cli-${PACKAGE_VERSION}.tar.gz"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri $PACKAGE_URL -Headers @{ "PRIVATE-TOKEN" = $USER_TOKEN } -OutFile $OUTPUT_PATH -MaximumRedirection 10 -UseBasicParsing
        Unblock-File -Path $OUTPUT_PATH
    } catch {
        Log-Error "Failed to download file: $_"
        exit 1
    }
    
    & pipx install $OUTPUT_PATH --pip-args="--default-timeout=1000"
    & pipx ensurepath
    #& pipx install $TOOL_NAME --index-url=https://_token_:$USER_TOKEN@gitlabe2.ext.net.nokia.com/api/v4/projects/96468/packages/pypi/simple

    if ($?) {        
        Unblock-Cli        
        Write-Host
        Log-Info "MLaaS CLI installed successfully."
        Log-Info "Open a new terminal and try the CLI by typing 'mlaas' and hit the Enter key."
        Write-Host
        Log-Info "Press any key to close this window..."
        [System.Console]::ReadKey() | Out-Null
        Get-Process cmd | Stop-Process
    } else {
        Log-Error "MLaaS CLI could not be installed."
    }
}

function Unblock-Cli {
    $pipxList = & pipx list  
    $IS_MLAAS_INSTALLED = $pipxList -match "package $TOOL_NAME"
    if ($IS_MLAAS_INSTALLED) {     
        $regex = [regex]::new('(?<=\$PATH at ).*?(?= manual)')
        $match = $regex.Match($pipxList)
        if ($match.Success) {
            $BINARY_PATH = $match.Value
        } else {
            Log-Error "No binary path was found."
        }

        $MLAAS_PATH = $BINARY_PATH + "\mlaas.exe"

        # Remove MLaaS CLI from the Zone.Identifier ADS
        if (Test-Path -Path "$MLAAS_PATH:Zone.Identifier") {
            Remove-Item -Path "$MLAAS_PATH:Zone.Identifier"
            Log-Info "MLaaS CLI unblocked successfully."
        } 

        # Get the current PATH environment variable
        $CURRENT_PATH = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)

        # Check if the BINARY_PATH is already in the PATH variable
        if (-not $CURRENT_PATH.Contains($BINARY_PATH)) {
            Log-Info "Adding $BINARY_PATH to the user's PATH environment variable."
            [Environment]::SetEnvironmentVariable("PATH", $CURRENT_PATH + ";$BINARY_PATH", [System.EnvironmentVariableTarget]::User)
        } 
    }   
}

#########################################################################################
Log-Info "MLaaS CLI Installation Script v1.0.16"
if ([string]::IsNullOrEmpty($env:USER_TOKEN)) {
    Log-Error "env:USER_TOKEN was not found."
    exit 1
}

$PACKAGE_VERSION = "1.0.1" 
if ($env:PACKAGE_VERSION) {
    $PACKAGE_VERSION = $env:PACKAGE_VERSION
}

$USER_TOKEN = $env:USER_TOKEN
$PROXY_SERVER = "http://135.245.192.7:8000"

# Set the proxy for the current session
$Env:http_proxy = $PROXY_SERVER
$Env:https_proxy = $PROXY_SERVER

# Verify Python and Pipx are installed
Verify-PythonInstallation
Verify-PipxInstallation

if (-not (Get-Command mlaas -ErrorAction SilentlyContinue)) {
    Log-Warn "MLaaS CLI not installed."
    Install-Tool
} else {
    $OUTPUT = & mlaas --version
    $MLAAS_VERSION = $OUTPUT -replace "mlaas, version ", ""
    if ($PACKAGE_VERSION -eq $MLAAS_VERSION) {
        Log-Info "The v$PACKAGE_VERSION of the MLaaS CLI is already installed."
    } else {
        Log-Info "Uninstalling MLaaS CLI v$MLAAS_VERSION ..."
        & pipx uninstall $TOOL_NAME
        Log-Info "Installing CLI v$PACKAGE_VERSION ..."
        Install-Tool      
    }
}

