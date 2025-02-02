#!/bin/bash

# author Gennadiy Tselischev
# revised by Oleksandr Molchanov

# Colors
ENDCOLOR="\e[0m"
RED="\e[31m"
GREEN="\e[32m"
BOLDGREEN="\e[1;32m"
YELLOW="\e[33m"
BOLDYELLOW="\e[1;33m"
BLUE="\e[34m"

SEPARATOR="\n$(printf '%.0s-' {1..40})\n" #separator variable (used to divide text in the script output)
LOG_FILE="wprestor_log"

# error function
err() {
    echo -e "${RED}ERROR: ${1}${ENDCOLOR}"
    exit 1
}

# Function to make sure the script is not run as root
check_user() {
    local user_id="$(id -u)"
    [[ "${user_id}" -eq 0 ]] && err "You should not run it as root!"
}

# Function to check if the script is run from the user's home directory
check_home_directory() {
    ! grep "^${HOME}" <<< "${PWD}" && err "You should run it under user homedir!"
}

# Function to display a disclaimer and get user confirmation
show_disclaimer() {
    echo -e "${YELLOW}WARNING:${ENDCOLOR} This script will move all files in the current directory to a backup folder, excluding files with the following extensions: *.tar.gz, *.zip, *.sh, *.sql, and folders: cgi-bin, .well-known."
    echo -e "${YELLOW}Current directory contents:${ENDCOLOR}"
    ls -la
    echo -e "${YELLOW}Do you understand and accept the responsibility for the consequences? [y/n]${ENDCOLOR}"
    read -rp "> " user_response
    if [[ ! "${user_response}" =~ ^[yY](es)?$ ]]; then
        err "User did not accept the disclaimer. Exiting script."
    fi
    echo -e "${GREEN}User accepted the disclaimer. Proceeding with the script...${ENDCOLOR}"
}

# Function to check if there are unwanted files to move them to a separate folder
backup_unwanted_files() {
    local backup_dir="previous_folder_backup"

    unwanted_items=$(find . -maxdepth 1 \( ! -name "*.tar.gz" ! -name "*.zip" ! -name "*.sh" ! -name "*.sql" ! -name "cgi-bin" ! -name ".well-known" \))

    if [[ -n "$unwanted_items" ]]; then
        echo -e "${BLUE}Unwanted files and folders detected. Moving them to ${backup_dir}...${ENDCOLOR}"

        mkdir -p "$backup_dir"
        # Check if the directory was created successfully
        if [[ ! -d "$backup_dir" ]]; then
            err "Failed to create backup directory ${backup_dir}. Exiting."
        fi

        for item in $unwanted_items; do
            if [[ "$item" != "." ]]; then
                mv "$item" "$backup_dir"
            fi
        done

        echo -e "${GREEN}Files and folders moved to ${backup_dir}.${ENDCOLOR}"
    else
        echo -e "${GREEN}No unwanted files or folders detected. Proceeding...${ENDCOLOR}"
    fi
}



# Function to find and select a backup file to restore
find_backup() {
    echo -e "\nAvailable backups to restore:\n"
    
   local BACKUPS=($(find "${PWD}" -type f \( -name "*.zip" -o -name "*.tar.gz" \)))
    [[ -z "${BACKUPS}" ]] && err "No backups found within ${PWD}"

    if [[ "${#BACKUPS[@]}" -gt 1 ]]; then
        local NUM=1
        for i in "${BACKUPS[@]}"; do
            echo "${NUM}. $i"
            NUM=$((NUM+1))
        done | column -t

        local BACKUP_CHOICE
        read -p "> Choose the backup: " BACKUP_CHOICE
        [[ ! "${BACKUP_CHOICE}" =~ ^[1-9]{1}[0-9]*$ ]] && err "Invalid choice"
        local ARRAY_MAPPER=$((BACKUP_CHOICE-1))
        [[ -z "${BACKUPS[${ARRAY_MAPPER}]}" ]] && err "Invalid choice"
        local CHOSEN_BACKUP="${BACKUPS[${ARRAY_MAPPER}]}"
    else
        CHOSEN_BACKUP="${BACKUPS[0]}"
        echo "${BACKUPS[0]}"
    fi

    echo -e "${SEPARATOR}"
    
    local CHOICE
    read -rp "> Do you want to proceed? [y/n]: " CHOICE
    [[ ! "${CHOICE}" =~ ^[yY](es)?$ ]] && err "Ok, next time"

    BACKUP="$(awk -F/ '{print $NF}' <<<"${CHOSEN_BACKUP}")"
}

