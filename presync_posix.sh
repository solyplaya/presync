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

VERSION="1.1"
TARGET_USED="1"
TARGET_CONFLICT="0"
src=""
dst=""
db=""
hasher=""
head_size=0
muted=0
prune_dirs=0
tmp="/tmp"

add_to_db() {

    table="$1"
    file="$2"
    directory="${3%/}/"
    file_rel="${file#"$directory"}"

    hash=$(get_hash_from_file "$file")

    if [ -n "$hash" ]; then

        if [ -n "$db" ]; then
            db_query "INSERT OR REPLACE INTO $table (hash, path) VALUES ('$(escape_single_quotes "$hash")', '$(escape_single_quotes "$file_rel")');"
        else
            # be ware of special chars and interpretation of backslashes
            echo "$hash|$file_rel" >> "$tmp/presync.$table"
        fi

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

    [ -z "$db" ] && return
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

    if [ -n "$db" ]; then
        db_query "SELECT path FROM target WHERE hash = '$(escape_single_quotes "$1")' AND used = 0 LIMIT 1;"
    else
        cat "$tmp/presync.target" | grep -m 1 "$1" | cut -d '|' -f 2-
    fi

}

get_unique_sources(){

    if [ -n "$db" ]; then
        db_query "SELECT s.hash, s.path FROM source s LEFT JOIN target t ON s.hash = t.hash AND s.path = t.path WHERE t.id IS NULL;"
    else
        sort "$tmp/presync.source" > "$tmp/presync.source.sorted"
        sort "$tmp/presync.target" > "$tmp/presync.target.sorted"
        comm -23 "$tmp/presync.source.sorted" "$tmp/presync.target.sorted" > "$tmp/presync.source.unique"
        comm -13 "$tmp/presync.source.sorted" "$tmp/presync.target.sorted" > "$tmp/presync.target.unique"
        rm "$tmp/presync.source.sorted" "$tmp/presync.target.sorted" "$tmp/presync.source" "$tmp/presync.target"
        mv "$tmp/presync.source.unique" "$tmp/presync.source"
        mv "$tmp/presync.target.unique" "$tmp/presync.target"

        cat "$tmp/presync.source"
    fi

}

have_command(){

    command -v "$1" > /dev/null

}

main() {

    _custom_db=""

    [ -z "${1:-}" ] && show_help

    if ! (have_command "sqlite3"); then

        for cmd in comm cat cut find grep sed sort; do
            ! (have_command "$cmd") && error_exit "Error: presync requires $cmd command to run in plaintext mode."
        done

        msg "Notice: command sqlite3 not found - using slower plain text mode"
    else
        db="/tmp/presync.sqlite3"
    fi

    while [ $# -gt 0 ] ; do
        case "$1" in

            --database)
                if [ -n "$db" ]; then
                    _custom_db="${2:-}"
                    if ! (touch "$_custom_db" 2>/dev/null && [ -w "$_custom_db" ]); then
                        error_exit "Cannot create database: $_custom_db"
                    fi
                fi
                shift
                ;;
            --tmp)
                tmp="${2:-}"
                shift
                ;;
            --hasher)
                if have_command "${2:-}"; then
                    hasher="$2"
                else
                    error_exit "Error: custom hasher '${2:-}' is not a valid command"
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
            --prune-dirs)
                prune_dirs=1
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

    if [ -n "$db" ]; then

        if [ -n "$_custom_db" ]; then
            db="$_custom_db"
        else
            touch "$db" 2>/dev/null

            if [ ! -w "$db" ]; then
                error_exit "Cannot write database file: $db"
            fi
        fi

    else
        # plain text mode needs write permission to tmp dir
        [[ ! -d "$tmp" || ! -w "$tmp" ]] && error_exit "Temp directory '$tmp' does not exist or is not writable!"
        rm "$tmp/presync.source" "$tmp/presync.target" 2>/dev/null
    fi

    # try to find an available hasher
    if [ -z "$hasher" ]; then

        # test b2sum and cksum
        for cmd in xxh128sum sha1sum md5sum md5; do
            if have_command "$cmd"; then
                hasher="$cmd"
                [ "$hasher" != "xxh128sum" ] && msg "Notice: command xxh128sum not found - using slower hasher $hasher"
                break
            fi
        done

        [ -z "$hasher" ] && error_exit "Error: no checksum calculation program found. Use a custom command with option --hasher."

    fi

    sync_target

}

msg() {

    [ "$muted" -eq 0 ] && echo "${1:-}"

}

