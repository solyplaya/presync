#!/bin/bash

# PreSync v 1.0 - 2025-01-26
# (c) 2025 Francisco Gonzalez
# BSD-2 License - or like sqlite3 and yt-dlp, unlicense public domain. To decide.
#
# Script to sync renamed filesystem structure between 2 synced directories.
# Does not copy or delete any files, only renames existing files in target
# directory based on content hash to prevent unneeded file copying on rsync
# command run.

# Note that script is not smart enough to handle the scenario where you rename src/A to src/B, the script will
# move all the files in dst/A to dst/B one by one, instead of renaming the folder.

# --dry-run implies --keep-db (gotcha not 100% same final result) USeful also to pregenerate the hases db of target
# --reuse-db reuses db if present without asking
# --flush-db removes any existing db without asking. If --reuse-db is provided, --reuse-db takes preference
# --keep-db does not delete the database after running.
# --resume ... implies reuse-db. Continue processing files from last record in database, as long as there's a DB of course.
# --debug dumps database of targets before / after processing
# --verbose Causes to show all files in source folder instead only ones that need moving
# --partial= use the provided number of kilobytes from the begining of the file for partial checksum calculations
# -p same as partial but use the default 1024kb head size instead of specifying one
#
# TODO:
# x rework paramater parsing
# x add support for partial file hashes with optional chunk size with param validation regex: head -c 1024k largefile | xxh128sum
# - add usage information / documentation / license info
# - add stats of actions done, specially useful for --quiet view
# - log file option? (moved files and renamed files in the log)
# x bring this to fossil-scm... it is growing a bit more than a one time use shell script for my file sync needs.
# - add command to wipe all databases in temp dir. aka rm /tmp/presync-*.sqlite3
# - move todo list to fossil
#
# For the DOCS:
# Each database is associated to a source/destination folder combination and stored in tmp folder

set -o nounset

hasher="xxh128sum"
tmp="/tmp"

src=""
dst=""
db="${tmp}/presync.sqlite3"

debug=0
dry_run=0
flush_db=0
head_size=1024
keep_db=0
partial=0
quiet=0
resume=0
reuse_db=0
verbose=0

add_to_db() {

    local file="$1"
    local hash=""
    local path="${file}"

    # xxh128sum messes inplace line display with output to stderr here
    if [[ "$partial" = 1 ]]; then
        hash=$(head -c ${head_size}k $file | $hasher 2>/dev/null | cut -d' ' -f1)
    else
        hash=$($hasher "$file" 2>/dev/null | cut -d' ' -f1)
    fi

    # only add if we could read the file to compute the hash
    if [[ -n "$hash" ]]; then
        db_query "INSERT OR REPLACE INTO files (hash, path) VALUES ('${hash//\'/\'\'}', '${path//\'/\'\'}');"
    else
        error_msg "Error: cannot generate checksum for file: $file"
    fi

}

cleanup_exit() {

    clear_line
    [[ "$keep_db" = 0 ]] && rm "$db"
    exit

}

clear_line(){

    echo -ne "\033[K"

}

collect_target_hashes() {

    local file
    local idx=0
    local IFS=$'\n'
    local files
    local total=0
    local resume_file=""

    echo "Collecting target dir file checksums..."

    files=$(find "$dst" -type f | sort)
    total=$(wc -l <<< "$files")

    if [[ "$resume" = 1 ]]; then

        resume_file=$(get_last_file)
    fi

    # https://stackoverflow.com/questions/71270045/print-periodic-progress-messages-on-the-same-line
    # progress bar
    for file in $files; do

        (( idx++ ))

        if [[ -n "$resume_file" ]]; then
            if [[ "$resume_file" = "$file" ]]; then
                resume_file=""
            fi
            continue
        fi

        inplace_msg "[${idx}/${total}] $file"

        add_to_db "${file}"

    done

}