# Function to extract the selected backup
extract_backup() {
    # Check if tar has --keep-old-files option
    TAR_SAFE=$(tar --help 2>/dev/null | grep -q -- "\s--keep-old-files\s" && echo true)
    # Check if unzip has -n option
    ZIP_SAFE=$(unzip --help 2>/dev/null | grep -q -- "\s-n\s" && echo true)

    # Exit if either tar or unzip does not have the safe options
    [[ -z "${TAR_SAFE}" || -z "${ZIP_SAFE}" ]] && err "tar or unzip failed safe check, exiting"

    if [[ "${BACKUP}" == *.tar.gz ]]; then
        echo -e "\n${BLUE}Checking integrity of${ENDCOLOR} ${BACKUP}${BLUE} as a .tar.gz archive...${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Checking integrity of ${BACKUP} as a .tar.gz archive..." >> "$LOG_FILE"

        if ! tar -tzf "${BACKUP}" >> "$LOG_FILE" 2>&1; then
            err "The archive ${BACKUP} is corrupted or invalid. Details logged to $LOG_FILE."
        fi

        echo -e "${BLUE}Extracting${ENDCOLOR} ${BACKUP}${BLUE} as a .tar.gz archive with --keep-old-files option...${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Extracting ${BACKUP} as a .tar.gz archive with --keep-old-files option..." >> "$LOG_FILE"
        
        if tar --keep-old-files -zxvf "${BACKUP}" >> "$LOG_FILE" 2>&1; then
            echo -e "${GREEN}Backup ${BACKUP}${ENDCOLOR} ${GREEN}was restored successfully!${ENDCOLOR}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup ${BACKUP} was restored successfully!" >> "$LOG_FILE"
        else
            err "Extraction failed for ${BACKUP}. Please check manually. Details logged to $LOG_FILE."
        fi

    elif [[ "${BACKUP}" == *.zip ]]; then
        echo -e "\n${BLUE}Checking integrity of${ENDCOLOR} ${BACKUP}${BLUE} as a .zip archive...${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Checking integrity of ${BACKUP} as a .zip archive..." >> "$LOG_FILE"

        if ! unzip -t "${BACKUP}" >> "$LOG_FILE" 2>&1; then
            err "The archive ${BACKUP} is corrupted or invalid. Details logged to $LOG_FILE."
        fi

        echo -e "${BLUE}Extracting${ENDCOLOR} ${BACKUP}${BLUE} as a .zip archive with -n option...${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Extracting ${BACKUP} as a .zip archive with -n option..." >> "$LOG_FILE"
        
        if unzip -n "${BACKUP}" >> "$LOG_FILE" 2>&1; then
            echo -e "${GREEN}Backup${ENDCOLOR} ${BACKUP} ${GREEN}was restored successfully!${ENDCOLOR}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup ${BACKUP} was restored successfully!" >> "$LOG_FILE"
        else
            err "Extraction failed for ${BACKUP}. Please check manually. Details logged to $LOG_FILE."
        fi

    else
        err "Unsupported file format or corrupted backup for ${BACKUP}. Please check manually."
    fi

    echo -e "${SEPARATOR}"
}


