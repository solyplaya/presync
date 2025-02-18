#!/bin/sh

# test for normal filename scenarios

# test edge scenarios (src dst starts with dash)
# test unreadable files
# test non writable etc.
# test sqlite and non sqlite... need to mock sqlite presence or use docker to test!
# create the shell script to run the tests inside docker alpine
# see how resync handles errors with diff verbosity levels

presync="./presync_posix.sh"
src="/tmp/test_src"
dst="/tmp/test_dst"
dst_base="/tmp/test_dst_base"

. ./common_functions

# test normal, test partial, test prune, test different hashers and all other custom params

test_presync_normal() {


    $presync --muted "$src" "$dst"
    result=$(get_src_dst_diff "23")

    # only sort folder must remain after syncing this test without prune-dirs
    assertEquals "./sort" "$result"

}

test_presync_prune_dirs() {

    $presync --muted --prune-dirs "$src" "$dst"
    result=$(get_src_dst_diff "13")

    assertEquals "" "$result"

}

test_presync_partial_checksums() {


    $presync --muted --partial 1 "$src" "$dst"
    result=$(get_src_dst_diff "23")

    # only sort folder must remain after syncing this test without prune-dirs
    assertEquals "./sort" "$result"

}

test_presync_custom_tmp_and_db() {


    mkdir "/tmp/subfolder" || exit 1

    $presync --muted --tmp "/tmp/subfolder" --database "/tmp/CustomDatabaseFile" "$src" "$dst"
    result=$(get_src_dst_diff "23")

    # only sort folder must remain after syncing this test without prune-dirs
    assertEquals "./sort" "$result"

    rm -rf "/tmp/subfolder" 2>/dev/null

}

test_presync_non_writable_tmp_arg() {

    result=$($presync --tmp /root "$src" "$dst")
    assertEquals "Temp directory '/root' does not exist or is not writable!" "$result"

}

test_presync_hasher_hhx128sum() {

    $presync --muted --hasher xxh128sum "$src" "$dst"
    result=$(get_src_dst_diff "23")
    assertEquals "./sort" "$result"

}

test_presync_hasher_sha1sum() {

    $presync --muted --hasher sha1sum "$src" "$dst"
    result=$(get_src_dst_diff "23")
    assertEquals "./sort" "$result"

}

test_presync_hasher_md5sum() {

    $presync --muted --hasher md5sum "$src" "$dst"
    result=$(get_src_dst_diff "23")
    assertEquals "./sort" "$result"

}

test_presync_hasher_b3sum() {

    $presync --muted --hasher b3sum "$src" "$dst"
    result=$(get_src_dst_diff "23")
    assertEquals "./sort" "$result"

}

oneTimeSetUp() {

    rm -rf "$src" "$dst" "$dst_base" 2>/dev/null

    # generate a regular filesys structure (not really normal, since one filename has a pipe character which in exFAT or NTFS is not allowed)
    gen_structure_normal

    # have an empty folder in source and target to make sure it gets preserved
    mkdir "$src/future" "$dst_base/future"

}

oneTimeTearDown() {

    rm -rf "$src" "$dst_base"
}

setUp() {

    cp -pr "$dst_base" "$dst"

}

tearDown() {

    rm -rf "$dst"
}

# shellcheck disable=SC2034
SHUNIT_PARENT="$0"

# shellcheck disable=SC1091
. shunit2

# EOF