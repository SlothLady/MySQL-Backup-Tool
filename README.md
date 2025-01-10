# MySQL Backup Tool

This script allows you to backup a MySQL database and upload the backup to a remote host. This script also has a dry run option to allow you to just test your connection settings and for neccessary privileges without doing a backup.

Can be automated with a cron job.

## Usage

To use the script, run the following command:

```bash
bash Database-Backup.sh
bash Database-Backup.sh -t # Or -test dry-run
bash Database-Backup.sh -h # Or -help displays usage information
```

## Configuration

Before your first use, you will need to enter your connection settings for your local MySQL database and the remote host. Additionally this script expects that you have used ssh-keygen to generate ssh keys for the user running the script and synced them with the remote host. You should be able to connect as specified below for this script to not return a remote connection error.

```
ssh user@remote-host
```

Configure settings

```bash
nano Database-Backup.sh
```

```bash
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

Regardless of whether you run the test or not, all of your configuration options, as well as working directory write permissions, MySQL priveleges and remote directory write permissions will be checked prior to doing a backup, this prevents a situation where you spend hours dumping a database only for the script to error due to lack of remote write permissions.

## Logging

Currently this script does not create logs, however this feature is planned and there will be an option to store logs locally and remotely.

## Backups by date

Currently this script does not name the remote backups with the date and time they were backed up however this is another planned feature and you will be able to specify the date and time format to be included in the file names.