# Function to find and restore SQL dumps
restore_sql_dump() {
    local SQL_DUMPS DUMP_CHOICE ARRAY_MAPPER CHOSEN_DUMP CHOICE
    echo -e "Available .sql dumps to restore:\n"
    
    SQL_DUMPS=($(find . -maxdepth 1 -type f -name "*.sql"))
    [[ -z "${SQL_DUMPS}" ]] && err "! No .sql dumps found within ${PWD}"

    if [[ "${#SQL_DUMPS[@]}" -gt 1 ]]; then
        NUM=1
        for i in "${SQL_DUMPS[@]}"; do
            echo "${NUM}. $i"
            NUM=$((NUM+1))
        done | column -t

        read -p "> Choose the backup: " DUMP_CHOICE
        [[ ! "${DUMP_CHOICE}" =~ ^[1-9]{1}[0-9]*$ ]] && err "! Invalid choice"
        ARRAY_MAPPER=$((DUMP_CHOICE-1))
        [[ -z "${SQL_DUMPS[${ARRAY_MAPPER}]}" ]] && err "! Invalid choice"
        CHOSEN_DUMP="${SQL_DUMPS[${ARRAY_MAPPER}]}"
    else
        CHOSEN_DUMP="${SQL_DUMPS[0]}"
        echo "${CHOSEN_DUMP}"
    fi

    read -rp " Do you want to proceed? [y/n]: " CHOICE
    [[ ! "${CHOICE}" =~ ^[yY](es)?$ ]] && err "! Ok, next time"

    DUMP="$(awk -F/ '{print $NF}' <<<"${CHOSEN_DUMP}")"

    echo -e "\n${BLUE}Importing selected dump to the database...${ENDCOLOR}"

mysql -f -u "$DB_NAME" -p"$DB_PASS" "$DB_NAME" < "$DUMP" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo -e "\n${DUMP} ${GREEN}imported successfully${ENDCOLOR}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${DUMP} imported successfully." >> "$LOG_FILE"  # Логируем успешный импорт
else
    err "${RED}Failed to import the .sql dump. Please check it manually${ENDCOLOR}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to import ${DUMP}. Please check manually." >> "$LOG_FILE"  # Логируем ошибку
fi

    echo -e "${SEPARATOR}"
}


# Function to create a database and a user
create_database() {
    # Function to check if a database already exists
    database_exists() {
        local db_name="$1"
        local cpanel_user=$(whoami)
        local existing_databases=$(uapi --output=jsonpretty --user="$cpanel_user" Mysql list_databases | jq -r '.result.data[].database')

        for db in $existing_databases; do
            if [[ "$db" == "$db_name" ]]; then
                return 0  # Database exists
            fi
        done
        return 1  # Database does not exist
    }

    # Generate a unique database name
    while true; do
        local RANDOM_NUMBER=$(shuf -i 100-999 -n 1)
        DB_NAME="${USER}_wpr${RANDOM_NUMBER}"
        
        if ! database_exists "$DB_NAME"; then
            break
        fi
    done

    DB_PASS=$(tr -dc 'A-Za-z0-9_!@#$%^*()-+=' </dev/urandom | head -c 12)

    # Log and display database details
    echo -e "\nYour database details (just in case):"
    echo -e "${GREEN}Database Name:${ENDCOLOR} $DB_NAME"
    echo -e "${GREEN}Database User:${ENDCOLOR} $DB_NAME"
    echo -e "${GREEN}Database Password:${ENDCOLOR} $DB_PASS"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Database details - Name: $DB_NAME, User: $DB_NAME, Password: $DB_PASS" >> "$LOG_FILE"

    echo -e "\n${BLUE}Creating a new database using the details obtained...${ENDCOLOR}\n"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Creating database $DB_NAME..." >> "$LOG_FILE"

    # Create the database
    if ! uapi Mysql create_database name="$DB_NAME" >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}Failed to create database $DB_NAME.${ENDCOLOR} ${RED}Check it manually.${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Failed to create database $DB_NAME. Check manually." >> "$LOG_FILE"
    else
        echo -e "${GREEN}\nDatabase${ENDCOLOR} $DB_NAME ${GREEN}created successfully.${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Database $DB_NAME created successfully." >> "$LOG_FILE"
    fi

    # Create the database user
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Creating database user $DB_NAME..." >> "$LOG_FILE"
    if ! uapi Mysql create_user name="$DB_NAME" password="$DB_PASS" >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}Failed to create database user $DB_NAME.${ENDCOLOR} ${RED}Check it manually.${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Failed to create database user $DB_NAME. Check manually." >> "$LOG_FILE"
    else
        echo -e "${GREEN}Database user${ENDCOLOR} $DB_NAME ${GREEN}created successfully.${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Database user $DB_NAME created successfully." >> "$LOG_FILE"
    fi

    # Grant privileges to the database user
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Granting privileges for user $DB_NAME on database $DB_NAME..." >> "$LOG_FILE"
    if ! uapi Mysql set_privileges_on_database user="$DB_NAME" database="$DB_NAME" privileges=ALL >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}Failed to grant privileges for user${ENDCOLOR} $DB_NAME ${RED}on database${ENDCOLOR} $DB_NAME ${RED}. ${ENDCOLOR} ${RED}Check it manually.${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Failed to grant privileges for user $DB_NAME on database $DB_NAME. Check manually." >> "$LOG_FILE"
    else
        echo -e "${GREEN}Privileges for user${ENDCOLOR} $DB_NAME ${GREEN}on database${ENDCOLOR} $DB_NAME ${GREEN}granted successfully.${ENDCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Privileges for user $DB_NAME on database $DB_NAME granted successfully." >> "$LOG_FILE"
    fi

    echo -e "${SEPARATOR}"
}


