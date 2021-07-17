#!/bin/bash

#
# Bash script for creating backups of Nextcloud.
#
# Version 1.0.0
#
# Usage:
# 	- With backup directory specified in the script:  ./NextcloudBackup.sh
# 	- With backup directory specified by parameter: ./NextcloudBackup.sh <BackupDirectory> (e.g. ./NextcloudBackup.sh /media/hdd/nextcloud_backup)
#
# The script is based on an installation of Nextcloud using nginx and MariaDB, see https://decatec.de/home-server/nextcloud-auf-ubuntu-server-18-04-lts-mit-nginx-mariadb-php-lets-encrypt-redis-und-fail2ban/
#

#
# IMPORTANT
# You have to customize this script (directories, users, etc.) for your actual environment.
# All entries which need to be customized are tagged with "TODO".
#

# Variables
backupMainDir=$1

if [ -z "$backupMainDir" ]; then
	# TODO: The directory where you store the Nextcloud backups (when not specified by args)
    backupMainDir='/srv/backups/nextcloud_backup'
fi

echo "Backup directory: $backupMainDir"

if [ -f .env ]
then
  export $(cat .env | xargs)
fi

currentDate=$(date +"%Y%m%d_%H%M%S")

# The actual directory of the current backup - this is a subdirectory of the main directory above with a timestamp
backupdir="${backupMainDir}/${currentDate}/"

# TODO: The directory of your Nextcloud installation (this is a directory under your web root)
nextcloudFileDir="$NEXTCLOUD_ROOT/files"

# TODO: The directory of your Nextcloud data directory (outside the Nextcloud file directory)
# If your data directory is located under Nextcloud's file directory (somewhere in the web root), the data directory should not be a separate part of the backup
nextcloudDataDir="$NEXTCLOUD_ROOT"

# TODO: The directory of your Nextcloud's local external storage.
# Uncomment if you use local external storage.
#nextcloudLocalExternalDataDir='/var/nextcloud_external_data'

# TODO: The container name of nextcloud. Used to start/stop nextcloud server (e.g. 'docker start <nextcloudContainerName>')
nextcloudContainerName='nextcloud'

# TODO: The container name of the database used by nextcloud.
databaseContainerName='nextcloud-mariadb'

# TODO: Your web server user
webserverUser='www-data'

# TODO: The name of the database system (ome of: mysql, mariadb, postgresql)
databaseSystem='mariadb'

# TODO: Your Nextcloud database name
nextcloudDatabase='nextcloud'

# TODO: Your Nextcloud database user
dbUser="$MYSQL_USER"

# TODO: The password of the Nextcloud database user
dbPassword="$MYSQL_PASSWORD"

# TODO: The maximum number of backups to keep (when set to 0, all backups are kept)
maxNrOfBackups=8

# File names for backup files
# If you prefer other file names, you'll also have to change the NextcloudRestore.sh script.
fileNameBackupFileDir='nextcloud-filedir.tar.gz'
fileNameBackupDataDir='nextcloud-datadir.tar.gz'

# TOOD: Uncomment if you use local external storage
#fileNameBackupExternalDataDir='nextcloud-external-datadir.tar.gz'

fileNameBackupDb='nextcloud-db.sql'

# Function for error messages
errorecho() { cat <<< "$@" 1>&2; }

function DisableMaintenanceMode() {
	echo "Switching off maintenance mode..."
	sudo docker exec -it -u www-data nextcloud php occ maintenance:mode --off
	echo "Done"
	echo
}

# Capture CTRL+C
trap CtrlC INT

function CtrlC() {
        echo "Backup cancelled. Restarting Nextcloud Container..."
	docker start "${nextcloudContainerName}"
	echo "Done"
	echo

	read -p "Keep maintenance mode? [y/n] " -n 1 -r
	echo

	if ! [[ $REPLY =~ ^[Yy]$ ]]
	then
		DisableMaintenanceMode
	else
		echo "Maintenance mode still enabled."
	fi

	exit 1
}

#
# Check for root
#
if [ "$(id -u)" != "0" ]
then
	errorecho "ERROR: This script has to be run as root!"
	exit 1
fi

