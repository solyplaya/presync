# Tasks

### TODO

- [ ] add option for --progress so it computes the total at the expense of double find command run. Caching should solve speed. test.
- [ ] add usage information / documentation / license info
- [ ] add stats of actions done, specially useful for `--quiet` view
- [ ] log file option? (moved files and renamed files in the log)
- [ ] add command to wipe all databases in temp dir. aka `rm /tmp/presync-*.sqlite3`
- [ ] move todo list to fossil
- [ ] refactor message printing
- [ ] add option to disable colors `--no-color`
- [ ] consider caching source checksums when using `--dry-run`
- [ ] do a few oneliners for partial hash collission tests with different head sizes

### DONE

- [x] rework paramater parsing
- [x] add support for partial file hashes with optional chunk size with param validation regex: `head -c 1024k largefile | xxh128sum`
- [x] bring this to fossil-scm... it is growing a bit more than a one time use shell script for my file sync needs.


