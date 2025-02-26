# Tasks

### TODO

- [ ] wite test files for unreadable files / unreadable folders
- [ ] check proper exit code handling in `--muted` mode
- [ ] test filesystem exFat / NTFS to use intermediary filename renames with changing only letter case (file -> FILE... is problematic in NTFS)
- [ ] consolidate a single version of the script
- [ ] add dry-run to posix version (with renaming track in a database colums for used and renamed files for better simulation)
- [ ] add reuse db functionality to posix version, simplified non-interactive params `--keep-db` and `--resume`
- [ ] add support for SSH in source or target (but not both)
- [ ] review proper exit on error in `db_query`
- [ ] add stats of actions done
- [ ] log file option? (moved files and renamed files in the log)
- [ ] add command to wipe all databases in temp dir. aka `rm /tmp/presync-*`
- [ ] add cross platform tests
- [ ] consider this progress bar: https://github.com/pollev/bash_progress_bar

### DONE

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
