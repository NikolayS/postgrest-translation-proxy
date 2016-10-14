#!/bin/bash

# How to run:
#  ./test/run.sh  2>/dev/null     – run manually w/o details
#  ./test/run.sh                  - run manually with details
#  ./test/run.sh -f junit         - get output in JUnit format (suatable for CircleCI)

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
failed=0
program=psql
condition=$(which $program 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ] ; then
    >&2 echo "\"$program\" tool is missing!"
    exit 1
fi

while getopts ":f:" opt; do
  case $opt in
    f) format="$OPTARG"
    ;;
    \?) >&2 echo "Invalid option -$OPTARG" && exit 1
    ;;
  esac
done

path=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )

testscount=$( ls -1 "$path/cases/"*.sh | wc -l )

if [ "$format" == "junit" ] ; then
    echo "<testsuite tests=\"$testscount\">"
fi

for f in $(ls "$path/cases/"*.sh)
do
    casename=$(echo "$f" | sed s/\.sh// | sed s%"$path/cases/"%%)
    #echo "Processing test case: \"$casename\""
    touch "$path/cases/$casename.expected" # if it doesn't exist, create it
    result=$(diff -iw "$path/cases/$casename.expected" <($f 2>/dev/null))
    if [ "$result" != "" ]
    then
        let "failed++"
        if [ "$format" == "junit" ] ; then
            echo "<testcase classname=\"cases/$casename.sh\" name=\"$casename\">"
            echo "  <failure type=\"NotExpectedOutput\">"
            echo "      <![CDATA["
            echo $result
            echo "]]>"
            echo "  </failure>"
            echo "</testcase>"
        else
            printf "${RED}FAILED${NC} test case \"$casename\"! See STDERR (or error log) for details\n"
            >&2 echo "[$(date)] FAILED test case \"$casename\""
            >&2 echo "Details:"
            >&2 echo "--------------------"
            >&2 echo "$result"
            >&2 echo "--------------------"
        fi
    else
        if [ "$format" == "junit" ] ; then
            echo "<testcase classname=\"cases/$casename.sh\" name=\"$casename\"/>"
        else
            printf "${GREEN}PASSED${NC} test case \"$casename\"\n"
        fi
    fi
done

if [ "$format" == "junit" ] ; then
    echo "</testsuite>"
fi

if [ "$failed" -gt 0 ] ; then
    if [ "$format" == "junit" ] ; then
        nothing=0
    else 
        printf "${BLUE}DONE${NC} Failed test cases: $failed/$testscount\n"
    fi
    exit 1
fi

