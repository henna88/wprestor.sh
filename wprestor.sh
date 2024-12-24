#!/bin/bash

# author Gennadiy Tselischev

# Colors
ENDCOLOR="\e[0m"
RED="\e[31m"
GREEN="\e[32m"
BOLDGREEN="\e[1;32m"
YELLOW="\e[33m"
BOLDYELLOW="\e[1;33m"
BLUE="\e[34m"

# Function make sure the script is not run as root
check_user() {
    user_id="$(id -u)"
    [[ "${user_id}" -eq 0 ]] && echo "You should not run it as root!" && exit 1
}


# Function to find and select a backup file to restore
find_backup() {
    echo -e "\nAvailable backups to restore:\n"
    
    BACKUPS=($(find "${PWD}" -type f \( -name "*.zip" -o -name "*.tar.gz" \)))
    [[ -z "${BACKUPS}" ]] && { echo "! No backups found within ${PWD}"; exit 1; }

    if [[ "${#BACKUPS[@]}" -gt 1 ]]; then
        NUM=1
        for i in "${BACKUPS[@]}"; do
            echo "${NUM}. $i"
            NUM=$((NUM+1))
        done | column -t

        read -p "> Choose the backup: " BACKUP_CHOICE
        [[ ! "${BACKUP_CHOICE}" =~ ^[1-9]{1}[0-9]*$ ]] && { echo "! Invalid choice"; exit 1; }
        ARRAY_MAPPER=$((BACKUP_CHOICE-1))
        [[ -z "${BACKUPS[${ARRAY_MAPPER}]}" ]] && { echo "! Invalid choice"; exit 1; }
        CHOSEN_BACKUP="${BACKUPS[${ARRAY_MAPPER}]}"
    else
        CHOSEN_BACKUP="${BACKUPS[0]}"
        echo "${BACKUPS[0]}"
    fi

    read -rp "
--------------------------------------------------------------------------
    
> Do you want to proceed? [y/n]: " CHOICE
    [[ ! "${CHOICE}" =~ ^[yY](es)?$ ]] && { echo "! Ok, next time"; exit 1; }

    BACKUP="$(awk -F/ '{print $NF}' <<<"${CHOSEN_BACKUP}")"
}

# Function to extract the selected backup
extract_backup() {
    if [[ "${BACKUP}" == *.tar.gz ]]; then
        echo -e "
        
${BLUE}Extracting${ENDCOLOR} ${BACKUP}${BLUE} as a .tar.gz archive...${ENDCOLOR}
        "
        tar -zxvf "${CHOSEN_BACKUP}" &>/dev/null
        echo -e "${GREEN}Backup ${BACKUP}${ENDCOLOR} ${GREEN}was restored successfully!${ENDCOLOR}
--------------------------------------------------------------------------"
        
    elif [[ "${BACKUP}" == *.zip ]]; then
echo -e "${BLUE}Extracting${ENDCOLOR} ${BACKUP}${BLUE}as a .zip archive...${ENDCOLOR}"
        unzip "${CHOSEN_BACKUP}" &>/dev/null
        echo -e "
        ${GREEN}Backup${ENDCOLOR} ${BACKUP} ${GREEN}was restored successfully!${ENDCOLOR}
--------------------------------------------------------------------------"
    else
        echo -e "${RED}! Unsupported file format or backup is corrupted. Check it manually${ENDCOLOR}"
        exit 1
    fi
    
}

# Function to create a database and a user
create_database() {
    #DIR_NAME="$PWD"
    #DIR_NAME=$(basename "$PWD" | rev | cut -d. -f2- | rev)
    RANDOM_NUMBER=$(shuf -i 100-999 -n 1)
    DB_NAME="${USER}_wp${RANDOM_NUMBER}"
    DB_PASS=$(tr -dc 'A-Za-z0-9_!@#$%^&*()-+=' </dev/urandom | head -c 16)

    echo -e "
Your database details (just in case):"
    echo -e "${GREEN}Database Name:${ENDCOLOR} $DB_NAME"
    echo -e "${GREEN}Database User:${ENDCOLOR} $DB_NAME"
    echo -e "${GREEN}Database Password:${ENDCOLOR} $DB_PASS"

    echo -e "
${BLUE}Creating a new database using the details obtained...${ENDCOLOR}\n
    "

    if uapi Mysql create_database name="$DB_NAME" &>/dev/null; then
        echo -e "${GREEN}\nDatabase${ENDCOLOR} $DB_NAME ${GREEN}created successfully.${ENDCOLOR} "
    else
        echo -e "${RED}Failed to create database $DB_NAME  .${ENDCOLOR} ${RED}Check it manually${ENDCOLOR}"
    fi

    if uapi Mysql create_user name="$DB_NAME" password="$DB_PASS" &>/dev/null; then
        echo -e "${GREEN}Database user${ENDCOLOR} $DB_NAME${GREEN} created successfully.${ENDCOLOR}"
    else
        echo -e "${RED}Failed to create database user $DB_NAME  .${ENDCOLOR} ${RED}Check it manually${ENDCOLOR}"
    fi

    if uapi Mysql set_privileges_on_database user="$DB_NAME" database="$DB_NAME" privileges=ALL &>/dev/null; then
        echo -e "${GREEN}Privileges for user${ENDCOLOR} $DB_NAME ${GREEN}on database${ENDCOLOR} $DB_NAME ${GREEN}granted successfully.${ENDCOLOR}"
    else
        echo -e "${RED}Failed to grant privileges for user${ENDCOLOR} $DB_NAME ${RED}on database${ENDCOLOR} $DB_NAME ${RED}. Check it manually${ENDCOLOR}"
    fi
}

