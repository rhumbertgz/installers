$DOWNLOADS_PATH = "mlaas-downloads"

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
    Write-Host "[info] $Message"
}

function Log-Error {
    param($Message)
    Write-Host "[error] $Message" -ForegroundColor Red
}

function Verify-ScoopInstallation{
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Log-Info "Scoop is not installed. Installing Scoop..."
        # Download and install Scoop
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        if ($?) {
            Log-Info "Scoop installed successfully."
            Verify-GitInstallation
        } else {
            Log-Error "Scoop could not be installed. See log messages for more info."
            exit 1
        }
        
    } else {
        $SCOOP_VERSION = & scoop --version
        Log-Info "Using found scoop version: $SCOOP_VERSION"
    }
}

function Verify-GitInstallation {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Log-Info "Git is not installed. Installing Git..."
        & scoop install git
        if ($?) {
            Log-Info "Git installed successfully."
        } else {
            Log-Error "Git could not be installed but it is needed by Scoop. See log messages for more info."
            exit 1
        }
    } else {
        $GIT_VERSION = & scoop --version
        Log-Info "Using found git version: $GIT_VERSION"
    }
}

function Verify-PipxInstallation{
    if (-not (Get-Command pipx -ErrorAction SilentlyContinue)) {
        Verify-ScoopInstallation
        Log-Info "pipx is not installed. Installing pipx..."
        & scoop install pipx
        if ($?) {
            Log-Info "pipx installed successfully."
            Verify-GitInstallation
        } else {
            Log-Error "pipx could not be installed. See log messages for more info."
            exit 1
        }
        & pipx ensurepath
    } else {
        $PIPX_VERSION = & pipx --version
        Log-Info "Using found pipx version: $PIPX_VERSION"
    }
}

function Install-Python {
    Verify-ScoopInstallation
    Write-Output "Python is not installed or an older version was found. Installing Python ..."
    try {
        & scoop install python
        $VERSION = python --version 2>&1
        Log-Info "$VERSION installed successfully."
        return $VERSION -replace 'Python ', ''
    } catch {
        Log-Error "Python could not be installed."
        exit 1
    }    
}

function Get-PythonVersion {
    try {
        $VERSION = python --version 2>&1
        if ($VERSION -like "*Python 3*") {
            return $VERSION -replace 'Python ', ''
        } else {
            return Install-Python 
        }
    } catch {
        return Install-Python
    }
}

function Verify-PythonInstallation {
    $PYTHON_VERSION = Get-PythonVersion
    $PYTHON_MAJOR, $PYTHON_MINOR, $PYTHON_PATCH = $PYTHON_VERSION -split '\.'


    if ([int]$PYTHON_MAJOR -lt 3 -or ([int]$PYTHON_MAJOR -eq 3 -and [int]$PYTHON_MINOR -lt 9)) {
        Log-Info "Python 3.9 or newer is required. Current version: $PYTHON_VERSION"
        Install-Python
    }else {
        Log-Info "Using found Python version: $PYTHON_VERSION"
    }
}

function Show-MlaasHelp {
    Write-Host
    & mlaas --help
}

function Install-Tool {        
    if (Test-Path -Path $DOWNLOADS_PATH) {
        Remove-Item -Path $DOWNLOADS_PATH -Recurse -Force
    } else {
        New-Item -ItemType Directory -Path $DOWNLOADS_PATH | Out-Null
    }

    $PACKAGE_URL = "https://gitlabe2.ext.net.nokia.com/api/v4/projects/96502/packages/generic/mlaas-cli/${PACKAGE_VERSION}/mlaas_cli-${PACKAGE_VERSION}.tar.gz"
    Log-Info "Downloading package: $PACKAGE_URL"

    $OUTPUT_PATH = "${DOWNLOADS_PATH}/mlaas_cli-${PACKAGE_VERSION}.tar.gz"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri $PACKAGE_URL -Headers @{ "PRIVATE-TOKEN" = $USER_TOKEN } -OutFile $OUTPUT_PATH -MaximumRedirection 10 -UseBasicParsing
        Unblock-File -Path $OUTPUT_PATH
    } catch {
        Log-Error "Failed to download file: $_"
        exit 1
    }

    Log-Info "Installing MLaaS CLI v$PACKAGE_VERSION ..."
    
    & pipx install $OUTPUT_PATH --pip-args="--default-timeout=1000"
    #& pipx install $TOOL_NAME --index-url=https://_token_:$USER_TOKEN@gitlabe2.ext.net.nokia.com/api/v4/projects/96468/packages/pypi/simple

    if ($?) {
        Write-Host
        Log-Info "MLaaS CLI installed successfully."
        Write-Host
        Unblock-Cli 
        Show-MlaasHelp
    } else {
        Log-Error "MLaaS CLI could not be installed. See log messages for more info."
    }
}

function Unblock-Cli {
    $pipxList = & pipx list  
    $IS_MLAAS_INSTALLED = $pipxList -match "package $cliName"
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
        $CURRENT_PATH = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

        # Check if the path is already in the PATH variable
        if ($CURRENT_PATH -notlike "*$MLAAS_PATH*") {
            # Add the new path to the PATH variable
            $NEW_PATH = "$CURRENT_PATH;$MLAAS_PATH"
            [System.Environment]::SetEnvironmentVariable("Path", $NEW_PATH, [System.EnvironmentVariableTarget]::Machine)
            if ($?){
                Log-Info "CLI path added to PATH environment variable."
            } else {
                Log-Info "CLI path could not be added to PATH environment variable."
            }
        } else {
            Log-Info "CLI path is already in the PATH environment variable."
        }

        Log-Info "The CLI is installed at: $MLAAS_PATH"    
    }   
}

#########################################################################################
if ([string]::IsNullOrEmpty($env:USER_TOKEN)) {
    Log-Error "env:USER_TOKEN was not found."
    exit 1
}

$PACKAGE_VERSION = "1.0.0" 
if ($env:PACKAGE_VERSION) {
    $PACKAGE_VERSION = $env:PACKAGE_VERSION
}

$USER_TOKEN = $env:USER_TOKEN
$TOOL_NAME = "mlaas-cli"

$proxyServer = "http://135.245.192.7:8000"

# Set the proxy for the current session
$Env:http_proxy = $proxyServer
$Env:https_proxy = $proxyServer

# Verify Python and Pipx are installed
Verify-PythonInstallation
Verify-PipxInstallation

if (-not (Get-Command mlaas -ErrorAction SilentlyContinue)) {
    Log-Info "MLaaS CLI not installed. Installing CLI v$PACKAGE_VERSION ..."
    Install-Tool
} else {
    $OUTPUT = & mlaas --version
    $MLAAS_VERSION = $OUTPUT -replace 'mlaas, version ', ''
    if ($PACKAGE_VERSION -eq $MLAAS_VERSION) {
        Log-Info "The v$PACKAGE_VERSION of the MLaaS CLI is already installed."
        Show-MlaasHelp
    } else {
        Log-Info "Uninstalling MLaaS CLI v$MLAAS_VERSION ..."
        & pipx uninstall $TOOL_NAME
        Log-Info "Installing CLI v$PACKAGE_VERSION ..."
        Install-Tool      
    }
}      

