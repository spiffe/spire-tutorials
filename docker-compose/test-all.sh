#!/bin/bash
# This script runs the test.sh script in each subdirectory to test if each
# tutorial is working properly. It is run by the Travis CI tool when a PR
# is submitted or merged on GitHub, but you can also run it interactively.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

bold=$(tput bold) || true
norm=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true

fail() {
	echo "${red}$*${norm}."
	exit 1
}

echo "${bold}Running all tests...${norm}"
for testdir in "${DIR}"/*; do
	if [[ -x "${testdir}/test.sh" ]]; then
		testname=$(basename "$testdir")
		echo "${bold}Running \"$testname\" test...${norm}"
		if ${testdir}/test.sh; then
			echo "${green}\"$testname\" test succeeded${norm}"
		else
			echo "${red}\"$testname\" test failed${norm}"
			FAILED=true
		fi
	fi
done

if [ -n "${FAILED}" ]; then
	fail "There were test failures"
fi
echo "${green}Done. All test passed!${norm}"
exit 0
