#!/bin/bash
# Legacy wrapper for common_utils functionality
# This file maintains backward compatibility for scripts expecting _shell/common_utils.sh

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the new modular common_utils_main.sh
source "${SCRIPT_DIR}/common_utils/common_utils_main.sh"