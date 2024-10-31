#!/bin/bash

cleanup() {
    if [ -d "$DOWNLOADS_PATH" ]; then
    rm -r "$DOWNLOADS_PATH"
    fi
}

trap cleanup EXIT

if [ -z "$1" ]; then
    echo "Error: USER_TOKEN was not provided."
    exit 1
fi

USER_TOKEN=$1

# Check if Python 3.9 or newer is installed
PYTHON_VERSION=$(python3 --version 2>&1)
if [[ $? -ne 0 ]]; then
    echo "Python is not installed."
    exit 1
fi

PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d' ' -f2 | cut -d'.' -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d' ' -f2 | cut -d'.' -f2)

if [[ $PYTHON_MAJOR -lt 3 ]] || { [[ $PYTHON_MAJOR -eq 3 ]] && [[ $PYTHON_MINOR -lt 9 ]]; }; then
    echo "Python 3.9 or newer is required. Current version: $PYTHON_VERSION"
    exit 1
fi

# Check if pipx is installed, if not install it
if ! command -v pipx &> /dev/null; then
    echo "pipx is not installed. Installing pipx..."
    python3 -m pip install --user pipx
    python3 -m pipx ensurepath
    echo "pipx installed successfully."
fi

# Set default value for PACKAGE_VERSION if not provided
PACKAGE_VERSION=${2:-1.0.0}
TOOL_NAME="mlaas-cli"

# Check if the mlaas-cli is installed
if pipx list | grep -q "$TOOL_NAME"; then
    CURRENT_VERSION=$(pipx list | grep $TOOL_NAME | awk '{print substr($3, 1, length($3)-1)}')

    if [ "$PACKAGE_VERSION" == "$CURRENT_VERSION" ]; then
        echo "The v$PACKAGE_VERSION of the MLaaS CLI is already installed."
        echo
        echo "`mlaas --help`"
        exit 0
    fi
    echo "Uninstalling mlaas_cli=$CURRENT_VERSION..."
    pipx uninstall $TOOL_NAME
fi


DOWNLOADS_PATH="./mlaas-downloads"
if [ -d "$DOWNLOADS_PATH" ]; then
    rm -r "$DOWNLOADS_PATH"
else
    mkdir -p "$DOWNLOADS_PATH"
fi


PACKAGE_URL="https://gitlabe2.ext.net.nokia.com/api/v4/projects/96502/packages/generic/mlaas-cli/${PACKAGE_VERSION}/mlaas_cli-${PACKAGE_VERSION}.tar.gz"
echo "Downloading package: $PACKAGE_URL"

OUTPUT_PATH="${DOWNLOADS_PATH}/mlaas_cli-${PACKAGE_VERSION}.tar.gz"
curl --header "PRIVATE-TOKEN: ${USER_TOKEN}" --output $OUTPUT_PATH $PACKAGE_URL

echo "Installing package: $PACKAGE_URL"
pipx install $OUTPUT_PATH

echo
echo "MLaaS CLI installed successfully."
echo
echo "`mlaas --help`"