db_init() {

    local response
    local params_hash=$(echo -n "$src|$dst|$partial|$head_size" | $hasher | cut -d' ' -f1)

    db="$tmp/presync-${params_hash}.sqlite3"

    # new db on each run onless resue specified
    if [ -f "$db" ]; then

        # resume implies reuse database
        [[ "$resume" = 1 ]] && reuse_db=1

        if [[ "$flush_db" = 0 && "$reuse_db" = 0 ]]; then

            read -p "A database from a previous run already exists, reuse? (y/N): " response

            if [[ "${response,,}" = "y" || "${response,,}" = "yes" ]]; then
                reuse_db=1
            fi

        fi

        if [[ "$reuse_db" = 1 ]]; then
            info_msg "Reusing existing database file: $db"
            return
        fi

        # Delete existing database since not reusing it
        rm "$db"

    fi

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

    error_msg "$1"
    exit 1

}

error_msg() {

    local red='\033[1;31m'
    local nocolor='\033[0m'

    echo -e "\n${red}${1:-}${nocolor}"

}

get_last_file(){

    db_query "SELECT path FROM files ORDER BY id DESC LIMIT 1;"
}

get_hash() {

    db_query "SELECT hash FROM files WHERE path = '${1//\'/\'\'}' LIMIT 1;"

}

get_path() {

    db_query "SELECT path FROM files WHERE hash = '${1//\'/\'\'}' AND used = 0 LIMIT 1;"
}

info_msg() {

    [[ "$quiet" = 1 ]] && return

    local green='\033[1;32m'
    local nocolor='\033[0m'

    echo -e "\n${green}${1:-}${nocolor}"

}

inplace_msg() {

    clear_line
    echo -ne "${1:-}\r"
}

is_same_file() {

    local file="${1}"
    local source_hash="${2}"
    local target_hash=$(get_hash "$file")

    [[ "$source_hash" == "$target_hash" ]]

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
    print_msg "Renaming existing target with different content: $file -> $target"

    # Rename and update only on success
    [[ "$dry_run" = 0 ]] && mv "$file" "$target" && update_path "$file" "$target"

}

update_path() {

    local old_path="$1"
    local new_path="$2"

    db_query "UPDATE files SET path='${new_path//\'/\'\'}', used=1  WHERE path='${old_path//\'/\'\'}';"

}

show_help() {

    echo "
This script synchronizes renamed folder content based on file hashes.
    Usage: $0 <source_directory> <target_directory>
"
    exit

}

sync_target() {

    local hash
    local target

    local idx=0
    local IFS=$'\n'
    local files
    local total=0

    # stats: totla files in source, total files in dest, total renamed files
    #        total identcal files in same path, total files in source not in target
    #        total files in target not in source

    local moved_files=0

    db_init

    if [[ "$reuse_db" = 0 || "$resume" = 1 ]]; then
        collect_target_hashes
    fi

    if [[ "$debug" = 1 ]]; then
        notice_msg "\nList of collected target hashes before processing: (id, hash, path, used)"
        db_query "select * from files;"
    fi

    clear_line

    # print message regardless of verbosity level
    echo "Processing sources and presyncing..."
    print_msg "(Only files in need of reloaction are shown below)"

    files=$(find "$src" -type f | sort)
    total=$(wc -l <<< "$files")

    for file in $files; do

        (( idx++ ))

        [[ "$quiet" = 1 ]] && inplace_msg "[${idx}/${total}] $file"

        # verbose mode, show all files
        [[ "$verbose" = 1 ]] && info_msg "[${idx}/${total}]: $file"

        # here hasher stderr for some reason is not messing inplace message display
        if [[ "$partial" = 1 ]]; then
            hash=$(head -c ${head_size}k $file | $hasher | cut -d' ' -f1)
        else
            hash=$($hasher "$file" | cut -d' ' -f1)
        fi

        target="${file/#$src/$dst}"

        [[ -f "$target" ]] && is_same_file "$target" "$hash" && continue

        existing_target="$(get_path "$hash")"

        # file exists in another path?
        if [[ -n "$existing_target" ]]; then

            # normal mode, show only files being processed
            [[ "$verbose" = 0 ]] && info_msg "[${idx}/${total}]: $file"

            # Rename existing target with different content since we have a candidate to take its place.
            [[ -f "$target" ]] && rename_existing_target "$hash" "$target"

            # create intermediary folders as needed
            [[ "$dry_run" = 0 ]] && [[ ! -d "${target%/*}" ]] && mkdir -p "${target%/*}"

            if [ -f "$target" ]; then
                [[ "$dry_run" = 0 ]] && echo "Error: target file with different content already exists! May not have permission to move conflicting file:"
            else
                # move existing_target to $target
                print_msg "Moving: $existing_target -> $target"

                if [ "$dry_run" = 0 ] && mv "$existing_target" "$target"; then
                    # update database entry so we don't create orphans
                    update_path "$existing_target" "$target"
                else
                    # error_msg could be skipped on dry_run
                    [[ "$dry_run" = 0 ]] && error_msg "Error: cannot move file!"
                fi

            fi

        fi

    done

    if [[ "$debug" = 1 ]]; then
        notice_msg "\nList of collected target hashes after processing: (id, hash, path, used)"
        db_query "select * from files;"
    fi

    echo "Done!"

}

