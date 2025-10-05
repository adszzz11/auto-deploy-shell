#!/bin/bash
# Legacy wrapper for runApp functionality
# This file maintains backward compatibility while using the new modular architecture

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the new modular runApp_main.sh
source "${SCRIPT_DIR}/runApp_main.sh"

# Check parameters and delegate to the main function
if [ "$#" -ne 4 ]; then
    echo "Usage: runApp.sh <port> [stop|start|restart] [JAVA_OPTS] <common_utils_dir>"
    exit 1
fi

# Call the main function with the same parameters
runapp_main "$1" "$2" "$3" "$4"
