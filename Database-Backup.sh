#!/bin/bash

# Usage: bash Database-Backup.sh [option]
#
# Set connection settings below
#
# Options:
#   -c -config    Use specified config file.
#   -t -test      Dry-run; test connection settings and priveleges without backing up.
#   -h -help      Display this message.
#
# Author: Kate Davidson - katedavidson.dev
# Date 10/01/2025
# Version 1.1

config_file="config.conf"

dry_run() {
    echo "Dry-run, not backing up."
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
                        RESULT=$(MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u $MYSQL_USERNAME -h $MYSQL_HOST -e "USE $MYSQL_DATABASE;" >/dev/null 2>&1)

                        if [[ $RESULT == *"ERROR"* ]]; then
                            echo "Database is NOT usable, exiting." >&2
                            exit 1
                        else
                            echo "Checking if user $MYSQL_USERNAME has PROCESS privileges."
                            PRIVILEGES=$(MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u $MYSQL_USERNAME -h $MYSQL_HOST -e "SHOW GRANTS FOR '$MYSQL_USERNAME'@'$MYSQL_HOST';" 2>/dev/null)

                            if [[ $PRIVILEGES == *"PROCESS"* ]]; then
                                echo "Connection test successful, exiting."
                                exit 0
                            else
                                echo "User does NOT have PROCESS privilege, exiting." >&2
                                exit 1
                            fi
                        fi
                    else
                        echo "Login to MySQL failed, exiting." >&2
                        exit 1
                    fi
                else
                    echo "Writing to remote path failed, exiting." >&2
                    exit 1
                fi
            else
                echo "Login to remote host or writing to remote path failed, exiting." >&2
                exit 1
            fi
        else
            echo "The database backup directory is not writable, exiting." >&2
            exit 1
        fi
    else
        echo "The current working directory is not writable, exiting." >&2
        exit 1
    fi
}

live_run() {
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
                        RESULT=$(MYSQL_PWD="${MYSQL_PASSWORD}" mysql -u $MYSQL_USERNAME -h $MYSQL_HOST -e "USE $MYSQL_DATABASE;" >/dev/null 2>&1)

                        if [[ $RESULT == *"ERROR"* ]]; then
                            echo "Database is NOT usable, exiting." >&2
                            exit 1
                        else
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

                                        if [ "$DISABLE_LOCAL_BACKUP" = true ]; then
                                            echo "Backup to remote host successful, deleting temporary file."
                                            echo "DELETING LOCAL BACKUP " $(date) >>logs-backup.log
                                            rm $BACKUP_PATH/$BACKUP_FILENAME

                                            if [ $? -eq 0 ]; then
                                                echo "Local backup deleted, exiting."
                                                echo "LOCAL BACKUP DELETED " $(date) >>logs-backup.log
                                                echo "---------------------------------" >>logs-backup.log
                                                exit 0
                                            else
                                                echo "Local backup deleting failed, exiting."
                                                echo "DELETING LOCAL BACKUP FAILED " $(date) >>logs-backup.log
                                                echo "---------------------------------" >>logs-backup.log
                                                exit 1
                                            fi
                                        else
                                            echo "Backup to remote host successful, exiting."
                                            echo "---------------------------------" >>logs-backup.log
                                            exit 0
                                        fi
                                    else
                                        echo "Backup to remote host failed, exiting." >&2
                                        echo "FILE TRANSFER FAILED " $(date) >>logs-backup.log
                                        echo "---------------------------------" >>logs-backup.log
                                        exit 1
                                    fi
                                else
                                    echo "Dumping database failed, exiting." >&2
                                    echo "DUMP FAILED " $(date) >>logs-backup.log
                                    echo "---------------------------------" >>logs-backup.log
                                    exit 1
                                fi
                            else
                                echo "User does NOT have PROCESS privilege, exiting." >&2
                                echo "CONFIG ERROR " $(date) >>logs-backup.log
                                echo "---------------------------------" >>logs-backup.log
                                exit 1
                            fi
                        fi
                    else
                        echo "Login to MySQL failed, exiting." >&2
                        echo "CONFIG ERROR " $(date) >>logs-backup.log
                        echo "---------------------------------" >>logs-backup.log
                        exit 1
                    fi
                else
                    echo "Writing to remote path failed, exiting." >&2
                    echo "CONFIG ERROR " $(date) >>logs-backup.log
                    echo "---------------------------------" >>logs-backup.log
                    exit 1
                fi

            else
                echo "Login to remote host or writing to remote path failed, exiting." >&2
                echo "CONFIG ERROR " $(date) >>logs-backup.log
                echo "---------------------------------" >>logs-backup.log
                exit 1
            fi
        else
            echo "The database backup directory is not writable, exiting." >&2
            echo "CONFIG ERROR " $(date) >>logs-backup.log
            echo "---------------------------------" >>logs-backup.log
            exit 1
        fi
    else
        echo "The current working directory is not writable, exiting." >&2
        echo "CONFIG ERROR " $(date) >>logs-backup.log
        echo "---------------------------------" >>logs-backup.log
        exit 1
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
            echo "Deleted old backup $FILE"
        fi
    done
}

print_help() {
    echo "Usage: $0 [-t | -test] [-h | -help] [-c config.conf | -config config.conf]"
    echo " -c, -config Use specified config file."
    echo " -t, -test Perform a dry run without backing up."
    echo " -h, -help Display this help message."
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c | -config)
            config_file="$2"
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

if [ -f "$config_file" ]; then
    source "$config_file"
else
    echo "Config file $config_file missing, exiting."
    exit 1
fi

if [ "$dry_run" = true ]; then
    dry_run
else
    if [ "$BACKUP_EXPIRES" -ne -1 ] && [ "$DISABLE_LOCAL_BACKUPS" != "true" ]; then
        delete_backups
    fi
    live_run
fi