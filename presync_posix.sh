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

VERSION="1.5"
TARGET_USED="1"
TARGET_CONFLICT="0"
src=""
dst=""
src_slash=""
dst_slash=""
db=""
t_src=""
t_dst=""
t_dr=""
hasher=""
head_size=0
muted=0
prune_dirs=0
resume=""
dry_run=""
tmp="/tmp"
nl_placeholder="<<_NEW_LINE_>>"
global_string=""
last_file=""

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

    if [ -z "$dry_run" ]; then
        [ -f "$db" ] && rm "$db" 2>/dev/null
        [ -f "$t_src" ] && rm "$t_src" 2>/dev/null
        [ -f "$t_dst" ] && rm "$t_dst" 2>/dev/null
        [ -f "$t_src.s" ] && rm "$t_src.s" 2>/dev/null
        [ -f "$t_dst.s" ] && rm "$t_dst.s" 2>/dev/null
        [ -f "$t_dr" ] && rm "$t_dr" 2>/dev/null
        [ -f "$t_dr.last_file" ] && rm "$t_dr.last_file" 2>/dev/null
        [ -f "$t_dr.source" ] && rm "$t_dr.source" 2>/dev/null
        [ -f "$t_dr.target" ] && rm "$t_dr.target" 2>/dev/null
    elif [ -n "$last_file" ]; then
        # store the last_file if not empty (and was dry-run)
        printf '%s\n' "$last_file" > "$t_dr.last_file" 2>/dev/null
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

    # uses global variables: table, directory, resume_file

    for item in "$1"/* "$1"/.*; do

        # prevent messy follow-ups of a symlink, current or parent directory
        [ "${item##*/}" = "." ] || [ "${item##*/}" = ".." ] || [ -h "$item" ] && continue

        if [ -d "$item" ]; then
                collect_hashes "$item"
        else

            if [ -f "$item" ]; then

                if [ -n "$resume_file" ]; then
                    if [ "$resume_file" = "$item" ]; then
                        resume_file=""
                    fi
                    continue
                fi

                hash=$(get_hash_from_file "$item")

                if [ -n "$hash" ]; then

                    file_rel="${item#"$directory"}"

                    if has_newline "$file_rel"; then
                        file_rel=$(escape_nl "$file_rel")
                    fi

                    if [ -n "$db" ]; then
                        printf '%s\n' "('$(escape_single_quotes "$hash")','$(escape_single_quotes "$file_rel")')," >> "$tmp/presync.$table" || error_exit_fs
                    else
                        printf '%s\n' "$hash|$file_rel" >> "$tmp/presync.$table" || error_exit_fs
                    fi

                    is_dry_run && last_file="$file_rel"

                else
                    msg "Error: cannot generate checksum for file: $item"
                fi

            fi
        fi
    done

}

db_init() {

    if [ -z "$resume" ]; then
        [ -f "$t_src" ] && rm "$t_src"
        [ -f "$t_dst" ] && rm "$t_dst"
        [ -f "$t_dr" ] && rm "$t_dr"
    fi

    [ -z "$db" ] && return

    if [ -f "$db" ]; then
        [ -n "$resume" ] && return
        rm "$db"
    else
        resume=""
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

    sqlite3 "$db" "$1" || error_exit "sqlite3 database query error!: $1"

}

dry_run_prepare() {

    if [ -n "$dry_run" ]; then

        msg "Dry run mode: no filesystem changes."
        msg "Use --resume in the next run to reuse the database."

        if [ -n "$db" ]; then
            cp "$db" "$t_dr" || error_exit_fs
            db="$t_dr"
        else
            cp "$t_dst" "$t_dr" || error_exit_fs
            t_dst="$t_dr"
        fi

    else
        [ -f "$t_dr" ] && rm "$t_dr"
    fi

}

error_exit() {

    msg "$1"
    cleanup_exit

}

error_exit_fs() {

    error_exit "Error creating temp file!"

}

escape_nl() {

    escape_string "$1" "$_LF" "$nl_placeholder"

}