# Function to update wp-config.php with new database values
update_wp_config() {
    echo -e "Let's update ${GREEN}wp-config.php${ENDCOLOR} file using the db details we have"
    local WP_CONFIG=$(find . -maxdepth 1 -name "wp-config.php")
    if [[ -z "$WP_CONFIG" ]]; then
        err "${RED}Error: ${GREEN}wp-config.php${ENDCOLOR} file not found in the current directory.${ENDCOLOR}"
    fi

    echo -e "\nOld ${GREEN}wp-config.php${ENDCOLOR} configuration:"
    grep "define( 'DB_NAME'" "$WP_CONFIG" || err "DB_NAME not found. Check and proceed further manually"
    grep "define( 'DB_USER'" "$WP_CONFIG" || err "DB_USER not found. Check and proceed further manually"
    grep "define( 'DB_PASSWORD'" "$WP_CONFIG" || err "DB_PASSWORD not found. Check and proceed further manually"

    echo -e "\n${BLUE}Updating ${GREEN}wp-config.php${ENDCOLOR} ${BLUE}with new database values...${ENDCOLOR}"

    # Escape special characters in the password
    local ESCAPED_DB_PASS=$(printf '%s\n' "$DB_PASS" | sed -e 's/[\/&]/\\&/g')

    sed -i "s/^\(define( 'DB_NAME', '\)[^']*\('.*;\)$/\1$DB_NAME\2/" "$WP_CONFIG" || err "Something went wrong. Proceed further manually"
    sed -i "s/^\(define( 'DB_USER', '\)[^']*\('.*;\)$/\1$DB_NAME\2/" "$WP_CONFIG" || err "Something went wrong. Proceed further manually"
    sed -i "s/^\(define( 'DB_PASSWORD', '\)[^']*\('.*;\)$/\1$ESCAPED_DB_PASS\2/" "$WP_CONFIG" || err "Something went wrong. Proceed further manually"

    echo -e "\nNew ${GREEN}wp-config.php${ENDCOLOR} configuration:"
    grep "define( 'DB_NAME'" "$WP_CONFIG" || err "DB_NAME not found. Check and proceed further manually"
    grep "define( 'DB_USER'" "$WP_CONFIG" || err "DB_USER not found. Check and proceed further manually"
    grep "define( 'DB_PASSWORD'" "$WP_CONFIG" || err "DB_PASSWORD not found. Check and proceed further manually"

    echo -e "\n${BOLDGREEN}Database settings in wp-config.php have been updated. Restoration finished${ENDCOLOR}"
    echo -e "Don't forget to remove $LOG_FILE"
    echo -e "${SEPARATOR}"
}


# Main script execution
echo -e "                                             ${BOLDGREEN}Hello fellow concierge! ${ENDCOLOR}\n"
check_user
check_home_directory
show_disclaimer
backup_unwanted_files
find_backup
extract_backup
create_database
restore_sql_dump
update_wp_config
