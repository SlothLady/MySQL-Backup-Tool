#!/bin/bash

# Usage: bash Database-Backup.sh [option]
#
# Set connection settings below
#
# Options:
#   -c -config    Use specified config file or folder of config files.
#   -t -test      Dry-run; test connection settings and priveleges without backing up.
#   -h -help      Display this message.
#
# Author: Kate Davidson - katedavidson.dev

script_path="$(dirname $(realpath ${0}))"
config_path="${script_path}/conf.d"
log_path="${script_path}/logs-backup.log"

slack_message() {
    if [[ "${dry_run}" = false && "${SLACK_INTEGRATION}" = true ]]; then
        if [ -z "${5}" ]; then
            filehash="n/a"
        else
            filehash=$(sha256sum "${5}" | awk '{print $1}')
        fi
        if [ -z "${6}" ]; then
            filename="n/a"
        else
            filename=${6}
        fi
        curl -X POST "${SLACK_WEBHOOK_URL}" -H 'Content-Type: application/json' -d '{"attachments":[{"color":"'"${4}"'","text": "*Log Message:*\n'"${1}"'\n\n*Config File:*\n'"${2}"'\n\n*Status:*\n'"${3}"'\n\n*Hostname:*\n'"$(uname -n)"'\n\n*Backup Filename:*\n'"${filename}"'\n\n*Backup Sha1 Hash:*\n'"${filehash}"'"}]}' >/dev/null 2>&1
        unset filehash
        unset filename
    fi
}

log_message() {
    if [ "${dry_run}" = false ]; then
        if [ "${2}" = false ]; then
            echo "${1}" >>${log_path}
        else
            echo "${1}" $(date) >>${log_path}
        fi
    fi
}

run_backup() {
    if [ "${dry_run}" = true ]; then
        echo "Dry-run, not backing up."
    fi
    log_message "BEGINS ${config_file}"
    echo "Using config file ${config_file}"
    if [ -w "${script_path}" ]; then
        if [[ -w "${BACKUP_PATH}" && ! -z "${BACKUP_PATH}" ]]; then
            echo "Testing connection to remote host ${REMOTE_HOST} as user ${REMOTE_USER}"
            ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" 'echo "Login successful."' >/dev/null 2>&1

            if [ ${?} -eq 0 ]; then
                echo "Checking if remote path ${REMOTE_PATH} is writeable."
                echo "Hello ${REMOTE_HOST}" | ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "REMOTE_PATH=${REMOTE_PATH} && cat > \${REMOTE_PATH}/test"

                if [ ${?} -eq 0 ]; then
                    echo "Testing connection to MySQL server ${MYSQL_HOST} as ${MYSQL_USERNAME}."
                    MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u "${MYSQL_USERNAME}" -h "${MYSQL_HOST}" -e "SELECT 1;" >/dev/null 2>&1

                    if [ ${?} -eq 0 ]; then
                        echo "Checking whether database ${MYSQL_DATABASE} can be used."
                        MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u ${MYSQL_USERNAME} -h ${MYSQL_HOST} -e "USE ${MYSQL_DATABASE};" >/dev/null 2>&1

                        if [ ${?} -eq 0 ]; then
                            echo "Checking if user ${MYSQL_USERNAME} has SELECT, SHOW VIEW, TRIGGER, PROCESS privileges."
                            PRIVILEGES=$(MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u ${MYSQL_USERNAME} -h ${MYSQL_HOST} -e "SHOW GRANTS FOR '${MYSQL_USERNAME}'@'${MYSQL_HOST}';" 2>/dev/null)

                            if [[ ${PRIVILEGES} == *"SELECT"* && ${PRIVILEGES} == *"SHOW VIEW"* && ${PRIVILEGES} == *"TRIGGER"* && ${PRIVILEGES} == *"PROCESS"* ]]; then

                                if [ "${dry_run}" = true ]; then
                                    if [[ "${LOCAL_BACKUPS}" = true ]]; then
                                        echo "Local backups are enabled."

                                        if [[ "${BACKUP_EXPIRES}" -ne -1 ]]; then
                                            echo "Local backups expire after ${BACKUP_EXPIRES} days."
                                        else
                                            echo "Local backups set to not expire."
                                        fi
                                    fi
                                    echo "Connection test successful."
                                    return 0
                                else
                                    BACKUP_FILENAME="${MYSQL_DATABASE}_$(date +"%Y-%m-%d_%H-%M").sql.gz"
                                    echo "Dumping database ${MYSQL_DATABASE} to ${BACKUP_PATH}/${BACKUP_FILENAME}."
                                    log_message "BEGIN DUMP"
                                    MYSQL_PWD="${MYSQL_PASSWORD}" mysqldump -u "${MYSQL_USERNAME}" -h "${MYSQL_HOST}" --single-transaction --databases "${MYSQL_DATABASE}" 2>/dev/null | gzip -9 >"${BACKUP_PATH}/${BACKUP_FILENAME}"

                                    if [ ${?} -eq 0 ]; then
                                        log_message "END DUMP"
                                        echo "Dumping database successful. Backing up to remote host ${REMOTE_HOST} as user ${REMOTE_USER}."
                                        log_message "BEGIN FILE TRANSFER "
                                        scp "${BACKUP_PATH}/${BACKUP_FILENAME}" ${REMOTE_USER}@${REMOTE_HOST}:"${REMOTE_PATH}"

                                        if [ ${?} -eq 0 ]; then
                                            log_message "END FILE TRANSFER"

                                            if [ "${LOCAL_BACKUPS}" = false ]; then
                                                echo "Backup to remote host successful, deleting temporary file."
                                                log_message "DELETING LOCAL BACKUP"
                                                rm "${BACKUP_PATH}/${BACKUP_FILENAME}"

                                                if [ ${?} -eq 0 ]; then
                                                    echo "Local backup deleted."
                                                    log_message "LOCAL BACKUP DELETED"
                                                    return 0
                                                else
                                                    echo "Local backup deleting failed."
                                                    log_message "DELETING LOCAL BACKUP FAILED"
                                                    return 1
                                                fi
                                            else
                                                echo "Backup to remote host successful."
                                                return 0
                                            fi
                                        else
                                            echo "Backup to remote host failed." >&2
                                            log_message "FILE TRANSFER FAILED"
                                            return 1
                                        fi
                                    else
                                        echo "Dumping database failed." >&2
                                        log_message "DUMP FAILED"
                                        return 1
                                    fi
                                fi
                            else
                                echo "User does NOT have required privileges." >&2
                                log_message "MYSQL USER BAD PERMS"
                                return 1
                            fi
                        else
                            echo "Database is NOT usable." >&2
                            log_message "MYSQL DB NOT USABLE"
                            return 1
                        fi
                    else
                        echo "Login to MySQL failed." >&2
                        log_message "MYSQL BAD LOGIN"
                        return 1
                    fi
                else
                    echo "Writing to remote path failed." >&2
                    log_message "REMOTE PATH NO PERMS"
                    return 1
                fi
            else
                echo "Login to remote host failed." >&2
                log_message "REMOTE HOST BAD LOGIN"
                return 1
            fi
        else
            echo "The database backup directory is not writable or not set." >&2
            log_message "LOCAL BACKUP DIR NO PERMS OR UNSET"
            return 1
        fi
    else
        echo "The script directory is not writable." >&2
        log_message "SCRIPT DIR NO PERMS"
        return 1
    fi
}