escape_single_quotes() {

    if has_string "$1" "'"; then
        escape_string "$1" "'" "''"
    else
        printf '%s' "$1"
    fi

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

get_hash_from_plaintext() {

    _search="$1"
    has_newline "$_search" && _search=$(escape_nl "$_search")

    grep -F "|$_search" "$t_dst" | while IFS= read -r line; do
        if [ "${line#*|}" = "$_search" ]; then
            printf '%s' "${line%%|*}"
            break
        fi
    done

}

get_last_line() {

    [ -f "$1" ] && tail -n 1 "$1"

}

get_target_path() {

    if [ -n "$db" ]; then
        db_query "SELECT path FROM target WHERE hash = '$(escape_single_quotes "$1")' AND used = 0 LIMIT 1;"
    else
        _path=$(grep -m 1 "^$1|" "$t_dst")
        printf '%s' "${_path#*|}"
    fi

}

get_unique_sources(){

    if [ -z "$resume" ]; then

        if [ -n "$db" ]; then

            sort "$t_src" > "$t_src.s" \
                && sort "$t_dst" > "$t_dst.s" \
                && comm -23 "$t_src.s" "$t_dst.s" > "$t_src" \
                && comm -13 "$t_src.s" "$t_dst.s" > "$t_dst" \
                && rm "$t_src.s" "$t_dst.s" \
                || error_exit_fs

                {
                    printf '%s\n' "INSERT INTO source (hash, path) VALUES"
                    head -n -1 "$t_src"
                    last_line=$(tail -n 1 "$t_src")
                    last_line="${last_line%,};"
                    printf '%s\n' "$last_line"
                } > "$t_src.s" || error_exit_fs

                {
                    printf '%s\n' "INSERT INTO target (hash, path) VALUES"
                    head -n -1 "$t_dst"
                    last_line=$(tail -n 1 "$t_dst")
                    last_line="${last_line%,};"
                    printf '%s\n' "$last_line"
                } > "$t_dst.s" || error_exit_fs

                # this may hit the maximum number of arguments of shell, should divide in batches ok a few Ks...
                sqlite3 "$db" < "$t_src.s" || error_exit "sqlite3 database batch insert error!"
                sqlite3 "$db" < "$t_dst.s" || error_exit "sqlite3 database batch insert error!"
                rm "$t_src.s" "$t_dst.s"
                db_query "SELECT hash, path FROM source ORDER BY id;" > "$t_src" || error_exit_fs
        else
            sort "$t_src" > "$t_src.s" \
                && sort "$t_dst" > "$t_dst.s" \
                && comm -23 "$t_src.s" "$t_dst.s" > "$t_src" \
                && comm -13 "$t_src.s" "$t_dst.s" > "$t_dst" \
                && rm "$t_src.s" "$t_dst.s" \
                || error_exit_fs
        fi
    elif [ -n "$db" ]; then
            # Here records are already unique and sorted since we import via transaction from plaintext file
            db_query "SELECT hash, path FROM source ORDER BY id;" > "$t_src" || error_exit_fs
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

has_string() {

    case "$1" in
        *"$2"*) return 0;;
        *) return 1;;
    esac

}

