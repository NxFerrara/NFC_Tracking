#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

assert_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root. Please use sudo."
        exit 1
    fi
}

load_env_variables() {
    set -a # Exports all environment variables
    [ -n "$WIFI_NAME" ] && export WIFI_NAME
    [ -n "$WIFI_PSK" ] && export WIFI_PSK

    source "$SCRIPT_DIR/../app/.env.shared" || return 1
    source "$SCRIPT_DIR/../app/.env" || return 1
    set +a # Stops exporting environment variables
}

run_scripts() {
    local setup_dir="$1"
    shift
    local scripts=("$@")

    for script in "${scripts[@]}"; do
        echo "Running script: $script"
        if ! bash "$setup_dir/$script" 2>&1; then
            echo -e "\nError executing $script. Exiting."
            exit 1
        fi
    done

    echo -e "\nScripts Execution Complete"
}

setup_cron_job() {
    local script_name="$SCRIPT_DIR/$(basename $0)"
    local job_command="bash $script_name $WIFI_NAME $WIFI_PSK"
    if crontab -l 2>/dev/null | grep -Fq "$job_command"; then
        echo "Cron job already exists. Skipping."
    else
        (crontab -l 2>/dev/null; echo "$job_command") | crontab -
        echo "Cron job set for next reboot."
    fi
}

cleanup_after_reboot() {
    crontab -l | grep -v "$SCRIPT_DIR" | crontab -
    rm -f "$FLAG_FILE_PATH"
    echo "Cleanup complete."
}

parse_arguments() {
    local scripts_flag=false
    local scripts_to_run=()
    WIFI_NAME=""
    WIFI_PSK=""

    while getopts ":n:p:s:" opt; do
        case $opt in
            n) WIFI_NAME="$OPTARG";;
            p) WIFI_PSK="$OPTARG";;
            s) scripts_flag=true; scripts_to_run+=("$OPTARG");;
            \?) echo "Invalid option -$OPTARG" >&2; exit 1;;
        esac
    done
    shift $((OPTIND-1))

    load_env_variables

    if [ "$scripts_flag" = true ]; then
        scripts_to_run+=("$@")
        run_scripts "$SCRIPT_DIR/setup" "${scripts_to_run[@]}"
        exit 0
    fi

    # Check that either -s or both -n and -p are provided
    if [ -z "$WIFI_NAME" ] || [ -z "$WIFI_PSK" ]; then
        echo "Usage: $0 [-s script1.sh script2.sh ...] [-n wifi_name -p wifi_pwd]"
        exit 1
    fi
}

main() {
    assert_root
    parse_arguments "$@"

    local flag_file_path="$PROJECT_PATH/app/tmp/exec_pre_install"
    local pre_reboot_scripts=("create_venv.sh" "install_dependencies.sh" "install_wifi_driver.sh" "set_device_overlays.sh" "set_user_permissions.sh" "create_services.sh")
    local post_reboot_scripts=("create_pipes.sh" "connect_wifi.sh")

    if [ ! -f "$flag_file_path" ]; then
        run_scripts "$SCRIPT_DIR/setup" "${pre_reboot_scripts[@]}"
        setup_cron_job
        mkdir -p "$PROJECT_PATH/app/tmp"
        touch "$flag_file_path"
        echo "Pre-Reboot Phase Complete"
        reboot
    fi

    if [ -f "$flag_file_path" ]; then
        run_scripts "$SCRIPT_DIR/setup" "${post_reboot_scripts[@]}"
        cleanup_after_reboot
        echo "Post-Reboot Phase Complete"
        reboot
    fi

    echo "Based."
}

main "$@"