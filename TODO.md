# Tasks

### TODO

- [ ] wite test files for unreadable files / unreadable folders
- [ ] wite test files for `--dry-run` and `--resume`
- [ ] check proper exit code handling in `--muted` mode
- [ ] test filesystem exFat / NTFS to use intermediary filename renames with changing only letter case (file -> FILE... is problematic in NTFS)
- [ ] consolidate a single version of the script
- [ ] add support for SSH in source or target (but not both)
- [ ] add stats of actions done
- [ ] log file option? (moved files and renamed files in the log)
- [ ] add command to wipe all databases in temp dir. aka `rm /tmp/presync-*`
- [ ] add cross platform tests

### DONE

- [x] add dry-run to posix version (using cop yof database to simulate filename collisions and renames)
- [x] add reuse db functionality to posix version, simplified non-interactive params `--keep-db` and `--resume` (only keep on dry-run)
- [x] review proper exit on error in `db_query` (no longer runs in a subshell, so exit does properly terminate the script)
- [x] implement end of params with -- in options processing
- [x] add tests for filenames with newline characters and problematic / non printable character combinations
- [x] add support for handling filenames with newline characters to posix version
- [x] do a test suite for multiple shells using docker
- [x] make configurable tmp dir via param
- [x] make configurable hasher command via param
- [x] add prune dirs option to posix version
- [x] add option to prune empty dirs (not existing in source)
- [x] create a posix compliant version for extended compatibility
- [x] get rid of .sh in presync.sh
- [x] add main wiki page / readme.md documentation
- [x] tag versions in fossil
- [x] consider caching source checksums when using `--dry-run`
- [x] refactor message printing
- [x] add option to disable colors `--no-color`
- [x] test message display of unreadable files in different display modes (verbose, quiet, normal)
- [x] handle empty hashes when processing - aka no read permission
- [x] move todo list to fossil (just versioned it)
- [x] add option for --progress so it computes the total at the expense of double find command run. Caching should solve speed. test.
- [x] add usage information / license info
- [x] rework paramater parsing
- [x] add support for partial file hashes with optional chunk size with param validation regex: `head -c 1024k largefile | xxh128sum`
- [x] bring this to fossil-scm... it is growing a bit more than a one time use shell script for my file sync needs.
- [x] do a few oneliners for partial hash collission tests with different head sizes
