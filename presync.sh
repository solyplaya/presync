#!/bin/bash

# PreSync v 1.0 - 2025-01-26
#
# BSD-2 License
#
# Copyright 2025 Francisco Gonzalez. All rights reserved.
#
# Redistribution and use in source and binary forms, with or
# without modification, are permitted provided that the
# following conditions are met:
#
#   1. Redistributions of source code must retain the above
#      copyright notice, this list of conditions and the
#      following disclaimer.
#
#   2. Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the
#      following disclaimer in the documentation and/or other
#      materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# The views and conclusions contained in the software and documentation
# are those of the authors and contributors and should not be interpreted
# as representing official policies, either expressed or implied, of anybody
# else.

set -o nounset

hasher="xxh128sum"
tmp="/tmp"

VERSION="1.1"

src=""
dst=""
db="${tmp}/presync.sqlite3"

debug=0
dry_run=0
flush_db=0
head_size=1024
keep_db=0
partial=0
progress=0
quiet=0
resume=0
reuse_db=0
term_width=80
verbose=0

add_to_db() {

    local file="$1"
    local hash=$(get_hash_from_file "$file")

    # only add if we could read the file to compute the hash
    if [[ -n "$hash" ]]; then
        db_query "INSERT OR REPLACE INTO files (hash, path) VALUES ('${hash//\'/\'\'}', '${file//\'/\'\'}');"
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
    local files
    local total=0
    local resume_file=""
    local progress_msg=""

    echo "Collecting target dir file checksums..."

    [[ "$progress" = 1 ]] && total=$(get_total_files "$dst")

    [[ "$resume" = 1 ]] && resume_file=$(get_last_file)

    # https://stackoverflow.com/questions/71270045/print-periodic-progress-messages-on-the-same-line
    # progress bar
    while IFS= read -d '' -r file ; do

        (( idx++ ))

        if [[ -n "$resume_file" ]]; then
            if [[ "$resume_file" = "$file" ]]; then
                resume_file=""
            fi
            continue
        fi

        [[ "$progress" = 1 ]] && progress_msg="[${idx}/${total}] "

        inplace_msg "${progress_msg}${file}"

        add_to_db "${file}"

    done < <(find "$dst" -type f -print0)

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

get_hash_from_file() {

    local file="$1"
    local hash=""
    local hash_tmp=""

    if [ -r "$file" ]; then

        # xxh128sum messes inplace line display with output to stderr here
        if [[ "$partial" = 1 ]]; then
            hash_tmp=$(head -c ${head_size}k "$file" | $hasher 2>/dev/null)
        else
            hash_tmp=$($hasher "$file" 2>/dev/null)
        fi

        # use regex instead of cut for edge cases of filenames with newline characters
        [[ $hash_tmp =~ ^\\?([0-9a-f]+) ]] && hash="${BASH_REMATCH[1]}"

    fi

    echo -n "$hash"

}

get_path() {

    db_query "SELECT path FROM files WHERE hash = '${1//\'/\'\'}' AND used = 0 LIMIT 1;"
}

get_total_files() {

    local total=0
    local path="$1"

    while IFS= read -r -d '' file; do
        ((total++))
    done < <(find "$path" -type f -print0)

    echo -n "$total"

}

info_msg() {

    [[ "$quiet" = 1 ]] && return

    local green='\033[1;32m'
    local nocolor='\033[0m'

    echo -e "\n${green}${1:-}${nocolor}"

}

inplace_msg() {

    local msg="${1:-}"
    local max_len
    local msg_left
    local msg_right

    # replace newline characters with escaped representation for single line display
    # msg="${msg//$'\n'/\\\\n}"

    # for now replace inplace message new lines with a single space
    msg="${msg//$'\n'/ }"
    clear_line

    if [ ${#msg} -gt $term_width ]; then
        max_len=$((term_width - 5))
        msg_left=$((max_len / 2))
        msg_right=$((max_len - msg_left))
        msg="${msg:0:$msg_left}...${msg: -$msg_right}"
    fi

    echo -ne "${msg}\r"

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

    echo "presync version $VERSION Copyright (c) Francisco Gonzalez

presync renames files in a backup to match a reorganized source folder enabling
efficient synchronization with rsync without unnecessary file copying.

Usage: presync [OPTION]... SRC DEST

Options
--debug, -d      dumps database of targets before / after processing
--dry-run        trial run without file changes (implies --keep-db)
--flush-db, -f   remove any existing db without asking
--help, -h       show this help
--keep-db, -k    don't delete database after running (ignores --flush-db)
-p               same as --partial $head_size
--partial SIZE   calc checksums using at most N kilobytes from file
--progress       show progress of total files
--quiet, -q      show less text output and use inplace progress messages
--resume         resume from last record in database (implies --reuse-db)
--reuse-db, -r   use an existing database of targets without asking
--verbose, -v    increase verbosity

presyn does not copy or delete any files, only renames existing files in the
destination directory based on content hash to prevent unnecessary file copying
on rsync (or similar) command run.

presync only considers files, so if you rename a folder src/A to src/B,
the script will move all the files in dst/A to dst/B one by one, instead of
renaming the folder. Empty folders left behind are there to be deleted by your
rsync program run.

On conflicts existing files get renamed to filename_[renamed_1].ext

Using the --partial argument you can speed up the synchronization process since
only a smaller amount of data from the begining of each file is used to calc
its checksum. This could lead to some false file matchings in the event that
various files share the same header data. Since no files are deleted or
overwritten, any incorrectly reorganized files will get resolved by rsync.

Database files are stored in /tmp/presync-[SOURCE|DEST|PARTIAL_SIZE].sqlite
and deleted after a successfull run unless --keep-db or --dry-run options are
given.

Example usage:

synchronize renamed files in backup
    presync /home/user/Pictures /media/backup/Pictures

synchronize move collection on slow USB drive with huge files:
    presync --partial 2048 --keep-db /media/movies /media/movies_backup

"
    exit

}



sync_target() {

    local target
    local idx=0
    local files
    local total=0
    local progress_msg=""

    # stats: total files in source, total files in dest, total renamed files
    #        total identcal files in same path, total files in source not in target
    #        total files in target not in source

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

    [[ "$progress" = 1 ]] && total=$(get_total_files "$dst")

    while IFS= read -r -d '' file; do

        (( idx++ ))

        [[ "$progress" = 1 ]] && progress_msg="[${idx}/${total}] "

        [[ "$quiet" = 1 ]] && inplace_msg "${progress_msg}${file}"

        # verbose mode, show all files
        [[ "$verbose" = 1 ]] && info_msg "${progress_msg}${file}"

        hash=$(get_hash_from_file "$file")
        target="${file/#$src/$dst}"

        if [[ -z "$hash" ]]; then
            error_msg "Error: cannot generate checksum for file: $file"
            continue
        fi

        [[ -f "$target" ]] && is_same_file "$target" "$hash" && continue

        existing_target="$(get_path "$hash")"

        # file exists in another path?
        if [[ -n "$existing_target" ]]; then

            # normal mode, show only files being processed
            [[ "$verbose" = 0 ]] && info_msg "${progress_msg}${file}"

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

    done < <(find "$src" -type f -print0)

    if [[ "$debug" = 1 ]]; then
        notice_msg "\nList of collected target hashes after processing: (id, hash, path, used)"
        db_query "select * from files;"
    fi

    clear_line
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
            --progress)
                progress=1
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

    # prevent long inplace messages from cluttering the terminal window
    term_width=$(tput cols)

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