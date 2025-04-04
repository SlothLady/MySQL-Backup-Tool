# MySQL / MariaDB Backup Tool

This script allows you to backup a MySQL database or multiple MySQL databases to, optionally a local folder, and upload the backups to a remote server using SCP. This script also has a dry run option to allow you to just test your connection settings and for neccessary privileges without doing a backup.

Can be automated with a cron job and multiple config files can be stored in a path, you can specify a path with -c or -config, this will make the script recursively use each config file. By default conf.d is used.

Integrates with slack webhooks to allow you to send backup log messages to a slack channel with the status, name of the config file, name of the backed up file and the hash of the backup for forensics.

## Usage

### To use the script, use the following commands:

```bash
bash Database-Backup.sh
bash Database-Backup.sh -c config.conf # Or -config use a specific config file or config folder, default is ./conf.d
bash Database-Backup.sh -t # Or -test dry-run
bash Database-Backup.sh -h # Or -help displays usage information
```

## Configuration

Before your first use, you will need to enter your connection settings for your local MySQL database and the remote host. Additionally this script expects that you have used ssh-keygen to generate ssh keys for the user running the script and synced them with the remote host. You should be able to connect as specified below for this script to not return a remote connection error. Config files or config file paths can be specified using -c or -config. By default the script will look for config files in the folder conf.d.

```
ssh user@remote-host
```

### Create new mysql user for backup

```
CREATE USER 'backup'@'localhost' IDENTIFIED BY 'password';
GRANT SELECT, SHOW VIEW, TRIGGER, PROCESS ON *.* TO 'backup'@'localhost';
FLUSH PRIVILEGES;
```

### Configure settings

```bash
cd conf.d
cp template database1.conf # It's a good idea to name this file something helpful like the name of your database followed by .conf
nano database1.conf
```

### If running this script with cron, use explicit paths like /home/ubuntu for the backup path.

```bash
# MySQL Database Backup Tool Config

#~~~~~~~~Connection Settings~~~~~~~~#

MYSQL_USERNAME=""                # MySQL username
MYSQL_PASSWORD=""                # MySQL password
MYSQL_DATABASE=""                # MySQL database name
MYSQL_HOST="localhost"           # MySQL hostname
REMOTE_USER=""                   # Remote username
REMOTE_HOST=""                   # Remote hostname
REMOTE_PATH=""                   # Remote backup path
LOCAL_BACKUPS=false              # Enable or disable storage and deletion of local backups, a temporary file will still be made
BACKUP_PATH="./"                 # Directory where local backups should be made
BACKUP_EXPIRES=-1                # Number of days after which local backups should be deleted, -1 for never
SLACK_INTEGRATION=false          # Enable or disable slack webhook integration
SLACK_WEBHOOK_URL=""             # Slack webhook URL

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
```

## Testing Configuration

### You can test your configuration by using the test argument.

```bash
bash Database-Backup.sh -t
```
```
Dry-run, not backing up.
Using config file conf.d/database1.conf
Testing connection to remote host remotehost as user localuser
Checking if remote path /home/remoteuser is writeable.
Testing connection to MySQL server localhost as mysqluser.
Checking whether database mysqldb can be used.
Checking if user mysqluser has SELECT, SHOW VIEW, TRIGGER, PROCESS privileges.
Connection test successful, exiting.
```

Regardless of whether you run the test or not, all of your configuration options, as well as working directory, backup directory write permissions, MySQL priveleges and remote directory write permissions will be checked prior to doing a backup, this prevents a situation where you spend hours dumping a database only for the script to error due to lack of remote write permissions.

## Logging

Event logs are stored in the file ```logs-backup.log``` in the working directory of the script. Dry runs do not make log entries, write permissions are still checked for.

## Naming Convention

Backups will be named ```[MYSQL_DATABASE]YYYY-MM-DD_HH-MM.sql.gz```
Where MYSQL_DATABASE is the name of the database being backed up, followed by the current date and time.

## Deleting Old Backups

By default, this script won't store local backups or delete old local backups, see ```BACKUP_EXPIRES=-1``` and ```DISABLE_LOCAL_BACKUPS``` in the configuration section, optionally backups can be stored locally as well as remotely and automatically deleted from the local backups folder after ```BACKUP_EXPIRES=x``` amount of days. Remote backups will never be deleted, this is by design.

## Slack Integration

This script can post to a slack channel using the webhook url specified in the config file, more info about creating slack webhooks can be found at https://api.slack.com/messaging/webhooks

## Digital Forensics

By setting up Slack integration, a message is automatically sent to your Slack webhook each time a backup is successfully completed. This message includes the timestamp, status, name of the backup file, and its SHA-256 hash. Sending this information to a third party, complete with a timestamp, provides a way to prove the authenticity and integrity of the backup at a specific date and time. The hash included in the Slack message can later be verified against the backup to confirm it has not been tampered with by using the command ```sha256sum backup.sql.gz```.

## Automation with cron

This script is designed to be used with cron to automatically run backups and can be easily automated with cron! Below is an example of a cron file to run the script daily at 10pm in ```/etc/cron.d/mysqlbackup``` as the user ```debian```

```
## MySQL Database Backup Tool
0 22 * * * debian /bin/bash /home/debian/MySQL-Backup-Tool/Database-Backup.sh
##
```

You can specify the config file or folder location with ```-c``` or ```-config```, by default the ```conf.d``` folder in the same directory as the script will be used to look for config files.