prune_dirs() {

    find "$dst" -type d -empty | while IFS= read -r dir; do

        # Check if dir path starts with directory as mitigation to filenames with new line characters
        if [ "${dir#"$dst"}" != "$dir" ] && [ -d "$dir" ]; then

            # only prune empty dir if it does not exist in src folder
            if [ ! -d "${src}${dir#"$dst"}" ]; then
                rmdir "$dir" 2>/dev/null
                prune_parents "$dir"
            fi
        fi

    done

}

prune_parents() {

    path="$1"

    dir="${path%/*}";

    # if dir does not exist in source, is not the root of dst or the last piece...
    if [ ! -d "${src}${dir#"$dst"}" ] && [ "$dst" != "$dir" ] && [ "$path" != "$dir" ]; then
        rmdir "$dir" 2>/dev/null
        prune_parents "$dir"
    fi

}

rename_conflicting_target() {

    _file="$1"
    _dir="${dst%/}/"
    _idx=1
    _target="${_file%.*}_[renamed_${_idx}].${_file##*.}"
    _hash=""

    while [ -f  "$_target" ]; do
        _idx=$((_idx+1))
        _target="${_file%.*}_[renamed_${_idx}].${_file##*.}"
    done

    if mv "$_file" "$_target"; then

        if [ -z "$db" ]; then
            _file_rel="${_file#"$_dir"}"
            _hash=$(cat "$tmp/presync.target" | grep -m 1 -F "$_file_rel" | cut -d '|' -f 1)
        fi

        # hash is only required in non db mode here
        update_target_path "$_file" "$_target" "$_hash" "$TARGET_CONFLICT"

    fi

}

show_help() {

    echo "presync.sh (posix) version $VERSION Copyright (c) 2025 Francisco Gonzalez
MIT license

presync renames files in target folder to match existing files in source folder
based on content checksums.

Usage: ${0##*/} [OPTION]... SRC DEST

Options
--database FILE  write the database to the specified FILE
--hasher CMD     use the given CMD to process file checksums
--help, -h       show this help
--muted, -m      don't output any text
--partial SIZE   calc checksums using at most N kilobytes from file
--prune-dirs     delete empty diretories left in target after processing
--tmp DIR        path to writable temp directory

presync does not copy or delete any files, only renames existing files in the
destination directory based on content hash to prevent unnecessary file copying
on rsync (or similar) command run.

presync only considers files, so if you rename a folder src/A to src/B,
the script will move all the files in dst/A to dst/B one by one, instead of
renaming the folder. Empty folders left in target after processing can be
deleted if passing the --prune-dirs option.

On conflicts existing files get renamed to filename_[renamed_1].ext

Using the --partial argument you can speed up the synchronization process since
only a smaller amount of data from the beginning of each file is used to calc
its checksum. This could lead to some false file matchings in the event that
various files share the same header data. Since no files are deleted or
overwritten, any incorrectly reorganized files will get resolved by rsync.

Database files are stored in /tmp/presync.sqlite and deleted after every run.
You can specify a custom database file and also a custom temporary directory in
case /tmp is not a writable path in your system.

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
                    update_target_path "$existing_target" "$target" "$hash" "$TARGET_USED"
                else
                    msg "Error: cannot move file!"
                fi

            fi

        fi

    done

    if [ -n "$db" ]; then
        rm "$db"
    else
        rm "$tmp/presync.source" "$tmp/presync.target"
    fi

    # check if dst is not empty first
    if [ "$prune_dirs" -eq 1 ] && [ -n "$(ls -A "$dst")" ]; then
        msg; msg "Deleting empty dirs in target..."
        # run in a subshell to keep cwd after execution
        # (cd "$dst" && prune_dirs)
        prune_dirs
    fi

    msg; msg "Done!"

}

update_target_path() {

    old_path="$1"
    new_path="$2"
    hash="$3"
    maybe_used=""
    [ "${4:-}" -eq 1 ] && maybe_used=", used=1"
    directory="${dst%/}/"
    old_path_rel="${old_path#"$directory"}"
    new_path_rel="${new_path#"$directory"}"

    if [ -n "$db" ]; then
        db_query "UPDATE target SET path='$(escape_single_quotes "$new_path_rel")' $maybe_used WHERE path='$(escape_single_quotes "$old_path_rel")';"
    else

        _esc_old=$(printf '%s' $(echo "$hash|$old_path_rel" | sed 's/\//\\\//g'))

        if [ "$used" -eq 0 ]; then
            _esc_new=$(printf '%s' $(echo "$hash|$new_path_rel" | sed 's/\//\\\//g'))
            # update path of existing file with different content
            sed -i "s/$_esc_old/$_esc_new/" "$tmp/presync.target"
        else
            # here simply delete the line... same effect as updating path and used state
            sed -i "/$_esc_old/{d; q}" "$tmp/presync.target"
        fi

    fi

}

trap cleanup_exit INT TERM

main "$@"

# EOF