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
sudo docker run --rm -ti -v "$PWD:/tests" presync/tests:alpine sh -c "$(cat <<ENDSSH

    cp -pr /tests /home/tester/isolated_tests
    cd /home/tester/isolated_tests || exit

    for SH in sh bash dash ksh; do
        echo "Running shellcheck with: \$SH"
        shellcheck -s \$SH ./presync_posix.sh || break
    done
ENDSSH
)"

for test_type in normal special_chars; do

    echo
    info_msg "Running test_normal (with sqlite3 binary)"
    sudo docker run --rm -ti -v "$PWD:/tests" presync/tests:alpine sh -c "$(cat <<ENDSSH

        cp -pr /tests /home/tester/isolated_tests
        cd /home/tester/isolated_tests || exit

        for SH in sh bash dash zsh oksh; do
            echo "Running \"test_normal.sh\" \"$test_type\" tests with shell: \$SH"

            if [ "\$SH" = "zsh" ]; then
                zsh -o shwordsplit -- ./test_normal.sh "$test_type"
                # zsh -o shwordsplit -- ./test_get_hash_from_file.sh "$test_type"
            else
                \$SH ./test_normal.sh "$test_type"
                # \$SH ./test_get_hash_from_file.sh "$test_type"
            fi

        done
ENDSSH
)"

    echo
    info_msg "Running test_normal in plain text mode (NO sqlite3 binary)"
    sudo docker run --rm -ti -v "$PWD:/tests" presync/tests:alpine-nodb sh -c "$(cat <<ENDSSH

        cp -pr /tests /home/tester/isolated_tests
        cd /home/tester/isolated_tests || exit

        for SH in sh bash dash zsh oksh; do
            echo "Running \"test_normal.sh\" \"$test_type\" (NO sqlite3 binary) tests with shell: \$SH"

            if [ "\$SH" = "zsh" ]; then
                zsh -o shwordsplit -- ./test_normal.sh "$test_type"
            else
                \$SH ./test_normal.sh "$test_type"
            fi

        done
ENDSSH
)"

done

rm presync_posix.sh

# EOF