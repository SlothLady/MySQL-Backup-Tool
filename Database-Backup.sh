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
# Date 10/01/2025

config_path="conf.d"
version="1.3"

dry_run() {
    echo "Dry-run, not backing up."
    echo "Using config file $config_file"
    if [ -w "$(pwd)" ]; then
        if [ -w "$BACKUP_PATH" ]; then
            echo "Testing connection to remote host $REMOTE_HOST as user $REMOTE_USER"
            ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" 'echo "Login successful."' >/dev/null 2>&1

            if [ $? -eq 0 ]; then
                echo "Checking if remote path $REMOTE_PATH is writeable."
                echo "Hello $REMOTE_HOST" | ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "REMOTE_PATH=${REMOTE_PATH} && cat > \${REMOTE_PATH}/test"

                if [ $? -eq 0 ]; then
                    echo "Testing connection to MySQL server $MYSQL_HOST as $MYSQL_USERNAME."
                    MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u "${MYSQL_USERNAME}" -h "${MYSQL_HOST}" -e "SELECT 1;" >/dev/null 2>&1

                    if [ $? -eq 0 ]; then
                        echo "Checking whether database $MYSQL_DATABASE can be used."
                        MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u $MYSQL_USERNAME -h $MYSQL_HOST -e "USE $MYSQL_DATABASE;"  >/dev/null 2>&1

                        if [ $? -eq 0 ]; then
                            echo "Checking if user $MYSQL_USERNAME has PROCESS privileges."
                            PRIVILEGES=$(MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u $MYSQL_USERNAME -h $MYSQL_HOST -e "SHOW GRANTS FOR '$MYSQL_USERNAME'@'$MYSQL_HOST';" 2>/dev/null)

                            if [[ $PRIVILEGES == *"PROCESS"* ]]; then

                                if [[ "$LOCAL_BACKUPS" = true ]]; then
                                    echo "Local backups are enabled."

                                    if [[ "$BACKUP_EXPIRES" -ne -1 ]]; then
                                        echo "Local backups expire after $BACKUP_EXPIRES days."
                                    else
                                        echo "Local backups set to not expire."
                                    fi
                                fi
                                echo "Connection test successful, exiting."
                                return 0
                            else
                                echo "User does NOT have PROCESS privilege, exiting." >&2
                                return 1
                            fi
                        else
                            echo "Database is NOT usable, exiting." >&2
                            return 1
                        fi
                    else
                        echo "Login to MySQL failed, exiting." >&2
                        return 1
                    fi
                else
                    echo "Writing to remote path failed, exiting." >&2
                    return 1
                fi
            else
                echo "Login to remote host failed, exiting." >&2
                return 1
            fi
        else
            echo "The database backup directory is not writable, exiting." >&2
            return 1
        fi
    else
        echo "The current working directory is not writable, exiting." >&2
        return 1
    fi
}

