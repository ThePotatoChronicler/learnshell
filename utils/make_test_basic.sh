#!/usr/bin/env bash
cat <<END
# shellcheck shell=bash disable=SC2034
TestName="$2"
TestNamePretty="$3"

test_${1}_${2}_preparation() {
  :
}

test_${1}_${2}_test() {
  expectedUserCommand /dev/null /dev/null
  local status=\$?

  return \$status
}
END
