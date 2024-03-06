#!/bin/bash

set -e

assert_conditions() {
    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        echo "${WARNING_MSG} This script must be run as root. Please use sudo."
        exit 1
    fi

    if [ -z "${PROJECT_PATH}" ] || [ -z "${SYSTEMD_DIR}" ]; then
        echo "${WARNING_MSG} Required environment variables PROJECT_PATH or SYSTEMD_DIR are not set."
        exit 1
    fi
}

process_service_files() {
    local service_dir="${PROJECT_PATH}/templates"
    readonly service_dir

    for service_template in "${service_dir}"/*.service; do
        local service_filename=$(basename "${service_template}")
        readonly service_filename

        # BUG: Service file is not created on line 26
        if [ ! -f "${SYSTEMD_DIR}/${service_filename}" ]; then
            envsubst < "${service_template}" > "${SYSTEMD_DIR}/${service_filename}"
            systemctl enable "${service_filename}" > /dev/null
            
            if [ "$?" -eq 0 ]; then
                echo "${OK_MSG} '${service_filename}' enabled"
            else
                echo "${FAIL_MSG} Failed to enable '${service_filename}'"
            fi
        else
            envsubst < "${service_template}" > "${SYSTEMD_DIR}/${service_filename}"
            systemctl daemon-reload
            systemctl restart "${service_filename}"

            if [ "$?" -eq 0 ]; then
                echo "${OK_MSG} '${service_filename}' updated"
            else
                echo "${FAIL_MSG} Failed to update '${service_filename}'"
            fi
        fi
    done
}

main() {
    assert_conditions
    process_service_files
}