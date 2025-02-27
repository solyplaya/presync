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

set -o nounset

VERSION="1.3"
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
nl_placeholder="<<_NEW_LINE_>>"
global_string=""

# special characters for message printing filter
_SUB=$(printf "\032")  # SUB character (ASCII 26) - as a visual substitute for unprintable chars
_BELL=$(printf "\007") # Bell character (ASCII 7)
_BS=$(printf "\010")   # BackSpace (ASCII 8)
_ESC=$(printf "\033")  # Escape character (ASCII 27)
_FF=$(printf "\014")   # Form Feed (ASCII 12)
_CR=$(printf "\015")   # Carriage Return (ASCII 13)
_HT=$(printf "\011")   # Horizontal Tab (ASCII 9)
_VT=$(printf "\013")   # Vertical Tab (ASCII 11)
_LF=$(printf "\012#")  # Line Feed (ASCII 10)
_LF="${_LF%#}"         # $(...) removes trailing newlines, so use an extra char to keep it and remove it afterwards

cleanup() {

    if [ -n "$db" ]; then
        rm "$db"
    else
        rm "$tmp/presync.source" "$tmp/presync.target"
    fi
}

cleanup_exit() {

    cleanup
    exit 1

}

collect_hashes() {

    # posix compliant recursive file loop using path expansion
    # does not create a subshell and handles filenames with newline characters
    # deals only with files (ignores symlinks)

    # uses global variables: table, directory

    for item in "$1"/* "$1"/.*; do

        # prevent messy follow-ups of a symlink, current or parent directory
        [ "${item##*/}" = "." ] || [ "${item##*/}" = ".." ] || [ -h "$item" ] && continue

        if [ -d "$item" ]; then
                collect_hashes "$item"
        else

            if [ -f "$item" ]; then

                hash=$(get_hash_from_file "$item")

                if [ -n "$hash" ]; then

                    file_rel="${item#"$directory"}"

                    if has_newline "$file_rel"; then
                        file_rel=$(escape_nl "$file_rel")
                    fi

                    if [ -n "$db" ]; then
                        db_query "INSERT OR REPLACE INTO $table (hash, path) VALUES ('$(escape_single_quotes "$hash")', '$(escape_single_quotes "$file_rel")');"
                    else
                        printf '%s\n' "$hash|$file_rel" >> "$tmp/presync.$table"
                    fi

                else
                    msg "Error: cannot generate checksum for file: $item"
                fi

            fi
        fi
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

    printf '%s' "$1" | sqlite3 "$db" || error_exit "sqlite3 database query error!: $1"

}

error_exit() {

    msg "$1"
    exit 1

}

escape_backslashes() {

    escape_string "$1" "\\" "\\\\"

}

escape_forwardslashes() {

    escape_string "$1" "/" "\\/"

}

escape_nl() {

    escape_string "$1" "$_LF" "$nl_placeholder"

}

escape_single_quotes() {

    escape_string "$1" "'" "''"

}

escape_string() {

    input="$1"
    _char="$2"
    _replace="$3"
    output=""

    while [ -n "$input" ]; do
        char="${input%"${input#?}"}"
        rest="${input#?}"

        if [ "$char" = "$_char" ]; then
            output="${output}${_replace}"
        else
            output="${output}${char}"
        fi

        input="$rest"
    done

    printf '%s' "$output"

}

get_hash_from_file() {

    # obtains the hash from a given file dealing properly with filenames with newline characters
    # that generate different outputs dependinng on the hasher used

    file="$1"
    hash=""

    if [ -r "$file" ]; then

        if [ "$head_size" -gt 0 ]; then
            hash=$(head -c "${head_size}"k "$file" | $hasher 2>/dev/null)
        else
            if has_newline "$file"; then
                hash=$($hasher -- "$file" 2>/dev/null | head -n 1)
            else
                hash=$($hasher -- "$file" 2>/dev/null)
            fi
        fi

    fi

    if [ -n "$hash" ]; then

        # remove leading backslash produced by sha1sum and md5sum if input filename has newline characters
        hash="${hash#\\}"

        # get only the hash and leave out the filename part
        hash="${hash%% *}"

        # do not use garbage data as a hash
        ! valid_hex "$hash" && hash=""

    fi

    printf '%s' "$hash"

}

get_target_path() {

    if [ -n "$db" ]; then
        db_query "SELECT path FROM target WHERE hash = '$(escape_single_quotes "$1")' AND used = 0 LIMIT 1;"
    else
        _path=$(grep -m 1 "^$1" "$tmp/presync.target")
        printf '%s' "${_path#*|}"
    fi

}

get_unique_sources(){

    if [ -n "$db" ]; then
        db_query "SELECT s.hash, s.path FROM source s LEFT JOIN target t ON s.hash = t.hash AND s.path = t.path WHERE t.id IS NULL;"
    else
        sort "$tmp/presync.source" > "$tmp/presync.source.sorted"
        sort "$tmp/presync.target" > "$tmp/presync.target.sorted"
        comm -23 "$tmp/presync.source.sorted" "$tmp/presync.target.sorted" > "$tmp/presync.source"
        comm -13 "$tmp/presync.source.sorted" "$tmp/presync.target.sorted" > "$tmp/presync.target"
        rm "$tmp/presync.source.sorted" "$tmp/presync.target.sorted"

        cat "$tmp/presync.source"
    fi

}

have_command(){

    command -v "$1" > /dev/null

}

has_newline() {

    case "$1" in
        *"$_LF"*) return 0;;
        *) return 1;;
    esac

}