is_dry_run() {

    [ -n "$dry_run" ]

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
            --dry-run)
                dry_run=1
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
                if [ -z "$head_size" ] || ! [ "$head_size" -eq "$head_size" ] 2>/dev/null || [ "$head_size" -le 0 ]; then
                    error_exit "Invalid head size parameter value: $head_size"
                fi
                shift
                ;;
            --prune-dirs)
                prune_dirs=1
                ;;
            --resume|r)
                resume=1
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

    # strip trailing slashes from path without using a function to preserve a possible trailing newline
    if [ "$src" != "/" ] && [ "$src" != "./" ]; then
        while [ "${src#"${src%?}"}" = "/" ]; do src="${src%/}"; done
    fi

    if [ "$dst" != "/" ] && [ "$dst" != "./" ]; then
        while [ "${dst#"${dst%?}"}" = "/" ]; do dst="${dst%/}"; done
    fi

    if [ "$tmp" != "/" ] && [ "$tmp" != "./" ]; then
        while [ "${tmp#"${tmp%?}"}" = "/" ]; do tmp="${tmp%/}"; done
    fi

    # if src and dst are the same, do nothing!
    if [ "$src" = "$dst" ]; then
        error_exit "Source and destination arguments are the same!"
    fi

    src_slash="${src%/}/"
    dst_slash="${dst%/}/"

    # even in db mode we use at least t_src to loop without a subshell
    t_src="$tmp/presync.source"
    t_dst="$tmp/presync.target"
    t_dr="$tmp/presync.dry-run"

    # disable resume if we have not collected any hashes
    if [ -n "$resume" ]; then
        [ ! -f "$t_src" ] && [ ! -f "$t_dst" ] && resume=""
    fi

    for cmd in comm grep head sort tail; do
        ! (have_command "$cmd") && error_exit "Error: presync requires $cmd command to run."
    done

    if ! have_command "sqlite3"; then

        msg "Notice: command sqlite3 not found! Using plain text mode."

    else

        if [ -n "$_custom_db" ]; then
            db="$_custom_db"
        else
            db="$tmp/presync.sqlite3"
        fi

        # prevent interpretation of paths as arguments
        [ "${db#/}" = "$db" ] && [ "${db#./}" = "$db" ] && db="./$db"


        if [ ! -f "$db" ]; then
            resume=""
            printf '' > "$db" 2>/dev/null
        fi

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


        if is_dry_run; then
            # check existence of file only in our database
            target_exists_in_db "$__dir" && rename_conflicting_target "$__dir"
        else

            # path exists as a regular file or symlink, try to rename
            if [ -f "$__dir" ] || [ -h "$__dir" ]; then
                rename_conflicting_target "$__dir"
            fi

            if [ ! -e "$__dir" ]; then
                mkdir "$__dir" || return
            fi

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
    _idx=1
    _target="${_file%/*}/[renamed_${_idx}]-${_file##*/}"
    _hash=""

    while [ -f  "$_target" ]; do
        _idx=$((_idx+1))
        _target="${_file%/*}/[renamed_${_idx}]-${_file##*/}"
    done

    msg "Solving conflict:"
    msg "  $_file"
    msg "  $_target"

    if ! is_dry_run; then
        mv "$_file" "$_target" || return
    fi

    # only update target path if moved file was a regular file and not a symlink
    # in dry-run mode we don't move the file, so have to check on the filename before moving
    if is_dry_run && [ -f "$_file" ] || [ -f "$_target" ]; then

        if [ -z "$db" ]; then
            _file_rel="${_file#"$dst_slash"}"
            _hash=$(get_hash_from_plaintext "$_file_rel")
        fi

        # hash is only required in plain text mode
        update_target_path "$_file" "$_target" "$_hash" "$TARGET_CONFLICT"

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

set_resume_file() {

    # uses global variables table, last_file

    if [ -z "$resume" ] || [ -f "$t_dr.$table" ]; then
        return
    fi

    _path=""

    if [ -n "$db" ]; then

        if [ -f "$t_dr.last_file" ]; then
            while IFS= read -r line; do
                _path="$line"
            done < "$t_dr.last_file"
        fi

    else
        if [ "$table" = "source" ]; then
            _path=$(get_last_line "$t_src")
        else
            _path=$(get_last_line "$t_dst")
        fi
        _path="${_path#*|}"
    fi

    if [ -n "$_path" ]; then
        if has_placeholders "$_path"; then
            replace_nl_placeholders "$_path"
            _path="$global_string"
        fi

        if [ "$table" = "source" ]; then
            resume_file="$src_slash$_path"
        else
            resume_file="$dst_slash$_path"
        fi

    fi

}

