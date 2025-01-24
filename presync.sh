#!/bin/bash

# Script to sync renamed filesystem structure between 2 syned directories.
# Does not copy or delete any files, only renames existing files in target
# directory based on content hash to prevent unneeded file copying on rsync
# command run.

# Note that script is not smart enough to handle the scenario where you rename src/A to src/B, the script will
# move all the files in dst/A to dst/B one by one, instead of renaming the folder.

set -o nounset

src="${1:-}"
dst="${2:-}"
db="/tmp/file_db.sqlite3"
hasher="xxh128sum"

add_to_db() {

    local file="$1"
    echo -n "Hasing: $file"

    local hash=$($hasher "$file" | cut -d' ' -f1)
    local path="${file}"

    # only add if we could read the file to compute the hash
    [[ -n "$hash" ]] && db_query "INSERT OR REPLACE INTO files (hash, path) VALUES ('${hash//\'/\'\'}', '${path//\'/\'\'}');"

    echo -ne "\r"
}

db_init() {

    # new db on each run
    [[ -f "$db" ]] && rm "$db"

    db_query '
CREATE TABLE files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hash TEXT,
    path TEXT,
    used INTEGER NOT NULL DEFAULT 0
);
'

}

db_query() {

    echo "$1" | sqlite3 "$db" || error_exit "sqlite3 database query error!: $1"

}

error_exit() {

    echo -e "$1"
    exit 1

}

get_hash() {

    db_query "SELECT hash FROM files WHERE path = '${1//\'/\'\'}' LIMIT 1;"

}

get_path() {

    db_query "SELECT path FROM files WHERE hash = '${1//\'/\'\'}' AND used = 0 LIMIT 1;"
}

is_same_file() {

    local file="${1}"
    local source_hash="${2}"
    local target_hash=$(get_hash "$file")

    [[ "$source_hash" == "$target_hash" ]]

}

process_directory() {

    local file

    echo "Collecting file checksums..."

    # add relative path to directory
    while IFS= read -d $'\0' -r file ; do add_to_db "${file}"; done < <(find "$dst" -type f -print0 | sort -z)

}

rename_existing_target() {

    local hash="$1"
    local file="$2"
    local idx=1
    local new_name
    local target="${file%.*}_[renamed_${idx}].${file##*.}"

    while [ -f  "$target" ]; do
        ((idx++))
        target="${file%.*}_[renamed_${idx}].${file##*.}"
    done

    # unique filename, now rename...
    echo "Renaming existing target with different content: $file -> $target"
    mv "$file" "$target"

    update_path "$file" "$target"

}

update_path() {

    local old_path="$1"
    local new_path="$2"

    db_query "UPDATE files SET path='${new_path//\'/\'\'}', used=1  WHERE path='${old_path//\'/\'\'}';"

}

main() {

    local hash
    local target

    # Check if source and target directories are provided
    if [[ ! -d "$src" || ! -d "$dst" ]]; then

        error_exit "This script synchronizes renamed folder content based on file hashes.\nUsage: $0 <source_directory> <target_directory>"

    fi

    db_init

    process_directory

    # debug temp
    # db_query "select * from files;"

    while IFS= read -d $'\0' -r file; do

        hash=$($hasher "$file" | cut -d' ' -f1)
        target="${file/#$src/$dst}"


        [[ -f "$target" ]] && is_same_file "$target" "$hash" && continue

        existing_target="$(get_path "$hash")"

        # file exists in another path?
        if [[ -n "$existing_target" ]]; then

            echo -e "\nProcessing: $file"

            # Rename existing target with different content since we have a candidate to take its place.
            [[ -f "$target" ]] && rename_existing_target "$hash" "$target"

            # create intermediary folders as needed
            [[ ! -d "${target%/*}" ]] && mkdir -p "${target%/*}"

            if [ -f "$target" ]; then
                echo "Error: target file with different content already exists! May not have permission to move conflicting file:"
                echo "$target"
            else
                # move existing_target to $target
                echo "Moving: $existing_target -> $target"
                mv "$existing_target" "$target"

                # update database entry so we don't create orphans
                update_path "$existing_target" "$target"
            fi

        fi

    done < <(find "$src" -type f -print0 | sort -z)

    echo -e "\nDone!\n"

    # debug
    # db_query "select * from files;"

}

# Trap interrupts and exit instead of continuing any loops
trap "echo Exited!; exit;" SIGINT SIGTERM
main

# EOF