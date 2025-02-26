#!/bin/sh

presync="./presync_posix.sh"
test_type="${1:-}"

src="--test_src"
dst="--test_dst"
dst_base="test_dst_base"
custom_tmp=""
custom_db=""

. ./common_functions

test_presync_normal() {

    $presync --muted -- "$src" "$dst"
    result=$(get_src_dst_diff "23")

    # only sort folder must remain after syncing this test without prune-dirs
    assertEquals "./sort" "$result"

}

test_presync_prune_dirs() {

    $presync --muted --prune-dirs -- "$src" "$dst"
    result=$(get_src_dst_diff "13")

    assertEquals "" "$result"

}

test_presync_partial_checksums() {

    $presync --muted --partial 1 -- "$src" "$dst"
    result=$(get_src_dst_diff "23")

    # only sort folder must remain after syncing this test without prune-dirs
    assertEquals "./sort" "$result"

}

test_presync_custom_tmp_and_db() {

    mkdir -- "$custom_tmp" || exit 1

    $presync --muted --tmp "$custom_tmp" --database "$custom_db" -- "$src" "$dst"
    result=$(get_src_dst_diff "23")

    # only sort folder must remain after syncing this test without prune-dirs
    assertEquals "./sort" "$result"

    rm -rf -- "$custom_tmp" 2>/dev/null

}

test_presync_non_writable_tmp_arg() {

    result=$($presync --tmp /root -- "$src" "$dst")
    assertEquals "Temp directory '/root' does not exist or is not writable!" "$result"

}

test_presync_hasher_hhx128sum() {

    $presync --muted --hasher xxh128sum -- "$src" "$dst"
    result=$(get_src_dst_diff "23")
    assertEquals "./sort" "$result"

}

test_presync_hasher_sha1sum() {

    $presync --muted --hasher sha1sum -- "$src" "$dst"
    result=$(get_src_dst_diff "23")
    assertEquals "./sort" "$result"

}

test_presync_hasher_md5sum() {

    $presync --muted --hasher md5sum -- "$src" "$dst"
    result=$(get_src_dst_diff "23")
    assertEquals "./sort" "$result"

}

test_presync_hasher_b3sum() {

    $presync --muted --hasher b3sum -- "$src" "$dst"
    result=$(get_src_dst_diff "23")
    assertEquals "./sort" "$result"

}

oneTimeSetUp() {


    case "$test_type" in

        "special_chars")

            # shellcheck disable=SC1003
            src=$(printf -- '--$`!*@__ SRC __\a\b\E\f\r\t\v\\\''"\360\240\202\211 \nx')
            src="${src%x}"

            # shellcheck disable=SC1003
            dst=$(printf -- '--$`!*@__ DST __\a\b\E\f\r\t\v\\\''"\360\240\202\211 \nx')
            dst="${dst%x}"

            # shellcheck disable=SC1003
            custom_tmp=$(printf -- '--$`!*@__ TMP __\a\b\E\f\r\t\v\\\''"\360\240\202\211 \nx')
            custom_tmp="${custom_tmp%x}"

            # shellcheck disable=SC1003
            custom_db=$(printf -- '--$`!*@__ DB_FILE __\a\b\E\f\r\t\v\\\''"\360\240\202\211 \nx')
            custom_db="${custom_db%x}"

            dst_base="test_dst_base"

            rm -rf -- "$src" "$dst" "$dst_base" 2>/dev/null

            # generate a filesystem with messed up character, non printable, new lines, dashes, etc.
            gen_structure_special
            ;;

        "normal"|*) # added the "normal" case just as a clarification, it would match anyway

            src="/tmp/test_src"
            dst="/tmp/test_dst"
            dst_base="/tmp/test_dst_base"
            custom_tmp="/tmp/custom_tmp"
            custom_db="$custom_tmp/CustomDatabaseFile"

            rm -rf -- "$src" "$dst" "$dst_base" 2>/dev/null

            # generate a regular filesys structure (not really normal, since one filename has a pipe character which in exFAT or NTFS is not allowed)
            gen_structure_normal
            ;;
    esac

    # have an empty folder in source and target to make sure it gets preserved
    mkdir -- "$src/future" "$dst_base/future"

}

oneTimeTearDown() {

    rm -rf -- "$src" "$dst_base" "$custom_tmp" "$custom_db"
}

setUp() {

    cp -pr -- "$dst_base" "$dst"

}

tearDown() {

    rm -rf -- "$dst"
}

# shellcheck disable=SC2034
SHUNIT_PARENT="$0"

# Eat all command-line arguments before calling shunit2.
shift $#

# shellcheck disable=SC1091
. shunit2

# EOF