delete_backups() {
    if [ "${BACKUP_EXPIRES}" -ne -1 ] && [ "${LOCAL_BACKUPS}" = true ]; then
        echo "Checking for expired local backups."
        log_message "CHECKING FOR EXPIRED LOCAL BACKUPS"
        CURRENT_DATE=$(date +%s)
        for file in "${BACKUP_PATH}"/*.sql.gz; do
            if [[ ${file} =~ _([0-9]{4}-[0-9]{2}-[0-9]{2})_[0-9]{2}-[0-9]{2}\.sql\.gz ]]; then
                FILE_DATE=${BASH_REMATCH[1]}
                FILE_DATE_EPOCH=$(date -d "${FILE_DATE}" +%s)
                FILE_AGE=$(((CURRENT_DATE - FILE_DATE_EPOCH) / (60 * 60 * 24)))
                if ((FILE_AGE > ${BACKUP_EXPIRES})); then
                    if [ "${dry_run}" = true ]; then
                        echo "${file} (age: ${FILE_AGE} days) is older than (BACKUP_EXPIRES: ${BACKUP_EXPIRES} days)"
                    else
                        echo "Deleting ${file} (age: ${FILE_AGE} days)"
                        log_message "DELETING EXPIRED BACKUP ${file}"
                        rm -f "${file}"
                    fi
                fi
            fi
        done
        return 0
    else
        return 1
    fi
}

print_help() {
    echo "Usage: ${0} [-t | -test] [-h | -help] [-c config.conf | -config config.conf]"
    echo " -c, -config Use specified config file or folder of config files."
    echo " -t, -test Perform a dry run without backing up."
    echo " -h, -help Display this help message."
}

unset_variables() {
    unset MYSQL_USERNAME
    unset MYSQL_PASSWORD
    unset MYSQL_DATABASE
    unset MYSQL_HOST
    unset REMOTE_USER
    unset REMOTE_HOST
    unset REMOTE_PATH
    unset LOCAL_BACKUPS
    unset BACKUP_PATH
    unset BACKUP_EXPIRES
    unset SLACK_INTEGRATION
    unset SLACK_WEBHOOK_URL
}

dry_run=false

while [[ "${#}" -gt 0 ]]; do
    case ${1} in
    -c | -config)
        config_path="${2}"
        shift 2
        ;;
    -t | -test)
        dry_run=true
        shift
        ;;
    -h | -help)
        print_help
        exit 0
        ;;
    *)
        echo "Unknown option: ${1}"
        print_help
        exit 1
        ;;
    esac
done

if [ -z "${config_path}" ]; then
    echo "Config path or file not specified."
    exit 1
fi

if [ -d "${config_path}" ]; then
    config_files=("${config_path}"/*.conf)
    if [ -z "$(ls -A "${config_path}")" ]; then
        echo "Config directory is empty."
        exit 1
    fi
else
    config_files=("${config_path}")
fi

if [ ${#config_files[@]} -eq 0 ]; then
    echo "No config files found."
    exit 1
fi

for config_file in "${config_files[@]}"; do
    if [ -f "${config_file}" ]; then
        unset_variables
        source "${config_file}"
        run_backup
        if [ ${?} -ne 0 ]; then
            ERROR=true
            slack_message "Database backup failed! :face_with_head_bandage:" "${config_file}" "Failed" "#d33f3f"
        else
            delete_backups
            slack_message "Database backup completed! :tada:" "${config_file}" "Completed" "#61d33f" "${BACKUP_PATH}/${BACKUP_FILENAME}" ${BACKUP_FILENAME}
        fi
        log_message "---------------------------------" false
    else
        echo "Config file ${config_file} missing, skipping."
    fi
done

if [ "${ERROR}" = true ]; then
    echo "Exited with error, not checking for expired backups"
    exit 1
else
    exit 0
fi