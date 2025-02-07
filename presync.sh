#!/bin/bash

# PreSync - renames files in target folder to match existing files in source
# folder based on content checksums.
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

set -o nounset

hasher="xxh128sum"
tmp="/tmp"

VERSION="1.4"

readonly SHOW_FROM_DEBUG="5"
readonly SHOW_FROM_VERBOSE="4"
readonly SHOW_FROM_NORMAL="3"
readonly SHOW_FROM_COMPACT="2"
readonly SHOW_FROM_QUIET="1"
readonly SHOW_FROM_MUTED="0"

readonly MSG_TYPE_ERROR="error"
readonly MSG_TYPE_INFO="info"
readonly MSG_TYPE_WARNING="warning"
readonly MSG_TYPE_NORMAL="normal"
readonly MSG_TYPE_INPLACE="inplace"

readonly TABLE_SOURCE="source"
readonly TABLE_TARGET="target"

src=""
dst=""
db="${tmp}/presync.sqlite3"

dry_run=0
flush_db=0
head_size=1024
keep_db=0
no_color=0
partial=0
progress=0
resume=0
reuse_db=0
term_width=80
verbosity="$SHOW_FROM_NORMAL"

add_to_db() {

    local table="$1"
    local file="$2"
    local directory="${3/%\//}/"
    local file_rel="${file/#$directory}"
    local hash=$(get_hash_from_file "$file")

    # only add if we could read the file to compute the hash
    if [[ -n "$hash" ]]; then
        db_query "INSERT OR REPLACE INTO $table (hash, path) VALUES ('${hash//\'/\'\'}', '${file_rel//\'/\'\'}');"
    else
        msg_error "Error: cannot generate checksum for file: $file"
    fi

}

cleanup_exit() {

    clear_line
    [[ "$keep_db" = 0 ]] && rm "$db"
    exit

}

clear_line(){

    [[ "$verbosity" -gt "$SHOW_FROM_MUTED" ]] && echo -ne "\033[K"

}

collect_hashes() {

    local table="$1"
    local directory="$2"

    local file
    local idx=0
    local files
    local total=0
    local resume_file=""
    local progress_msg=""
    local percent=""

    msg "Collecting $table checksums..." "$SHOW_FROM_COMPACT"

    [[ "$progress" = 1 ]] && total=$(get_total_files "$directory")
    [[ "$resume" = 1 ]] && resume_file=$(get_last_file "$table")

    while IFS= read -d '' -r file ; do

        (( idx++ ))

        if [[ -n "$resume_file" ]]; then
            if [[ "$resume_file" = "$file" ]]; then
                resume_file=""
            fi
            continue
        fi

        if [[ "$progress" = 1 ]]; then
            percent=$((idx * 100 / total))
            progress_msg="[${idx}/${total} (${percent}%] "
        fi

        if [[ "$verbosity" -eq "$SHOW_FROM_QUIET" ]]; then
            [[ "$progress" = 1 ]] && msg_inplace "Collecting $table checksums: ${idx}/${total} (${percent}%)" "$SHOW_FROM_QUIET"
        else

            if [[ ( "$verbosity" -eq "$SHOW_FROM_COMPACT" || "$verbosity" -eq "$SHOW_FROM_NORMAL" ) ]]; then
                msg_inplace "${progress_msg}${file}" "$verbosity"
            else
                msg_normal "${progress_msg}${file}"
            fi

        fi

        add_to_db "$table" "${file}" "${directory}"

    done < <(find "$directory" -type f -print0)

}

collect_source_hashes() {

    collect_hashes "$TABLE_SOURCE" "$src"

}

collect_target_hashes() {

    collect_hashes "$TABLE_TARGET" "$dst"

}

