#!/bin/bash

# author Gennadiy Tselischev

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

    read -rp "> Do you want to proceed? [y/n]: " CHOICE
    [[ ! "${CHOICE}" =~ ^[yY](es)?$ ]] && { echo "! Ok, next time"; exit 1; }

    BACKUP="$(awk -F/ '{print $NF}' <<<"${CHOSEN_BACKUP}")"
}

# Function to extract the selected backup
extract_backup() {
    if [[ "${BACKUP}" == *.tar.gz ]]; then
        echo "Extracting ${BACKUP} as a .tar.gz archive..."
        tar -zxvf "${CHOSEN_BACKUP}" &>/dev/null
        echo "Backup ${BACKUP} was restored successfully!"
    elif [[ "${BACKUP}" == *.zip ]]; then
        echo "Extracting ${BACKUP} as a .zip archive..."
        unzip "${CHOSEN_BACKUP}" &>/dev/null
        echo "Backup ${BACKUP} was restored successfully!"
    else
        echo "! Unsupported file format or backup is corrupted. Check it manually"
        exit 1
    fi
    
}

# Function to create a database and a user
create_database() {
    DIR_NAME="$PWD"
    DIR_NAME=$(basename "$PWD" | rev | cut -d. -f2- | rev)
    DB_NAME="${USER}_${DIR_NAME}"
    DB_PASS=$(tr -dc 'A-Za-z0-9_!@#$%^&*()-+=' </dev/urandom | head -c 16)

    echo -e "Your database details (just in case):\n"
    echo "Database Name: $DB_NAME"
    echo "Database User: $DB_NAME"
    echo "Database Password: $DB_PASS"

    echo -e "\nCreating a new database using the details obtained...\n"

    if uapi Mysql create_database name="$DB_NAME" &>/dev/null; then
        echo -e "\nDatabase $DB_NAME created successfully."
    else
        echo "Failed to create database $DB_NAME . Check it manually"
    fi

    if uapi Mysql create_user name="$DB_NAME" password="$DB_PASS" &>/dev/null; then
        echo "Database user $DB_NAME created successfully."
    else
        echo "Failed to create database user $DB_NAME. Check it manually"
    fi

    if uapi Mysql set_privileges_on_database user="$DB_NAME" database="$DB_NAME" privileges=ALL &>/dev/null; then
        echo "Privileges for user $DB_NAME on database $DB_NAME granted successfully."
    else
        echo "Failed to grant privileges for user $DB_NAME on database $DB_NAME. Check it manually"
    fi
}

# Function to find and restore SQL dumps
restore_sql_dump() {
    echo -e "\nAvailable .sql dumps to restore:\n"
    
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

    read -rp "> Do you want to proceed? [y/n]: " CHOICE
    [[ ! "${CHOICE}" =~ ^[yY](es)?$ ]] && { echo "! Ok, next time"; exit 1; }

    DUMP="$(awk -F/ '{print $NF}' <<<"${CHOSEN_DUMP}")"

    echo -e "\nImporting selected dump to the database..."

    if mysql -f -u "$DB_NAME" -p"$DB_PASS" "$DB_NAME" < "$DUMP" &>/dev/null; then
        echo "${DUMP} imported successfully"
    else
        echo "Failed to import the .sql dump. Please check it manually"; exit 1;
    fi
}

# Function to update wp-config.php with new database values
update_wp_config() {
    WP_CONFIG=$(find . -maxdepth 1 -name "wp-config.php")
    if [[ -z "$WP_CONFIG" ]]; then
        echo "Error: wp-config.php file not found in the current directory."
        exit 1
    fi
    echo "wp-config.php file found: $WP_CONFIG"

echo -e "\nCurrent Database Configuration:"
grep "define( 'DB_NAME'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }
grep "define( 'DB_USER'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }
grep "define( 'DB_PASSWORD'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }

echo -e "\nUpdating wp-config.php with new database settings..."

sed -i "s/^\(define( 'DB_NAME', '\)[^']*\('.*;\)$/\1$DB_NAME\2/" "$WP_CONFIG" || { echo "Something went wrong. Proceed further manually"; exit 1; }
sed -i "s/^\(define( 'DB_USER', '\)[^']*\('.*;\)$/\1$DB_NAME\2/" "$WP_CONFIG" || { echo "Something went wrong. Proceed further manually"; exit 1; }
sed -i "s/^\(define( 'DB_PASSWORD', '\)[^']*\('.*;\)$/\1$DB_PASS\2/" "$WP_CONFIG" || { echo "Something went wrong. Proceed further manually"; exit 1; }

echo -e "\nVerifying the updates in wp-config.php:"
    grep "define( 'DB_NAME'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }
    grep "define( 'DB_USER'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }
    grep "define( 'DB_PASSWORD'" "$WP_CONFIG" || { echo "DB_NAME not found. Check and proceed further manually"; exit 1; }

    echo -e "\nDatabase settings in wp-config.php have been updated."
}

# Main script execution
echo -e "Hello fellow concierge! Let's restore another site today =)\n"
find_backup
extract_backup
create_database
restore_sql_dump
update_wp_config