has_placeholders() {

    case "$1" in
        *"$nl_placeholder"*) return 0;;
        *) return 1;;
    esac

}

main() {

    _custom_db=""

    [ -z "${1:-}" ] && show_help

    while [ $# -gt 0 ] ; do
        case "$1" in

            --database)
                _custom_db="${2:-}"
                shift
                ;;
            --tmp)
                tmp="${2:-}"
                # trim trailing forward slash
                [ -n "$tmp" ] && tmp="${tmp%/}"
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
                if [ -z "$head_size" ] || ! [ "$head_size" -eq "$head_size" ] 2>/dev/null || [ "$head_size" -le 0 ]; then
                    error_exit "Invalid head size parameter value: $head_size"
                fi
                shift
                ;;
            --prune-dirs)
                prune_dirs=1
                ;;
            --)
                shift
                break
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

    # plain text mode needs write permission to tmp dir, and further features will need a writable tmp dir
    if ! [ -d "$tmp" ] || ! [ -w "$tmp" ] ; then
        error_exit "Temp directory '$tmp' does not exist or is not writable!"
    fi

    # prevent interpretation of paths as arguments
    [ "${src#/}" = "$src" ] && [ "${src#./}" = "$src" ] && src="./$src"
    [ "${dst#/}" = "$dst" ] && [ "${dst#./}" = "$dst" ] && dst="./$dst"
    [ "${tmp#/}" = "$tmp" ] && [ "${tmp#./}" = "$tmp" ] && tmp="./$tmp"

    if ! (have_command "sqlite3"); then

        for cmd in comm cat grep sort; do
            ! (have_command "$cmd") && error_exit "Error: presync requires $cmd command to run in plaintext mode."
        done

        [ -f "$tmp/presync.source" ] && rm "$tmp/presync.source" 2>/dev/null
        [ -f "$tmp/presync.target" ] && rm "$tmp/presync.target" 2>/dev/null

        msg "Notice: command sqlite3 not found - using slower plain text mode"

    else

        if [ -n "$_custom_db" ]; then
            db="$_custom_db"
        else
            db="$tmp/presync.sqlite3"
        fi

        # prevent interpretation of paths as arguments
        [ "${db#/}" = "$db" ] && [ "${db#./}" = "$db" ] && db="./$db"

        touch "$db" 2>/dev/null

        if [ ! -w "$db" ]; then
            error_exit "Cannot write database file: $db"
        fi

    fi

    # try to find an available hasher
    if [ -z "$hasher" ]; then

        for cmd in xxh128sum b3sum sha1sum md5sum md5; do
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