db_init() {

    local response
    local params_hash=$(echo -n "$(realpath "$src")|$(realpath "$dst")|$partial|$head_size" | $hasher | cut -d' ' -f1)

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
            msg_info "Reusing existing database file: $db"
            return
        fi

        # Delete existing database since not reusing it
        rm "$db"

    fi

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

db_query_ascii() {

    echo "$1" | sqlite3 -ascii "$db" || error_exit "sqlite3 database query error!: $1"

}

error_exit() {

    msg_error "$1"
    exit 1

}

get_last_file(){

    local table="$1"

    db_query "SELECT path FROM $table ORDER BY id DESC LIMIT 1;"

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

get_target_path() {

    db_query "SELECT path FROM target WHERE hash = '${1//\'/\'\'}' AND used = 0 LIMIT 1;"
}

get_unique_sources(){

    db_query_ascii "SELECT s.hash, s.path FROM source s LEFT JOIN target t ON s.hash = t.hash AND s.path = t.path WHERE t.id IS NULL;"

}

get_unique_sources_count(){

    db_query "SELECT COUNT(*) FROM source s LEFT JOIN target t ON s.hash = t.hash AND s.path = t.path WHERE t.id IS NULL;"

}

get_total_files() {

    local total=0
    local path="$1"

    while IFS= read -r -d '' file; do
        ((total++))
    done < <(find "$path" -type f -print0)

    echo -n "$total"

}

main() {

    local head_regex='[0-9]{2,}'

    [ -z "${1:-}" ] && show_help

    command -v "sqlite3" > /dev/null || error_exit "The program \"sqlite3\" is required to store file hashess"
    command -v "$hasher" > /dev/null || error_exit "The program \"$hasher\" is required to process file hashess"

    while [ ${#} -gt 0 ] ; do
        case "${1}" in

            --compact|-c)
                verbosity="$SHOW_FROM_COMPACT"
                ;;
            --debug|-d)
                verbosity="$SHOW_FROM_DEBUG"
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
            --muted|-m)
                verbosity="$SHOW_FROM_MUTED"
                ;;
            --no-color|-n)
                no_color=1
                ;;
            -p)
                partial=1
                msg_info "using $head_size head size"
                ;;
            --partial)
                partial=1
                head_size="${2:-${head_size}}"
                [[ ! $head_size =~ $head_regex ]] && error_exit "Invalid head size paramater value: $head_size"
                msg_info "using $head_size head size"
                shift 1
                ;;
            --progress|-p)
                progress=1
                ;;
            --quiet|-q)
                verbosity="$SHOW_FROM_QUIET"
                ;;
            --resume)
                resume=1
                ;;
            --reuse-db|-r)
                reuse_db=1
                ;;
            --verbose|-v)
                verbosity="$SHOW_FROM_VERBOSE"
                ;;
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
        msg_warning "(Dry run mode - no filesystem changes. Preserving database after run.)"
    fi

    sync_target
    cleanup_exit

}

msg() {

    local msg="${1:-}"
    local verbosity_level="${2:-SHOW_FROM_NORMAL}"
    local type="${3:-normal}" # error, info, warning + normal, inplace
    local max_len
    local msg_left
    local msg_right
    local color=""
    local color_reset=""
    local post_msg=""
    local flag_e="-e"
    local flag_n=""

    if [[ "$no_color" = 0 ]]; then

        case "$type" in

            "error")
                # bright red
                color="\033[1;31m"
                ;;
            "info")
                # bright green
                color="\033[1;32m"
                ;;
            "warning")
                # bright yellow
                color="\033[1;33m"
                ;;
        esac

        [[ -n "$color" ]] && color_reset="\033[0m"

    fi

    # more verbosity than target disables inplace messages
    if [[ ( "$type" = "inplace" && "$verbosity" -gt "$verbosity_level" ) ]]; then
        type="normal"
    fi

    if [ "$type" = "inplace" ]; then

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

        flag_n="-n"
        post_msg="\r"

    fi

    [[ "$verbosity" -ge "$verbosity_level" ]] && echo $flag_n $flag_e "${color}${msg}${color_reset}${post_msg}"

}

msg_error(){

    msg "$1" "${2:-$SHOW_FROM_QUIET}" "$MSG_TYPE_ERROR"

}

msg_info(){

    msg "$1" "${2:-$SHOW_FROM_COMPACT}" "$MSG_TYPE_INFO"

}

msg_inplace(){

    msg "$1" "${2:-$SHOW_FROM_COMPACT}" "$MSG_TYPE_INPLACE"

}

msg_normal(){

    msg "$1" "${2:-$SHOW_FROM_NORMAL}" "$MSG_TYPE_NORMAL"

}

msg_warning(){

    msg "$1" "${2:-$SHOW_FROM_COMPACT}" "$MSG_TYPE_WARNING"

}

rename_conflicting_target() {

    local file="$1"
    local idx=1
    local new_name
    local target="${file%.*}_[renamed_${idx}].${file##*.}"

    while [ -f  "$target" ]; do
        ((idx++))
        target="${file%.*}_[renamed_${idx}].${file##*.}"
    done

    # unique filename, now rename...
    msg_normal "Renaming existing target with different content: $file -> $target"

    # Rename and update only on success
    [[ "$dry_run" = 0 ]] && mv "$file" "$target" && update_target_path "$file" "$target"

}


