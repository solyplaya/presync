#!/usr/bin/env sh

# invoke: time ./run_tests.sh

info_msg() {

    echo "\033[1;32m${1}\033[0m"

}

# make sure we are in tests
cd "${0%/*}" || exit

# prepare test enviroment
cp ../presync_posix.sh ./ || exit

# run shellcheck
info_msg "Running shellcheck.,,"
sudo docker run --rm -ti -v "$PWD:/tests" presync/tests:alpine sh -c '

    cd /tests

    for SH in sh bash dash ksh; do
        echo "Running shellcheck with: $SH"
        shellcheck -s $SH ./presync_posix.sh || break
    done
'

# run test_normal.sh
echo
info_msg "Running test_normal (with sqlite3 binary)"
sudo docker run --rm -ti -v "$PWD:/tests" presync/tests:alpine sh -c '

    cd /tests

    for SH in sh bash dash zsh oksh; do
        echo "Running \"test_normal.sh\" tests with shell: $SH"

        if [ "$SH" = "zsh" ]; then
            zsh -o shwordsplit -- ./test_normal.sh
            # zsh -o shwordsplit -- ./test_get_hash_from_file.sh
        else
            $SH ./test_normal.sh
            # $SH ./test_get_hash_from_file.sh
        fi

    done
'

echo
info_msg "Running test_normal in plain text mode (NO sqlite3 binary)"
sudo docker run --rm -ti -v "$PWD:/tests" presync/tests:alpine-nodb sh -c '
    cd /tests

    for SH in sh bash dash zsh oksh; do
        echo "Running \"test_normal.sh\" tests with shell: $SH"

        if [ "$SH" = "zsh" ]; then
            zsh -o shwordsplit -- ./test_normal.sh
        else
            $SH ./test_normal.sh
        fi

    done
'

rm presync_posix.sh