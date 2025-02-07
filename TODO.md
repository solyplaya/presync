# Tasks

### TODO

- [ ] get rid of .sh in presync.sh
- [ ] add option to prune empty dirs not existing in source
- [ ] add main wiki page / readme.md documentation
- [ ] add stats of actions done, specially useful for `--compact` view
- [ ] log file option? (moved files and renamed files in the log)
- [ ] add command to wipe all databases in temp dir. aka `rm /tmp/presync-*.sqlite3`
- [ ] add test suite
- [ ] consider this progress bar: https://github.com/pollev/bash_progress_bar

### DONE

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
