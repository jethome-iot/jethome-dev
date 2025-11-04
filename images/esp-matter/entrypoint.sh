#!/bin/bash
set -e

echo "Activating ESP-IDF and ESP-Matter environments..."
echo ""

# Source ESP-IDF environment
. "${IDF_PATH}/export.sh"

echo ""
echo "Activating ESP-Matter environment..."

# Source ESP-Matter environment
. "${ESP_MATTER_PATH}/export.sh"

echo "ESP-Matter environment activated"
echo ""

# Execute the command
exec "$@"

