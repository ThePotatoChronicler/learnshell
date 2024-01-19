#!/usr/bin/env bash
cat <<END
# shellcheck shell=bash disable=SC2034
TestName="${3:-multi}"
TestNamePretty="$2"
TestStyle="multi"
TestMultiNames=({00..00})
TestMultiDescriptions=(
  ""
)

test_${1}_${3:-multi}_preparation() {
  cp "\$(csdir)/in\$1.txt" "\$ENVDIR/input.txt"
}

test_${1}_${3:-multi}_test() {
  expectedUserCommand "\$(csdir)/out\$1.txt" /dev/null
  local status=\$?

  testVerifyWorkFiles
  status=\$(( \$? > status ? \$? : status ))

  return \$status
}
END