main() {

    local head_regex='[0-9]{2,}'

    [ -z "${1:-}" ] && show_help

    command -v "sqlite3" > /dev/null || error_exit "The program \"sqlite3\" is required to store file hashess"
    command -v "$hasher" > /dev/null || error_exit "The program \"$hasher\" is required to process file hashess"

    while [ ${#} -gt 0 ] ; do
        case "${1}" in

            --debug|-d)
                debug=1
                ;;
            --dry-run)
                dry_run=1
                ;;
            --flush-db|-f)
                flush_db=1
                ;;
            --help|-h)
                show_help
                ;;
            --keep-db|-k)
                keep_db=1
                ;;
            -p)
                partial=1
                info_msg "using $head_size head size"
                ;;
            --partial)
                partial=1
                head_size="${2:-${head_size}}"
                [[ ! $head_size =~ $head_regex ]] && error_exit "Invalid head size paramater value: $head_size"
                info_msg "using $head_size head size"
                shift 1
                ;;
            --quiet|-q)
                quiet=1
                ;;
            --resume)
                resume=1
                ;;
            --reuse-db|-r)
                reuse_db=1
                ;;
            --verbose|-v)
                verbose=1
                ;;
            # Catch any unknown argument and stop processing
            --*|-*)
                error_exit "Unknown parameter: $1"
                usage
                ;;
            *)
                # Stop processing when we encounter a positional argument
                break
            ;;
        esac
        shift 1
    done

    src="${1:-}"
    dst="${2:-}"

    [[ "$#" -ne 2 ]] && error_exit "Missing source and target arguments."

    [[ ! -d "$src" || ! -r "$dst" ]] && error_exit "Source directory does not exist or is not readable!"
    [[ ! -d "$dst" || ! -w "$dst" ]] && error_exit "Destination directory does not exist or is not writable!"
    [[ ! -d "$tmp" || ! -w "$tmp" ]] && error_exit "Temp directory does not exist or is not writable!"

    if [[ "$dry_run" = 1 ]]; then
        keep_db=1
        notice_msg "(Dry run mode - no filesystem changes. Preserving database after run.)"
    fi

    sync_target
    cleanup_exit

}

notice_msg() {

    local yellow='\033[1;93m'
    local nocolor='\033[0m'

    echo -e "${yellow}${1:-}${nocolor}"

}

print_msg() {

    [[ "$quiet" = 1 ]] && return
    echo -e "${1:-}"

}

# Trap interrupts and exit instead of continuing any loops
trap cleanup_exit SIGINT SIGTERM

main "$@"

# EOF