# Function to find and restore SQL dumps
restore_sql_dump() {
    echo -e "
--------------------------------------------------------------------------
    \nAvailable .sql dumps to restore:\n"
    
    SQL_DUMPS=($(find . -maxdepth 1 -type f -name "*.sql"))
    [[ -z "${SQL_DUMPS}" ]] && { echo "! No .sql dumps found within ${PWD}"; exit 1; }

    if [[ "${#SQL_DUMPS[@]}" -gt 1 ]]; then
        NUM=1
        for i in "${SQL_DUMPS[@]}"; do
            echo "${NUM}. $i"
            NUM=$((NUM+1))
        done | column -t

        read -p "> Choose the backup: " DUMP_CHOICE
        [[ ! "${DUMP_CHOICE}" =~ ^[1-9]{1}[0-9]*$ ]] && { echo "! Invalid choice"; exit 1; }
        ARRAY_MAPPER=$((DUMP_CHOICE-1))
        [[ -z "${SQL_DUMPS[${ARRAY_MAPPER}]}" ]] && { echo "! Invalid choice"; exit 1; }
        CHOSEN_DUMP="${SQL_DUMPS[${ARRAY_MAPPER}]}"
    else
        CHOSEN_DUMP="${SQL_DUMPS[0]}"
        echo "${CHOSEN_DUMP}"
    fi

    read -rp "

> Do you want to proceed? [y/n]: " CHOICE
    [[ ! "${CHOICE}" =~ ^[yY](es)?$ ]] && { echo "! Ok, next time"; exit 1; }

    DUMP="$(awk -F/ '{print $NF}' <<<"${CHOSEN_DUMP}")"

    echo -e "
    \n${BLUE}Importing selected dump to the database...${ENDCOLOR}"

    if mysql -f -u "$DB_NAME" -p"$DB_PASS" "$DB_NAME" < "$DUMP" &>/dev/null; then
        echo -e "
${DUMP} ${GREEN}imported successfully${ENDCOLOR}"
    else
        echo -e "${RED}Failed to import the .sql dump. Please check it manually${ENDCOLOR}"; exit 1;
    fi
}

# Function to update wp-config.php with new database values
update_wp_config() {
    echo -e "
--------------------------------------------------------------------------

Let's update ${GREEN}wp-confing.php${ENDCOLOR} file using the db details we have"
    WP_CONFIG=$(find . -maxdepth 1 -name "wp-config.php")
    if [[ -z "$WP_CONFIG" ]]; then
        echo -e "${RED}Error: ${GREEN}wp-config.php${ENDCOLOR} file not found in the current directory.${ENDCOLOR}"
        exit 1
    fi

echo -e "\nCurrent Database Configuration:"
grep "define( 'DB_NAME'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }
grep "define( 'DB_USER'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }
grep "define( 'DB_PASSWORD'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }

echo -e "
\n${BLUE}Updating ${GREEN}wp-config.php${ENDCOLOR} ${BLUE}with new database values...${ENDCOLOR}"

sed -i "s/^\(define( 'DB_NAME', '\)[^']*\('.*;\)$/\1$DB_NAME\2/" "$WP_CONFIG" || { echo "Something went wrong. Proceed further manually"; exit 1; }
sed -i "s/^\(define( 'DB_USER', '\)[^']*\('.*;\)$/\1$DB_NAME\2/" "$WP_CONFIG" || { echo "Something went wrong. Proceed further manually"; exit 1; }
sed -i "s/^\(define( 'DB_PASSWORD', '\)[^']*\('.*;\)$/\1$DB_PASS\2/" "$WP_CONFIG" || { echo "Something went wrong. Proceed further manually"; exit 1; }

echo -e "\nVerify the updates in ${GREEN}wp-config.php${ENDCOLOR}:"
    grep "define( 'DB_NAME'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }
    grep "define( 'DB_USER'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }
    grep "define( 'DB_PASSWORD'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }

    echo -e "\n
    ${BOLDGREEN}Database settings in wp-config.php have been updated. Restoration finished${ENDCOLOR}
    "
}

# Main script execution
echo -e "                                             ${BOLDGREEN}Hello fellow concierge! ${ENDCOLOR}\n"
check_user
find_backup
extract_backup
create_database
restore_sql_dump
update_wp_config