#
# Check if backup dir already exists
#
if [ ! -d "${backupdir}" ]
then
	mkdir -p "${backupdir}"
else
	errorecho "ERROR: The backup directory ${backupdir} already exists!"
	exit 1
fi

#
# Set maintenance mode
#
echo "Set maintenance mode for Nextcloud..."
docker exec -it -u www-data nextcloud php occ maintenance:mode --on
echo "Done"
echo

#
# Stop web server
#
echo "Stopping web server..."
docker stop "${nextcloudContainerName}"
echo "Done"
echo

#
# Backup file directory
#
echo "Creating backup of Nextcloud file directory..."
#tar -cpzf "${backupdir}/${fileNameBackupFileDir}" -C "${nextcloudFileDir}" .
tar cf - -C "${nextcloudFileDir}" . -P | pv -s $(du -sb "${nextcloudFileDir}" | awk '{print $1}') | gzip > "${backupdir}/${fileNameBackupFileDir}"
echo "Done"
echo

#
# Backup data directory
#
echo "Creating backup of Nextcloud data directory..."
#tar --exclude="${nextcloudFileDir}" --exclude="${nextcloudDataDir}/Nextcloud-Backup-Restore" -cpzf "${backupdir}/${fileNameBackupDataDir}"  -C "${nextcloudDataDir}" .
tar --exclude="${nextcloudFileDir}" --exclude="${nextcloudDataDir}/Nextcloud-Backup-Restore" cf - -C "${nextcloudFileDir}" . -P | pv -s $(du -sb "${nextcloudFileDir}" | awk '{print $1}') | gzip > "${backupdir}/${fileNameBackupFileDir}"
echo "Done"
echo

# Backup local external storage.
# Uncomment if you use local external storage
#echo "Creating backup of Nextcloud local external storage directory..."
#tar -cpzf "${backupdir}/${fileNameBackupExternalDataDir}"  -C "${nextcloudLocalExternalDataDir}" .
#echo "Done"
#echo

#
# Backup DB
#
if [ "${databaseSystem,,}" = "mysql" ] || [ "${databaseSystem,,}" = "mariadb" ]; then
  	echo "Backup Nextcloud database (MySQL/MariaDB)..."

	if ! [ -z "$(docker exec -it ${databaseContainerName} mysqldump -V)" ]; then
		errorecho "ERROR: MySQL/MariaDB not installed (command mysqldump not found)."
		errorecho "ERROR: No backup of database possible!"
	else
		docker exec -it "${mariaDBContainerName}" mysqldump --single-transaction -h localhost -u"${dbUser}" -p"${dbPassword}" "${nextcloudDatabase}" > "${backupdir}/${fileNameBackupDb}"
	fi

	echo "Done"
	echo
elif [ "${databaseSystem,,}" = "postgresql" ]; then
	echo "Backup Nextcloud database (PostgreSQL)..."

	if ! [ -z "$(docker exec -it ${databaseContainerName} pg_dump --help)" ]; then
		errorecho "ERROR:PostgreSQL not installed (command pg_dump not found)."
		errorecho "ERROR: No backup of database possible!"
	else
		PGPASSWORD="${dbPassword}" pg_dump "${nextcloudDatabase}" -h localhost -U "${dbUser}" -f "${backupdir}/${fileNameBackupDb}"
	fi

	echo "Done"
	echo
fi

#
# Start web server
#
echo "Starting web server..."
docker start "${nextcloudContainerName}"
echo "Done"
echo

#
# Disable maintenance mode
#
DisableMaintenanceMode

#
# Delete old backups
#
if [ ${maxNrOfBackups} != 0 ]
then
	nrOfBackups=$(ls -l ${backupMainDir} | grep -c ^d)

	if [[ ${nrOfBackups} > ${maxNrOfBackups} ]]
	then
		echo "Removing old backups..."
		ls -t ${backupMainDir} | tail -$(( nrOfBackups - maxNrOfBackups )) | while read -r dirToRemove; do
			echo "${dirToRemove}"
			rm -r "${backupMainDir}/${dirToRemove:?}"
			echo "Done"
			echo
		done
	fi
fi

echo
echo "DONE!"
echo "Backup created: ${backupdir}"
