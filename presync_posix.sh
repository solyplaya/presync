#!/usr/bin/env sh

# PreSync (posix version) - renames files in target folder to match existing
# files in source folder based on content checksums.
#
# MIT License
#
# Copyright (c) 2025 Francisco Gonzalez. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

hasher="xxh128sum"

VERSION="1.0"
src=""
dst=""
db="/tmp/presync.sqlite3"
head_size=0
muted=0

add_to_db() {

    table="$1"
    file="$2"
    directory="${3%/}/"
    file_rel="${file#"$directory"}"

    hash=$(get_hash_from_file "$file")

    if [ -n "$hash" ]; then
        db_query "INSERT OR REPLACE INTO $table (hash, path) VALUES ('$(escape_single_quotes "$hash")', '$(escape_single_quotes "$file_rel")');"
    else
        msg "Error: cannot generate checksum for file: $file"
    fi

}

cleanup_exit() {

    rm "$db"
    exit 1

}

collect_hashes() {

    table="$1"
    directory="$2"

    msg "Collecting $table checksums..."

    find "$directory" -type f | while IFS= read -r file; do
        # Check if file path starts with directory as mitigation to filenames with new line characters
        [ "${file#"$directory"}" != "$file" ] && [ -r "$file" ] && add_to_db "$table" "$file" "$directory"
    done

}

db_init() {

    [ -f "$db" ] && rm "$db"

    db_query '
CREATE TABLE source (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hash TEXT,
    path TEXT,
    used INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE target (
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

    msg "$1"
    exit 1

}

escape_single_quotes() {

    input="$1"
    output=""

    while [ -n "$input" ]; do
        char="${input%"${input#?}"}"
        rest="${input#?}"

        if [ "$char" = "'" ]; then
            output="${output}''"
        else
            output="${output}${char}"
        fi

        input="$rest"
    done

    printf '%s' "$output"

}

get_hash_from_file() {

    file="$1"
    hash=""

    if [ -r "$file" ]; then

        if [ "$head_size" -gt 0 ]; then
            hash=$(head -c "${head_size}"k "$file" | $hasher | cut -d' ' -f1)
        else
            hash=$($hasher "$file" | cut -d' ' -f1)
        fi

    fi

    printf '%s' "$hash"

}

get_target_path() {

    db_query "SELECT path FROM target WHERE hash = '$(escape_single_quotes "$1")' AND used = 0 LIMIT 1;"
}

get_unique_sources(){

    db_query "SELECT s.hash, s.path FROM source s LEFT JOIN target t ON s.hash = t.hash AND s.path = t.path WHERE t.id IS NULL;"

}

main() {

    [ -z "${1:-}" ] && show_help

    command -v "sqlite3" > /dev/null || error_exit "The program \"sqlite3\" is required to store file hashess"
    command -v "$hasher" > /dev/null || error_exit "The program \"$hasher\" is required to process file hashess"

    while [ $# -gt 0 ] ; do
        case "$1" in

            --database|-d)
                db="${2:-}"
                if ! (touch "$db" 2>/dev/null && [ -w "$db" ]); then
                    error_exit "Cannot create database: $db"
                fi
                shift
                ;;
            --help|-h)
                show_help
                ;;
            --muted|-m)
                muted=1
                ;;
            --partial)
                head_size="${2:-0}"
                if ! ([ -n "$head_size" ] && [ "$head_size" -eq "$head_size" ] 2>/dev/null && [ "$head_size" -gt 0 ]); then
                    error_exit "Invalid head size parameter value: $head_size"
                fi
                shift
                ;;
            --*|-*)
                error_exit "Unknown parameter: $1"
                ;;
            *)
                break
            ;;
        esac
        shift 1
    done

    src="${1:-}"
    dst="${2:-}"

    [ "$#" -ne 2 ] && error_exit "Missing source and target arguments."

    if [ ! -d "$src" ] || [ ! -r "$dst" ]; then
        error_exit "Source directory does not exist or is not readable!"
    fi

    if [ ! -d "$dst" ] || [ ! -w "$dst" ]; then
        error_exit "Destination directory does not exist or is not writable!"
    fi

    touch "$db" 2>/dev/null

    if [ ! -w "$db" ]; then
        error_exit "Cannot write database file: $db"
    fi

    sync_target

}

