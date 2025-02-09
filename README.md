## What is PreSync?

presync is a bash script that renames files in target folder to match existing files in source folder based on content checksums.

presync does not copy or delete any files, only renames existing files in the destination directory based on content hash to prevent unnecessary file copying on rsync (or similar) command run.

## Installation

To install `presync`, follow these simple steps:

1. **Dependencies**

- `bash` - GNU Bourne Again SHell. Website: [bash](https://www.gnu.org/software/bash/)
- `sqlite3`: A command-line interface for SQLite databases. Website: [sqlite](https://sqlite.org/)
- `xxhash`: command-line tool for computing a fast non-cryptographic checksum. Website: [xxhash](https://github.com/Cyan4973/xxHash)

You can install these dependencies using your system's package manager. For example, on Ubuntu/Debian:

```bash
sudo apt-get install bash sqlite3 xxhash
```

2. **Download the script**

   You can download the `presync.sh` script from the repository:

```bash
wget https://github.com/githubusername/presync/raw/main/presync.sh
```

3. **Make the script executable**

Grant execution permissions to the script:

`chmod +x presync.sh`

4. **Move the script to a directory in your PATH**

To make the script easily accessible from anywhere, move it to a directory included in your system's `PATH` (e.g., `/usr/local/bin` for system-wide use or `~/bin` for user-specific use):

```bash
sudo mv presync.sh /usr/local/bin/presync   # System-wide
# or
mv presync.sh ~/bin/presync                 # User-specific
```

Notice that this installs `presync` executable without the `.sh` extension.

If you choose to use a user-specific directory like `~/bin`, ensure it's added to your `PATH` by adding the following to your `~/.bashrc` or `~/.bash_profile`:

```bash
export PATH=$PATH:~/bin
```

4. **Verify installation**

Check that the script is installed correctly by running:

```bash
presync --help
```

## Usage

```
presync [OPTION]... SRC DEST
```

Options:

    --compact, -c    show less text output and use in-place progress messages
    --debug, -d      dumps database of targets before / after processing
    --dry-run        trial run without file changes (implies --keep-db)
    --flush-db, -f   remove any existing db without asking
    --help, -h       show this help
    --keep-db, -k    don't delete database after running (ignores --flush-db)
    --muted, -m      don't output any text
    --no-color       print all messages without color
    -P               same as --partial 1024
    --partial SIZE   calc checksums using at most N kilobytes from file
    --progress, -p   show progress of total files
    --quiet, -q      show only in-place progress messages
    --resume         resume from last record in database (implies --reuse-db)
    --reuse-db, -r   use an existing database of targets without asking
    --verbose, -v    increase verbosity

presync only considers files, so if you rename a folder `src/A` to `src/B`, the script will move all the files in `dst/A` to `dst/B` one by one, instead of renaming the folder. Empty folders left behind are there to be deleted by your rsync program run.

On conflicts existing files get renamed to `filename_[renamed_1].ext`

Using the --partial argument you can speed up the synchronization process since only a smaller amount of data from the beginning of each file is used to calc its checksum. This could lead to some false file matchings in the event that various files share the same header data. Since no files are deleted or overwritten, any incorrectly reorganized files will get resolved by rsync.

Database files are stored in `/tmp/presync-[params checksum].sqlite` and deleted after a successful run unless `--keep-db` or `--dry-run` options are given.

## Examples

Synchronize renamed files in backup

```bash
presync /home/user/Pictures /media/backup/Pictures
```

Synchronize movies collection on slow USB drive with huge files:

```bash
presync --partial 2048 --keep-db /media/movies /media/movies_backup
```

Do a test run without modifying any files, then reuse the database:

```bash
presync --dry-run /home/user/Pictures /media/backup/Pictures

presync --resume /home/user/Pictures /media/backup/Pictures
```

Run rsync without copying again renamed files in target folder:

```bash
presync --muted src dst && rsync --av --delete --progress src dst
```

The `--muted` option causes presync to not output any messages at all. On error exit code 1 is returned.

## Partial checksums

Using partial checksums allows for a faster processing of large files specially on slow mediums. If you are curious, below are some commands to help identify hash collisions when using way to small partial sizes.

First count the number of files in current directory:
```bash
find . -type f | wc -l
```

Then run the following one-liner and compare how many unique files each head size brings:
```bash
for size in 1K 5K 10K 100K; do echo "head size: $size:"; find . -type f -exec sh -c 'head -c '"$size"' "$1" | xxh128sum' _ {} \; | sort -u | wc -l; done
```

For most of the tests I have performed with a large base of files, 1k head size was enough to uniquely identify each file without any collision.

That would be equivalent to:

```bash
presync --partial 1 src dst
```

## Processing huge directories

Before presync can start renaming target files it must collect the checksum of all existing files in source and target folders. If you have to process a huge amount of files on a slow medium it can take quite some time. For that reason you have the option `--resume` to continue computing hashes from a previously interrupted run as long as `--dry-run` or `--keep-db` options were given.

```bash
presync --dry-run src dst
```

Interrupt processing with `ctrl+c` at any time, then to continue from the last processed file:

```bash
presyncS --resume src dst
```

If you run presync without `--resume` and it encounters a database file from a previous run, it will ask you wheter you want to reuse it or not. Have that into account if you are using `--muted` option for your batch or cron scripts. For that matter you have the `--resume`, `--reuse-db` and `--flush-db` options available.

## ToDo

You can read the planned to do features in [TODO.md](TODO.md) file

## License

PreSync is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.

## NOTICE: this is a mirror of a local fossil repo

This project is hosted locally on a [fossil](https://fossil-scm.org/) repo and [mirrored automatically](https://www.fossil-scm.org/home/doc/trunk/www/mirrortogithub.md) to github.