show_help() {

    echo "presync version $VERSION Copyright (c) 2025 Francisco Gonzalez
MIT license

presync renames files in target folder to match existing files in source folder
based on content checksums.

Usage: ${0##*/} [OPTION]... SRC DEST

Options
--compact, -c    show less text output and use inplace progress messages
--debug, -d      dumps database of targets before / after processing
--dry-run        trial run without file changes (implies --keep-db)
--flush-db, -f   remove any existing db without asking
--help, -h       show this help
--keep-db, -k    don't delete database after running (ignores --flush-db)
--muted, -m      don't output any text
--no-color       print all messages without color
-P               same as --partial $head_size
--partial SIZE   calc checksums using at most N kilobytes from file
--progress, -p   show progress of total files
--quiet, -q      show only inplace progress messages
--resume         resume from last record in database (implies --reuse-db)
--reuse-db, -r   use an existing database of targets without asking
--verbose, -v    increase verbosity

presync does not copy or delete any files, only renames existing files in the
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

Database files are stored in /tmp/presync-[params checksum].sqlite
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
    local row
    local idx=0
    local file
    local files
    local total=0
    local progress_msg=""
    local percent=""

    # stats: total files in source, total files in dest, total renamed files
    #        total identcal files in same path, total files in source not in target
    #        total files in target not in source

    db_init

    if [[ "$reuse_db" = 0 || "$resume" = 1 ]]; then
        collect_target_hashes
        clear_line
        collect_source_hashes
    fi

    if [[ "$verbosity" -ge "$SHOW_FROM_DEBUG" ]]; then
        msg_info "\nList of collected target hashes before processing: (id, hash, path, used)"
        msg_warning "$(db_query "select * from $TABLE_TARGET;")\n"
        msg_info "\nList of collected source hashes before processing: (id, hash, path, used)"
        msg_warning "$(db_query "select * from $TABLE_SOURCE;")\n"
    fi

    clear_line

    msg "Pre-syncing..." "$SHOW_FROM_COMPACT"

    [[ "$progress" = 1 ]] && total=$(get_unique_sources_count)

    # fix verbosity crap

    while IFS=$'\x1F' read -d $'\x1E' -ra row; do

        (( idx++ ))

        file="${row[1]}"

        if [[ "$progress" = 1 ]]; then
            percent=$((idx * 100 / total))
            progress_msg="[${idx}/${total} (${percent}%)] "
        fi

        # show all files being processed from verbosity verbose and up
        if [[ "$verbosity" -gt "$SHOW_FROM_NORMAL" ]]; then
            msg_info "${progress_msg}${file}"
        fi

        hash="${row[0]}"
        target="${dst}/${row[1]}"

        existing_target="$(get_target_path "$hash")"

        # file exists in another path?
        if [[ -n "$existing_target" ]]; then

            existing_target="$dst/$existing_target"

            case "$verbosity" in
                "$SHOW_FROM_NORMAL") msg_info "${progress_msg}${file}" ;;
                "$SHOW_FROM_COMPACT") msg_inplace "${progress_msg}${file}" ;;
                "$SHOW_FROM_QUIET") [[ "$progress" = 1 ]] && msg_inplace "Collecting source hashes and processing: ${idx}/${total} (${percent}%)" "$SHOW_FROM_QUIET" ;;
            esac

            # Rename existing target with different content since we have a candidate to take its place.
            [[ -f "$target" ]] && rename_conflicting_target "$target"

            # create intermediary folders as needed
            [[ "$dry_run" = 0 ]] && [[ ! -d "${target%/*}" ]] && mkdir -p "${target%/*}"

            if [ -f "$target" ]; then
                [[ "$dry_run" = 0 ]] && msg_error "Error: target file with different content already exists! May not have permission to move conflicting file: $target"
            else
                # move existing_target to $target
                msg_normal "Moving: $existing_target -> $target"

                if [ "$dry_run" = 0 ] && mv "$existing_target" "$target"; then
                    # update database entry so we don't create orphans
                    update_target_path "$existing_target" "$target"
                else
                    # msg_error could be skipped on dry_run
                    [[ "$dry_run" = 0 ]] && msg_error "Error: cannot move file!"
                fi

            fi

        fi

    done < <(get_unique_sources)

    if [[ "$verbosity" -ge "$SHOW_FROM_DEBUG" ]]; then
        msg_info "\nList of collected target hashes after processing: (id, hash, path, used)"
        msg_warning "$(db_query "select * from target;")\n"
    fi

    clear_line
    msg "Done!" "$SHOW_FROM_COMPACT"

}

update_target_path() {

    local old_path="$1"
    local new_path="$2"
    local directory="${dst/%\//}/"
    local old_path_rel="${old_path/#$directory}"
    local new_path_rel="${new_path/#$directory}"

    db_query "UPDATE target SET path='${new_path_rel//\'/\'\'}', used=1 WHERE path='${old_path_rel//\'/\'\'}';"

}

# Trap interrupts and exit instead of continuing any loops
trap cleanup_exit SIGINT SIGTERM

main "$@"

# EOF