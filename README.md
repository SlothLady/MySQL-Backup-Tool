# MySQL Backup Tool

This script allows you to backup a MySQL database to, optionally a local folder, and upload the backups to a remote server using SCP. This script also has a dry run option to allow you to just test your connection settings and for neccessary privileges without doing a backup.

Can be automated with a cron job.

## Usage

To use the script, use the following commands:

```bash
bash Database-Backup.sh
bash Database-Backup.sh -t # Or -test dry-run
bash Database-Backup.sh -h # Or -help displays usage information
bash Database-Backup.sh -c config.ini # Or -config use a specific config file, default is ./config.ini
```

## Configuration

Before your first use, you will need to enter your connection settings for your local MySQL database and the remote host. Additionally this script expects that you have used ssh-keygen to generate ssh keys for the user running the script and synced them with the remote host. You should be able to connect as specified below for this script to not return a remote connection error.

```
ssh user@remote-host
```

Configure settings

```bash
nano config.ini
```

```bash
#~~~~~~~~Connection Settings~~~~~~~~#

MYSQL_USERNAME=""                # MySQL username
MYSQL_PASSWORD=""                # MySQL password
MYSQL_DATABASE=""                # MySQL database name
MYSQL_HOST="localhost"           # MySQL hostname
REMOTE_USER=""                   # Remote username
REMOTE_HOST=""                   # Remote hostname
REMOTE_PATH=""                   # Remote backup path
BACKUP_PATH="./"                 # Directory where local backups should be made
BACKUP_EXPIRES=-1                # Number of days after which local backups should be deleted, -1 for never
DISABLE_LOCAL_BACKUPS=true       # Enable or disable storage and deletion of local backups, a temporary file will still be made

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
```

## Testing Configuration

You can test your configuration by using the test argument.

```bash
bash Database-Backup.sh -t
```
```
Dry-run, not backing up.
Testing connection to remote host novus as user localuser
Checking if remote path /home/remoteuser is writeable.
Testing connection to MySQL server localhost as mysqluser.
Checking whether database mysqldb can be used.
Checking if user mysqluser has PROCESS privileges.
Connection test successful, exiting.
```

Regardless of whether you run the test or not, all of your configuration options, as well as working directory, backup directory write permissions, MySQL priveleges and remote directory write permissions will be checked prior to doing a backup, this prevents a situation where you spend hours dumping a database only for the script to error due to lack of remote write permissions.

## Logging

Event logs are stored in the file ```logs-backup.log``` in the working directory of the script. Dry runs do not make log entries, write permissions are still checked for.

## Naming Convention

Backups will be named ````[MYSQL_DATABASE]YYYY-MM-DD_HH-MM.sql.gz````
Where MYSQL_DATABASE is the name of the database being backed up, followed by the current date and time.

## Deleting Old Backups

By default, this script won't store local backups or delete old local backups, see ```BACKUP_EXPIRES=-1``` and ```DISABLE_LOCAL_BACKUPS``` in the configuration section, optionally backups can be stored locally as well as remotely and automatically deleted from the local backups folder after ```BACKUP_EXPIRES=x``` amount of days. Remote backups will never be deleted, this is by design.