# !/bin/bash

set -e

# Color Support
if [ -t 1 ] && [ -n "$(tput colors)" ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    MAGENTA="$(tput setaf 5)"
    CYAN="$(tput setaf 6)"
    WHITE="$(tput setaf 7)"
    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"
else
    # stdout does not support colors
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    WHITE=""
    BOLD=""
    RESET=""
fi

# Status Messages
OK="${GREEN}[OK]     ${RESET}"
WARNING="${YELLOW}[WARNING]${RESET}"
FAIL="${RED}[FAIL]   ${RESET}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export RED GREEN YELLOW BLUE MAGENTA CYAN WHITE BOLD RESET

assert_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${WARNING} This script must be run as root. Please use sudo."
        exit 1
    fi
}

load_env_variables() {
    local project_path="${SCRIPT_DIR}/../../"
    set -a
    source "${project_path}/scripts/paths.sh"
    source "${project_path}/.env"
    set +a
}

run_scripts() {
    local target_dir="$1"
    readonly target_dir
    shift

    set +e
    for script in "${target_dir}"/*.sh; do
        # TODO: Add name script name
        if ! bash "${script}" 2>&1; then
            echo "${FAIL} ${script##*/}"
            exit 2
        fi
        echo "${OK} ${script##*/}"
    done
    set -e
}

run_pre_reboot_tasks() {
    if [ ! -f "${PRE_REBOOT_FLAG}" ] && [ ! -f "${REBOOT_HALTED_FLAG}" ]; then
        # TODO: Bold it
        echo "Initiating pre-reboot setup..."
        run_scripts "${SCRIPT_DIR}/pre_reboot"
        echo "Pre-reboot tasks completed."
    elif [ -f "${REBOOT_HALTED_FLAG}" ]; then
        echo "${WARNING} Pre-reboot setup already completed"
    elif [ -f "${PRE_REBOOT_FLAG}" ]; then
        echo "${WARNING} Pre-reboot setup already completed"
        exit 0
    fi
        
    local response
    while true; do
        read -p "Do you wish to reboot now? [Y/n] " response
        case "${response}" in
            [Yy])
                # Create file flags and locks required during post-reboot setup
                touch "${DISPLAY_FRAME_BUFFER_LOCK_PATH}"
                touch "${PRE_REBOOT_FLAG}"

                if [ -f "${REBOOT_HALTED_FLAG}" ]; then
                    rm -f "${REBOOT_HALTED_FLAG}"
                fi
                echo "Rebooting..."
                reboot --no-wall
                break;
                ;;
            [Nn])
                touch "${REBOOT_HALTED_FLAG}"
                echo "${WARNING} Post-reboot setup won't begin until system is rebooted"
                break
                ;;
            *)
                echo "Invalid input. Please answer 'Y' (yes) or 'n' (no)."
                ;;
        esac
    done
    exit 0
}

run_post_reboot_tasks() {
    echo "Checking post-reboot requirements..."
    if [ ! -f "${PRE_REBOOT_FLAG}" ]; then
        echo "${WARNING} Pre-reboot dependencies missing"
        exit 1
    elif [ -f "${POST_REBOOT_FLAG}" ]; then
        echo "${WARNING} Post-reboot setup already completed"
        exit 0
    fi
    echo "${OK} All requirements satisfied"

    echo -e "\nInitiating post-reboot setup..."
    run_scripts "${SCRIPT_DIR}/post_reboot"
    touch "${POST_REBOOT_FLAG}"
    
    echo -e "\n${BOLD}FiberPTS${RESET} setup is done. System will reboot now."
    reboot
}

make_app_directories() {
    mkdir -p ${PROJECT_PATH}/.app/flags
    mkdir -p ${PROJECT_PATH}/.app/locks
    mkdir -p ${PROJECT_PATH}/.app/logs
    mkdir -p ${PIPE_FOLDER_PATH}
}

print_usage() {
    echo "Usage: $0 --pre | --post"
}

main() {
    assert_root
    load_env_variables

    make_app_directories
    case "$1" in
        --pre)
            run_pre_reboot_tasks
            ;;
        --post)
            run_post_reboot_tasks
            ;;
        *)
            echo "$0: Invalid option '$1'"
            print_usage
            exit 1
            ;;
    esac
    exit 0
}

main "$@"