make_path() {

    # function to iterate each subfolder to be created in a path dealing with conflicting files

    # this is the base dir to build upon
    __dir="$1"

    # remove the last part.. aka the file so we have now only a sub dir path
    __file="${2%/*}"

    # argument does not have any sub folders
    [ "$2" = "$__file" ] && return

    while [ -n "$__file" ]; do

        __dir="$__dir/${__file%%/*}"

        # path exists as a regular file or symlink, try to rename
        if [ -f "$__dir" ] || [ -h "$__dir" ]; then
            rename_conflicting_target "$__dir"
        fi

        if [ ! -e "$__dir" ]; then
            mkdir "$__dir" || return
        fi
        if [ "$__file" = "${__file#*/}" ]; then
            __file=""
        else
            __file="${__file#*/}"
        fi

    done

}

msg() {

    [ "$muted" != "0" ] && return

    input="${1:-}"
    output=""

    while [ -n "$input" ]; do

        char="${input%"${input#?}"}"
        rest="${input#?}"

        case "$char" in
            "$_BELL" | "$_BS" | "$_ESC" | "$_FF" | "$_CR" | "$_HT" | "$_VT" | "$_LF") output="${output}$_SUB" ;;
            *) output="${output}${char}" ;;
        esac

        input="$rest"

    done

    printf '%s\n' "$output"

}

prune_dirs() {

    # only prune dirs if dst is not empty
    if [ "$prune_dirs" -eq 1 ] && [ -n "$(ls -A "$dst")" ]; then
        msg; msg "Deleting empty dirs in target..."
        prune_empty_dirs "$dst"
    fi

}