live_run() {
    echo "BEGINS $config_file " $(date) >>logs-backup.log
    echo "Using config file $config_file"
    if [ -w "$(pwd)" ]; then
        if [ -w "$BACKUP_PATH" ]; then
            echo "Testing connection to remote host $REMOTE_HOST as user $REMOTE_USER"
            ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" 'echo "Login successful."' >/dev/null 2>&1

            if [ $? -eq 0 ]; then
                echo "Checking if remote path $REMOTE_PATH is writeable."
                echo "Hello $REMOTE_HOST" | ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "REMOTE_PATH=${REMOTE_PATH} && cat > \${REMOTE_PATH}/test"

                if [ $? -eq 0 ]; then
                    echo "Testing connection to MySQL server $MYSQL_HOST as $MYSQL_USERNAME."
                    MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u "${MYSQL_USERNAME}" -h "${MYSQL_HOST}" -e "SELECT 1;" >/dev/null 2>&1

                    if [ $? -eq 0 ]; then
                        echo "Checking whether database $MYSQL_DATABASE can be used."
                        MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u $MYSQL_USERNAME -h $MYSQL_HOST -e "USE $MYSQL_DATABASE;"  >/dev/null 2>&1

                        if [ $? -eq 0 ]; then
                            echo "Checking if user $MYSQL_USERNAME has PROCESS privileges."
                            PRIVILEGES=$(MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u $MYSQL_USERNAME -h $MYSQL_HOST -e "SHOW GRANTS FOR '$MYSQL_USERNAME'@'$MYSQL_HOST';" 2>/dev/null)

                            if [[ $PRIVILEGES == *"PROCESS"* ]]; then
                                BACKUP_FILENAME="${MYSQL_DATABASE}_$(date +"%Y-%m-%d_%H-%M").sql.gz"
                                echo "Dumping database $MYSQL_DATABASE to $BACKUP_PATH/$BACKUP_FILENAME."
                                echo "BEGIN DUMP " $(date) >>logs-backup.log
                                MYSQL_PWD="${MYSQL_PASSWORD}" mysqldump -u "${MYSQL_USERNAME}" -h "${MYSQL_HOST}" --single-transaction --databases "${MYSQL_DATABASE}" 2>/dev/null | gzip -9 >$BACKUP_PATH/$BACKUP_FILENAME

                                if [ $? -eq 0 ]; then
                                    echo "END DUMP " $(date) >>logs-backup.log
                                    echo "Dumping database successful. Backing up to remote host $REMOTE_HOST as user $REMOTE_USER."
                                    echo "BEGIN FILE TRANSFER " $(date) >>logs-backup.log
                                    scp $BACKUP_PATH/$BACKUP_FILENAME $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH

                                    if [ $? -eq 0 ]; then
                                        echo "END FILE TRANSFER " $(date) >>logs-backup.log

                                        if [ "$LOCAL_BACKUPS" = false ]; then
                                            echo "Backup to remote host successful, deleting temporary file."
                                            echo "DELETING LOCAL BACKUP " $(date) >>logs-backup.log
                                            rm $BACKUP_PATH/$BACKUP_FILENAME

                                            if [ $? -eq 0 ]; then
                                                echo "Local backup deleted, exiting."
                                                echo "LOCAL BACKUP DELETED " $(date) >>logs-backup.log
                                                echo "---------------------------------" >>logs-backup.log
                                                return 0
                                            else
                                                echo "Local backup deleting failed, exiting."
                                                echo "DELETING LOCAL BACKUP FAILED " $(date) >>logs-backup.log
                                                echo "---------------------------------" >>logs-backup.log
                                                return 1
                                            fi
                                        else
                                            echo "Backup to remote host successful, exiting."
                                            echo "---------------------------------" >>logs-backup.log
                                            return 0
                                        fi
                                    else
                                        echo "Backup to remote host failed, exiting." >&2
                                        echo "FILE TRANSFER FAILED " $(date) >>logs-backup.log
                                        echo "---------------------------------" >>logs-backup.log
                                        return 1
                                    fi
                                else
                                    echo "Dumping database failed, exiting." >&2
                                    echo "DUMP FAILED " $(date) >>logs-backup.log
                                    echo "---------------------------------" >>logs-backup.log
                                    return 1
                                fi
                            else
                                echo "User does NOT have PROCESS privilege, exiting." >&2
                                echo "MYSQL USER NO PROCESS PERM " $(date) >>logs-backup.log
                                echo "---------------------------------" >>logs-backup.log
                                return 1
                            fi
                        else
                            echo "Database is NOT usable, exiting." >&2
                            echo "MYSQL DB NOT USABLE " $(date) >>logs-backup.log
                            echo "---------------------------------" >>logs-backup.log
                            return 1
                        fi
                    else
                        echo "Login to MySQL failed, exiting." >&2
                        echo "MYSQL BAD LOGIN " $(date) >>logs-backup.log
                        echo "---------------------------------" >>logs-backup.log
                        return 1
                    fi
                else
                    echo "Writing to remote path failed, exiting." >&2
                    echo "REMOTE PATH NO PERMS " $(date) >>logs-backup.log
                    echo "---------------------------------" >>logs-backup.log
                    return 1
                fi
            else
                echo "Login to remote host failed, exiting." >&2
                echo "REMOTE HOST BAD LOGIN " $(date) >>logs-backup.log
                echo "---------------------------------" >>logs-backup.log
                return 1
            fi
        else
            echo "The database backup directory is not writable, exiting." >&2
            echo "LOCAL BACKUP DIR NO PERMS " $(date) >>logs-backup.log
            echo "---------------------------------" >>logs-backup.log
            return 1
        fi
    else
        echo "The current working directory is not writable, exiting." >&2
        echo "WORKING DIR NO PERMS " $(date) >>logs-backup.log
        echo "---------------------------------" >>logs-backup.log
        return 1
    fi
}

