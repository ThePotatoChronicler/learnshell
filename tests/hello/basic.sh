# shellcheck shell=bash disable=SC2034
TestName="basic"
TestNamePretty="Standard output test"

test_hello_basic_preparation() {
  :
}

test_hello_basic_test() {
  expectedUserCommand "$(csdir)/hello.txt" /dev/null
}
