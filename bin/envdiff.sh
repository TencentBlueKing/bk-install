#!/usr/bin/env bash
# Description: show diff from default/xx.env to 04-final/xx.env

SELF_DIR=$(readlink -f "$(dirname "$0")")
ENV_FILENAME="$1"
DEFAULT_ENV_FILE=${SELF_DIR}/default/${ENV_FILENAME%.env}.env
FINAL_ENV_FILE=${SELF_DIR}/04-final/${ENV_FILENAME%.env}.env
if ! [[ -f $DEFAULT_ENV_FILE && -f $FINAL_ENV_FILE ]]; then
    echo "$DEFAULT_ENV_FILE or $FINAL_ENV_FILE is not exist."
    exit 1
fi

if [[ $(wc -l < "$DEFAULT_ENV_FILE") -ne $(wc -l < "$FINAL_ENV_FILE") ]]; then
    echo "$FINAL_ENV_FILE 's line number is not equal to $DEFAULT_ENV_FILE"
    exit 1
fi

# start comparing, using subshell with empty environment variables
# print out environment variables to tmp files
# and show diffs from the two tmp files
DEFAULT_TMP=$(mktemp /tmp/default_env_XXXXX)
FINAL_TMP=$(mktemp /tmp/final_env_XXXXXX)
trap 'rm -f $DEFAULT_TMP $FINAL_TMP' exit

env -i bash --noprofile --norc -c "set -a; source $DEFAULT_ENV_FILE; env | grep ^BK | sort > $DEFAULT_TMP"
env -i bash --noprofile --norc -c "set -a; source $FINAL_ENV_FILE;   env | grep ^BK | sort > $FINAL_TMP"

echo "DEFAULT($1) has following different value from FINAL($1): "
echo 
COLUMNS=$(tput cols)
sdiff -w "$COLUMNS" --suppress-common-lines "$DEFAULT_TMP" "$FINAL_TMP" 