date_diff() {
    d1=$(date -d "$1" +%s)
    d2=$(date -d "$2" +%s)
    echo $(((d2 - d1) / 86400))
}

delete_backups() {
    CURRENT_DATE=$(date +"%Y-%m-%d")
    for FILE in "$BACKUP_PATH"/*.sql.gz; do
        FILE_DATE=$(basename "$FILE" | cut -d'_' -f1)
        AGE=$(date_diff "$FILE_DATE" "$CURRENT_DATE")
        if [ "$AGE" -gt "$BACKUP_EXPIRES" ]; then
            rm "$FILE"
            echo "Deleted old backup $FILE."
        fi
    done
}

print_help() {
    echo "Usage: $0 [-t | -test] [-h | -help] [-c config.conf | -config config.conf]"
    echo " -c, -config Use specified config file or folder of config files."
    echo " -t, -test Perform a dry run without backing up."
    echo " -h, -help Display this help message."
}

unset_variables() {
    unset MYSQL_BCKTOOL_CFG_VER
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
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c | -config)
            config_path="$2"
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
            echo "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

if [ -z "$config_path" ]; then
    echo "Config path or file not specified, exiting."
    exit 1
fi

if [ -d "$config_path" ]; then
    config_files=("$config_path"/*.conf)
    if [ -z "$(ls -A "$config_path")" ]; then
        echo "Config directory is empty, exiting."
        exit 1
    fi
else
    config_files=("$config_path")
fi

if [ ${#config_files[@]} -eq 0 ]; then
    echo "No config files found, exiting."
    exit 1
fi

for config_file in "${config_files[@]}"; do
    if [ -f "$config_file" ]; then
        unset_variables
        source "$config_file"
        if [ "$MYSQL_BCKTOOL_CFG_VER" = $version ]; then
            if [ "$dry_run" = true ]; then
                dry_run
                if [ $? -ne 0 ]; then
                    ERROR=true
                fi
            else
                # if [ "$BACKUP_EXPIRES" -ne -1 ] && [ "$LOCAL_BACKUPS" = true ]; then
                    # echo "Checking for expired local backups."
                    # delete_backups
                # fi
                live_run
                if [ $? -ne 0 ]; then
                    ERROR=true
                fi
            fi
        else
            if [ "$dry_run" = false ]; then
                echo "Config file $config_file $MYSQL_BCKTOOL_CFG_VER version mismatch, expected $version, skipping."
                echo "CONFIG FILE $config_file $MYSQL_BCKTOOL_CFG_VER VERSION MISMATCH " $(date) >>logs-backup.log
                echo "---------------------------------" >>logs-backup.log
            fi
        fi
    else
        if [ "$dry_run" = false ]; then
            echo "Config file $config_file missing, skipping."
            echo "CONFIG FILE $config_file MISSING " $(date) >>logs-backup.log
            echo "---------------------------------" >>logs-backup.log
        fi
    fi
done

if [ "$ERROR" = true ]; then
    exit 1
else
    exit 0
fi