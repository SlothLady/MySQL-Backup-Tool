#!/bin/bash

# Usage: bash Database-Backup.sh [option]
#
# Set connection settings below
#
# Options:
#   -h            Display this message.
#   -t            Dry-run; test connection settings and priveleges without backing up.
#
# Author: Kate Davidson - katedavidson.dev
# Date 10/01/2025
# Version 1.0

#~~~~~~~~Connection Settings~~~~~~~~#

MYSQL_USERNAME=""
MYSQL_PASSWORD=""
MYSQL_DATABASE=""
MYSQL_HOST="localhost"
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_PATH=""
BACKUP_FILENAME="backup.sql.gz"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

dry_run() {
    echo "Dry-run, not backing up."
    if [ -w "$(pwd)" ]; then
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
        echo "The current working directory is not writable, exiting." >&2
        exit 1
    fi
}

live_run() {
    if [ -w "$(pwd)" ]; then
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
                            echo "Dumping database $MYSQL_DATABASE to $BACKUP_FILENAME."
                            MYSQL_PWD="${MYSQL_PASSWORD}" mysqldump -u "${MYSQL_USERNAME}" -h "${MYSQL_HOST}" --single-transaction --databases "${MYSQL_DATABASE}" 2>/dev/null | gzip -9 >$BACKUP_FILENAME

                            if [ $? -eq 0 ]; then
                                echo "Dumping database successful. Backing up to remote host $REMOTE_HOST as user $REMOTE_USER."
                                scp $BACKUP_FILENAME $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH

                                if [ $? -eq 0 ]; then
                                    echo "Backup to remote host completed successfully, exiting."
                                    exit 0
                                else
                                    echo "Backup to remote host failed, exiting." >&2
                                    exit 1
                                fi
                            else
                                echo "Dumping database failed, exiting." >&2
                                exit 1
                            fi
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
        echo "The current working directory is not writable, exiting." >&2
        exit 1
    fi
}

print_help() {
    echo "Usage: $0 [-t | -test] [-h | -help]"
    echo " -t, -test Perform a dry run without backing up."
    echo " -h, -help Display this help message."
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -t | -test)
        dry_run
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
    shift
done
if [ "$#" -eq 0 ]; then
    live_run
fi