msg() {

    [ "$muted" -eq 0 ] && echo "${1:-}"

}

rename_conflicting_target() {

    _file="$1"
    _idx=1
    _target="${_file%.*}_[renamed_${_idx}].${_file##*.}"

    while [ -f  "$_target" ]; do
        _idx=$((_idx+1))
        _target="${_file%.*}_[renamed_${_idx}].${_file##*.}"
    done

    mv "$_file" "$_target" && update_target_path "$_file" "$_target"

}

show_help() {

    echo "presync.sh (posix) version $VERSION Copyright (c) 2025 Francisco Gonzalez
MIT license

presync renames files in target folder to match existing files in source folder
based on content checksums.

Usage: ${0##*/} [OPTION]... SRC DEST

Options
--database FILE  write the database to the specified FILE
--help, -h       show this help
--muted, -m      don't output any text
--partial SIZE   calc checksums using at most N kilobytes from file

presync does not copy or delete any files, only renames existing files in the
destination directory based on content hash to prevent unnecessary file copying
on rsync (or similar) command run.

presync only considers files, so if you rename a folder src/A to src/B,
the script will move all the files in dst/A to dst/B one by one, instead of
renaming the folder. Empty folders left behind are there to be deleted by your
rsync program run.

On conflicts existing files get renamed to filename_[renamed_1].ext

Using the --partial argument you can speed up the synchronization process since
only a smaller amount of data from the beginning of each file is used to calc
its checksum. This could lead to some false file matchings in the event that
various files share the same header data. Since no files are deleted or
overwritten, any incorrectly reorganized files will get resolved by rsync.

Database files are stored in /tmp/presync.sqlite and deleted after every run.
You can specify a custom database file location in case /tmp is not a writable
path in your system.

This version of presync.sh does not handle filenames with newline characters.

Example usage:

synchronize renamed files in backup
    presync /home/user/Pictures /media/backup/Pictures

synchronize movies collection on slow USB drive with huge files:
    presync --partial 512 --keep-db /media/movies /media/movies_backup

"
    exit

}

sync_target() {

    idx=0

    db_init
    collect_hashes "target" "$dst"
    collect_hashes "source" "$src"

    msg "presync-ing..."

    get_unique_sources | while IFS= read -r row; do

        # This handles filenames with pipe character because the filename column is the last from the query
        file="${row#*|}"
        hash="${row%%|*}"

        target="$dst/$file"

        existing_target="$(get_target_path "$hash")"

        if [ -n "$existing_target" ]; then

            idx=$((idx+1))

            existing_target="$dst/$existing_target"

            msg
            msg "[$idx] $src/$file"

            # Rename existing target with different content since we have a candidate to take its place.
            [ -f "$target" ] && rename_conflicting_target "$target"

            # Create intermediary folders as needed
            [ ! -d "${target%/*}" ] && mkdir -p "${target%/*}"

            if [ -f "$target" ]; then
                msg  "Error: cannot rename conflicting target: $target"
            else
                msg "$existing_target"
                msg "$target"

                if mv "$existing_target" "$target"; then
                    update_target_path "$existing_target" "$target"
                else
                    msg "Error: cannot move file!"
                fi

            fi

        fi

    done

    rm "$db"
    msg
    msg "Done!"

}

update_target_path() {

    old_path="$1"
    new_path="$2"
    directory="${dst%/}/"
    old_path_rel="${old_path#"$directory"}"
    new_path_rel="${new_path#"$directory"}"

    db_query "UPDATE target SET path='$(escape_single_quotes "$new_path_rel")', used=1 WHERE path='$(escape_single_quotes "$old_path_rel")';"

}

trap cleanup_exit INT TERM

main "$@"

# EOF