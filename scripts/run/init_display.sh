#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

env_file="$SCRIPT_DIR/../../config/scripts_config.sh"

source "$env_file"

exec 200>"$DISPLAY_FRAME_BUFFER_LOCK_PATH" # Open the lock file for writing and assign file descriptor 200

trap 'flock -u 200' EXIT # Trap EXIT signal to ensure lock release on script exit

init_display(){
    flock -x 200 # Wait until lock is acquired

    # Extract the last character of DISPLAY_FRAME_BUFFER_PATH
    local framebuffer_number="${DISPLAY_FRAME_BUFFER_PATH: -1}"

    # Map the console to the framebuffer
    con2fbmap 1 "$framebuffer_number"
    # Wait for a moment
    sleep 0.5
    # Unmap the console
    con2fbmap 1 0
    # Not needed to clear the screen since screen.py takes care of that
    # sudo dd if=/dev/zero of="$DISPLAY_FRAME_BUFFER_PATH" bs=1 count=153600
    flock -u 200 # Release the lock
}

# Check if DISPLAY_FRAME_BUFFER_PATH exists
if [ -e "$DISPLAY_FRAME_BUFFER_PATH" ]; then
    init_display
else
    echo "WARNING: $DISPLAY_FRAME_BUFFER_PATH does not exist."
fi