prune_empty_dirs() {

    # uses src dst globals

    # loop only directories including hidden ones
    for dir in "$1"/*/ "$1"/.*/; do

        # remove trailing slash
        dir="${dir%/*}"

        # prevent messy follow-ups of symlink, current dir, parent dir or the pattern itself
        [ "${dir##*/}" = "." ] || [ "${dir##*/}" = ".." ] || [ -h "$dir" ] || ! [ -d "$dir" ] && continue

        if [ -d "$dir" ] && [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then

            # only delete the empty dir if it does not exist in source
            if [ ! -d "${src}${dir#"$dst"}" ]; then
                rmdir "$dir" 2>/dev/null && prune_parents "$dir"
            fi
        else
            prune_empty_dirs "$dir"
        fi

    done

}

prune_parents() {

    path="$1"
    dir="${path%/*}";

    # if dir does not exist in source, is not the root of dst or the last piece...
    if [ ! -d "${src}${dir#"$dst"}" ] && [ "$dst" != "$dir" ] && [ "$path" != "$dir" ]; then
        rmdir "$dir" 2>/dev/null && prune_parents "$dir"
    fi

}

rename_conflicting_target() {

    _file="$1"
    _dir="${dst%/}/"
    _idx=1
    _target="${_file%/*}/[renamed_${_idx}]-${_file##*/}"
    _hash=""

    while [ -f  "$_target" ]; do
        _idx=$((_idx+1))
        _target="${_file%/*}/[renamed_${_idx}]-${_file##*/}"
    done

    if mv "$_file" "$_target"; then

        # only update target path if moved file was a regular file and not a symlink
        if [ -f "$_target" ]; then

            if [ -z "$db" ]; then
                _file_rel="${_file#"$_dir"}"
                has_newline "$_file_rel" && _file_rel=$(escape_nl "$_file_rel")
                _hash=$(grep -m 1 -F -- "$_file_rel" "$tmp/presync.target")
                _hash="${_hash%%|*}"
            fi

            # hash is only required in plain text mode
            update_target_path "$_file" "$_target" "$_hash" "$TARGET_CONFLICT"

        fi

    fi

}

replace_global_string() {

    # posix compliant search and relace using parameter expansion
    # works only on global_string to preserve trailing newline characters

    string="$global_string"
    search="$1"
    replace="$2"
    output=""

    while [ -n "$string" ]; do

        if [ "${string#"$search"}" != "$string" ]; then
            output="${output}$replace"
            string="${string#"$search"}"
        else
            output="${output}${string%"${string#?}"}"
            string="${string#?}"
        fi

    done

    global_string="$output"

}

replace_nl_placeholders() {

    global_string="$1"
    replace_global_string "$nl_placeholder" "$_LF"

}

show_help() {

    printf '%s' "presync.sh (posix) version $VERSION Copyright (c) 2025 Francisco Gonzalez
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

On conflicts existing files get renamed to [renamed_1]-filename

Using the --partial argument you can speed up the synchronization process since
only a smaller amount of data from the beginning of each file is used to calc
its checksum. This could lead to some false file matchings in the event that
various files share the same header data. Since no files are deleted or
overwritten, any incorrectly reorganized files will get resolved by rsync.

Database files are stored in /tmp/presync.sqlite and deleted after every run.
You can specify a custom database file and also a custom temporary directory in
case /tmp is not a writable path in your system.

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

    # sqlite3 or plaintext
    db_init

    # collect target hashes
    table="target"
    directory="${dst%/}/"
    collect_hashes "$dst"

    # collect source hashes
    table="source"
    directory="${src%/}/"
    collect_hashes "$src"

    msg "presync-ing..."

    get_unique_sources | while IFS= read -r row; do

        # This handles filenames with pipe character because the filename column is the last from the query
        file="${row#*|}"
        hash="${row%%|*}"

        existing_target="$(get_target_path "$hash")"

        if [ -n "$existing_target" ]; then

            idx=$((idx+1))

            if has_placeholders "$existing_target"; then
                replace_nl_placeholders "$existing_target"
                existing_target="$global_string"
            fi

            if has_placeholders "$file"; then
                replace_nl_placeholders "$file"
                file="$global_string"
            fi

            # build target, with any nl chars translated back
            target="$dst/$file"
            existing_target="$dst/$existing_target"

            msg; msg "[$idx] ${src#./}/$file"

            # Rename existing target with different content since we have a candidate to take its place.
            [ -f "$target" ] && rename_conflicting_target "$target"

            # Create intermediary folders as needed
            # [ ! -d "${target%/*}" ] && mkdir -p "${target%/*}"

            if [ ! -d "${target%/*}" ]; then

                # Is the dir to be created an already existing file or contains an existing file in its path?
                # if so, need to rename in order to accomodate the new file path. We only rename regular files and symlinks.
                make_path "$dst" "$file"

                if [ ! -d "${target%/*}" ]; then
                    msg "Cannot create target path: ${target%/*}"
                    continue
                fi

            fi


            if [ -f "$target" ]; then
                msg  "Error: cannot rename conflicting target: $target"
            else
                msg "${existing_target#./}"
                msg "${target#./}"

                if mv "$existing_target" "$target"; then
                    update_target_path "$existing_target" "$target" "$hash" "$TARGET_USED"
                else
                    msg "Error: cannot move file!"
                fi

            fi

        fi

    done

    cleanup
    prune_dirs
    msg; msg "Done!"

}

update_target_path() {

    # paths come here with nl unescapped if any
    old_path="$1"
    new_path="$2"
    hash="$3"
    maybe_used=""
    [ "${4:-0}" -eq 1 ] && maybe_used=", used=1"
    directory="${dst%/}/"
    old_path_rel="${old_path#"$directory"}"
    new_path_rel="${new_path#"$directory"}"

    has_newline "$old_path_rel" && old_path_rel=$(escape_nl "$old_path_rel")
    has_newline "$new_path_rel" && new_path_rel=$(escape_nl "$new_path_rel")

    if [ -n "$db" ]; then
        db_query "UPDATE target SET path='$(escape_single_quotes "$new_path_rel")' $maybe_used WHERE path='$(escape_single_quotes "$old_path_rel")';"
    else

        # use intermediate temp file for text editing
        if [ -z "$maybe_used" ]; then
            # update path of existing file with different content
            grep -v -F "$hash|$old_path_rel" "$tmp/presync.target" > "$tmp/presync.target.tmp"
            printf '%s\n' "$hash|$new_path_rel" >> "$tmp/presync.target.tmp"
            mv "$tmp/presync.target.tmp" "$tmp/presync.target"

        else
            # delete the line has same effect as updating path and used state for now
            grep -v -F "$hash|$old_path_rel" "$tmp/presync.target" > "$tmp/presync.target.tmp"
            mv "$tmp/presync.target.tmp" "$tmp/presync.target"

        fi

    fi

}

valid_hex() {

    # check if we got a valid hex string a-f0-9 without regex

    str="$1"

    [ -z "$str" ] && return 1

    while [ -n "$str" ]; do
        char="${str%"${str#?}"}"
        str="${str#?}"

        case "$char" in [!a-f0-9]) return 1 ;; esac
    done

    return 0

}

trap cleanup_exit INT TERM

main "$@"

# EOF