show_help() {

    printf '%s' "presync.sh (posix) version $VERSION Copyright (c) 2025 Francisco Gonzalez
MIT license

presync renames files in target folder to match existing files in source folder
based on content checksums.

Usage: ${0##*/} [OPTION]... SRC DEST

Options
--database FILE  write the database to the specified FILE
--dry-run        trial run without file changes
--hasher CMD     use the given CMD to process file checksums
--help, -h       show this help
--muted, -m      don't output any text
--partial SIZE   calc checksums using at most N kilobytes from file
--prune-dirs     delete empty diretories left in target after processing
--resume         resume from a previous --dry-run invocation
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

Database files are stored in /tmp/presync.sqlite and deleted after every run
unless --dry-run option is provided. If --resume is provided in the next run
no hash collection will be performed unless it was interrupted by the user, in
which case collection will resume from the last file in the database. Please
note that --dry-run simulation does not handle symlink collisions whereas a
normal run does.

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
    resume_file=""

    # sqlite3 or plaintext
    db_init

    # collect source hashes
    table="source"
    if [ -z "$resume" ] || [ ! -f "$t_dr.$table" ]; then
        directory="$src_slash"
        set_resume_file
        msg "Collecting $table hashes..."
        collect_hashes "$src"
        last_file=""
        is_dry_run && printf '' > "$t_dr.$table"
    fi

    # collect target hashes
    table="target"
    if [ -z "$resume" ] || [ ! -f "$t_dr.$table" ]; then
        directory="$dst_slash"
        set_resume_file
        msg "Collecting $table hashes..."
        collect_hashes "$dst"
        last_file=""
        is_dry_run && printf '' > "$t_dr.$table"
    fi

    msg "presync-ing..."

    get_unique_sources
    dry_run_prepare

    while IFS= read -r row; do

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

            # here lies the key to correct dry-run
            if is_dry_run; then
                # check existence of file only in our database
                target_exists_in_db "$target" && rename_conflicting_target "$target"
            else
                # Rename existing target with different content since we have a candidate to take its place.
                # this may be an entry not in the database, like a symlink in our way
                [ -f "$target" ] && rename_conflicting_target "$target"
            fi

            # Create intermediary folders as needed
            if [ ! -d "${target%/*}" ]; then

                # Is the dir to be created an already existing file or contains an existing file in its path?
                # if so, need to rename in order to accomodate the new file path. We only rename regular files and symlinks.
                make_path "$dst" "$file"

                if ! is_dry_run; then

                    if [ ! -d "${target%/*}" ]; then
                        msg "Cannot create target path: ${target%/*}"
                        continue
                    fi
                fi

            fi

            if ! is_dry_run && [ -f "$target" ]; then
                msg  "Error: cannot rename conflicting target: $target"
            else
                msg "${existing_target#./}"
                msg "${target#./}"

                if is_dry_run; then
                    update_target_path "$existing_target" "$target" "$hash" "$TARGET_USED"
                else
                    if mv "$existing_target" "$target"; then
                        update_target_path "$existing_target" "$target" "$hash" "$TARGET_USED"
                    else
                        msg "Error: cannot move file!"
                    fi
                fi
            fi

        fi

    done < "$t_src"

    # prune_dirs simulation adds some complextity to dry_run, so not for now.
    ! is_dry_run && prune_dirs
    cleanup

    msg; msg "Done!"

}

target_exists_in_db() {

    # paths come with nl unescapped

    # make path relative
    search_path="${1#"$dst_slash"}"

    if [ -n "$db" ]; then
        has_newline "$search_path" && search_path=$(escape_nl "$search_path")
        found_hash=$(db_query "SELECT hash FROM target WHERE path = '$(escape_single_quotes "$search_path")' LIMIT 1;")
    else
        # get_hash_from_plaintext takes care of escaping nl chars
        found_hash=$(get_hash_from_plaintext "$search_path")
    fi

    [ -n "$found_hash" ]

}

update_target_path() {

    # paths come here with nl unescapped if any
    old_path="$1"
    new_path="$2"
    __hash="$3"
    maybe_used=""
    [ "${4:-0}" -eq 1 ] && maybe_used=", used=1"
    old_path_rel="${old_path#"$dst_slash"}"
    new_path_rel="${new_path#"$dst_slash"}"

    has_newline "$old_path_rel" && old_path_rel=$(escape_nl "$old_path_rel")
    has_newline "$new_path_rel" && new_path_rel=$(escape_nl "$new_path_rel")

    if [ -n "$db" ]; then
        db_query "UPDATE target SET path='$(escape_single_quotes "$new_path_rel")' $maybe_used WHERE path='$(escape_single_quotes "$old_path_rel")';"
    else

        if [ -z "$maybe_used" ]; then
            # update path of existing file with different content
            update_entry_plaintext "$__hash|$old_path_rel" "$__hash|$new_path_rel"
        else
            # delete the line has same effect as updating path and used state for now
            update_entry_plaintext "$__hash|$old_path_rel"
        fi

    fi

}

update_entry_plaintext() {

    # if arg 2 is empty, just delete the line matching arg 1
    # use intermediate temp file for text editing

    if [ -n "${2:-}" ]; then
        grep -v -x -F "$1" "$t_dst" > "$t_dst.tmp"
        printf '%s\n' "$2" >> "$t_dst.tmp"
        mv "$t_dst.tmp" "$t_dst" || error_exit_fs
    else
        grep -v -x -F "$1" "$t_dst" > "$t_dst.tmp"
        mv "$t_dst.tmp" "$t_dst" || error_exit_fs
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