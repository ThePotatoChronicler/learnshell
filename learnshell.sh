#!/usr/bin/env bash

# Constants
readonly DEFHOME=/home/student
readonly -a DEFENVDIRS=("$DEFHOME" "/tmp")
# /Constants

# Functions

# Gets the directory of the CALLER script, not the CALLEE
csdir() {
  printf "%s" "$(dirname "$(readlink -f "${BASH_SOURCE[1]}")")"
}

getSystemId() {
  awk -F= '$1 == "ID" { printf "%s", $2; exit; }' /etc/os-release
}

checkPackage() {
  command -v "$1" &> /dev/null
}

# https://stackoverflow.com/a/8574392
elementIn() {
  local e needle="$1"
  shift
  for e; do [[ "$e" == "$needle" ]] && return 0; done
  return 1
}

getSudoOrAlternative() {
  checkPackage "sudo" && printf "sudo" && return
  checkPackage "doas" && printf "doas" && return

  printf "sudo"
}

recommendPackageDownload() {
  local systemid installer
  systemid="$(getSystemId)"

  cat <<END | sed -E 's/^ {4}//'
    You are missing a required program/package: "$1"
    To install it, use your system's package manager
END

  case $systemid in
    arch) installer="pacman -S" ;;
    debian | ubuntu | mint) installer="apt install" ;;
    fedora) installer="dnf install" ;;
  esac

  if [[ -v installer ]]; then
    cat <<END | sed -E 's/^ {6}//'

      A command like this could work (although the package may be named differently):
        $(getSudoOrAlternative) $installer $1
END
  else
    cat <<END | sed -E 's/^ {6}//'

      Could not detect your package manager, you are on your own
END
  fi
}

isTerminal() {
  [[ -t "${1-1}" ]] || [[ -n "${OVERRIDE_ISTERMINAL}" ]]
}

# Program exiting error
fatalMsg() {
  if isTerminal 2; then
    local _C=$'\e[31m' _R=$'\e[m'
  fi

  printf "[${_C}FATAL${_R}] %s\n" "$1" >&2
}

# Non-program exiting error
errorMsg() {
  if isTerminal 2; then
    local _C=$'\e[31m' _R=$'\e[m'
  fi

  printf "[${_C}ERROR${_R}] %s\n" "$1" >&2
}

checkIfRoot() {
  if (( EUID != 0 )) || [[ "$ALLOWROOT" == "yes" ]]; then
    return 0
  fi

  fatalMsg "Do not run this program as root user, you are risking your own computer"
  fatalMsg "(If you must risk yourself like this, set variable ALLOWROOT=yes)"
  exit 1
}

checkForPackages() {
  local packages package
  packages=(fakechroot)

  for package in "${packages[@]}"; do
    if ! checkPackage "$package"; then
      fatalMsg "Missing package $package"
      recommendPackageDownload "$package"
      return 1
    fi
  done
}

getOrganisationFromScriptPath() {
  # I promise I am not a heretic
  local v="${1#"${1%assignments.*/*.sh}"}"
  v="${v%/*.sh}"
  v="${v#assignments.}"
  printf "%s" "$v"
}


loadAssignment() {
  if isTerminal; then
    # Utilities for assignment scripts
    local _B=$'\e[1m' _I=$'\e[3m' _U=$'\e[4m' _R=$'\e[m' \
      _BB=$'\e[44m' \
      _CB=$'\e[44m\e[80G\e[1K\e[G'
  fi

  
  local AssignmentName AssignmentNamePretty AssignmentDescription
  # Example for shellcheck to shut up
  # shellcheck source=./assignments/hello.sh
  source "$1"

  local organisation orgext
  organisation="$(getOrganisationFromScriptPath "$1")"

  if [[ -n "$organisation" ]]; then
    orgext=".${organisation}"
  fi

  # Absolute name
  local name="$AssignmentName""$orgext"

  ASSIGNMENTS+=("$name")
  ASSIGNMENT_METADATA["$name:namePretty"]="$AssignmentNamePretty"
  ASSIGNMENT_METADATA["$name:description"]="$AssignmentDescription"
  ASSIGNMENT_METADATA["$name:script"]="$1"
  ASSIGNMENT_METADATA["$name:organisation"]="$organisation"

}

loadAllAssignments() {
  declare -a assignments=("$(csdir)"/assignments/*.sh "$(csdir)"/assignments.*/*.sh)
  if [[ "${#assignments[@]}" -eq 0 ]]; then
    fatalMsg "There are no assignments"
    return 1
  fi

  for assignment_script in "${assignments[@]}"; do
    [[ -d "$assignment_script" ]] && { errorMsg "Assignment script $assignment_script is a directory"; continue; }
    loadAssignment "$assignment_script"
  done
}

usage0() {
  if isTerminal; then
    local _CG=$'\e[32m' _R=$'\e[m'
  fi
  
  cat <<END | sed -E 's/^ {4}//'
    ${_CG}Usage: $0 assignment script${_R}
      assignment - The assignment to test script on, must be specified by ID
      script - Script to test

    Available assignments:
END

  for assignment in "${ASSIGNMENTS[@]}"; do
    printf "%s\n" "$assignment"$'\t'"${ASSIGNMENT_METADATA["${assignment}:namePretty"]}"
  done | {
    column -t -s$'\t' -N ID,Name  2>/dev/null ||
      { echo -e "ID\tName"; cat; }
  }
}

printTitle() {
  if isTerminal; then
    local _C=$'\e[1;4;30;47m' _R=$'\e[m'
  fi
  printf "${_C}%s${_R}\n" "$1"
}

describeAssignment() {
  printTitle "${ASSIGNMENT_METADATA["$1"":namePretty"]}"
  printf "%s\n" "${ASSIGNMENT_METADATA["$1"":description"]}"
}

verifyAssignment() {  
  if ! elementIn "$1" "${ASSIGNMENTS[@]}"; then
    fatalMsg "$(printf "Assignment %s does not exist" "$1")"
    return 1
  fi
}

parseArgs() {
  if [[ $# -eq 0 ]]; then
    usage0
    return 1
  fi

  if [[ $# -eq 1 ]]; then
    verifyAssignment "$1" || return
    describeAssignment "$1"
    exit 0
  fi

  if [[ $# -eq 2 ]]; then
    verifyAssignment "$1" || return
    
    if ! [[ -e "$2" ]] && [[ "$IGNOREPERMS" != "yes" ]]; then
      fatalMsg "Script '$2' does not seem to exist (ignore with IGNOREPERMS=yes)"
      return 1
    fi
    
    if ! [[ -r "$2" ]] && [[ "$IGNOREPERMS" != "yes" ]]; then
      fatalMsg "Script '$2' does not seem readable (ignore with IGNOREPERMS=yes)"
      return 1
    fi

    USER_ASSIGNMENT="$1"
    SCRIPT="$(realpath "$2")"
    
    return 0
  fi

  errorMsg "Too many arguments"
  return 1
}

prepareBaseEnvironment() {
  local envdir
  envdir="$(mktemp --tmpdir -d "learnshell_env.XXXXXXXX")" || {
    errorMsg "Could not create base environment directory"
    return 1
  }

  for dir in bin lib lib64 usr etc var nix opt dev sys; do
    [[ -e "/$dir" ]] && ln -s "/$dir" "$envdir/"
  done

  ln -s "$SCRIPT" "$envdir/student.sh" || {
    errorMsg "Could not link user script to environment"
    return 1
  }

  mkdir -p "${envdir}${DEFHOME}" "${envdir}/tmp"

  printf "%s" "$envdir"
}

loadTest() {
  local TestName TestNamePretty \
    TestStyle=basic TestMultiReportStyle=split

  declare -a TestMultiNames TestMultiDescriptions
  
  # Example for shellcheck to shut up
  # shellcheck source=./tests/hello/basic.sh
  source "$1"

  TESTS+=("$TestName")
  TEST_METADATA["$TestName:namePretty"]="$TestNamePretty"
  TEST_METADATA["$TestName:testStyle"]="$TestStyle"

  if [[ "$TestStyle" == multi ]]; then
    TEST_METADATA["$TestName:testMultiReportStyle"]="${TestMultiReportStyle}"
    
    if [[ "${#TestMultiNames[@]}" -ne "${#TestMultiDescriptions[@]}" ]]; then
      errorMsg "Test $TestName with style multi has differing counts of names and descriptions"
      return 1
    fi
    TEST_METADATA["$TestName:testMultiNamesSize"]="${#TestMultiNames[@]}"
    TEST_METADATA["$TestName:testMultiDescriptionsSize"]="${#TestMultiDescriptions[@]}"

    local i
    for i in $(seq "${#TestMultiNames[@]}"); do
      TEST_METADATA["$TestName:testMultiNames:$i"]="${TestMultiNames[((i - 1))]}"
      TEST_METADATA["$TestName:testMultiDescriptions:$i"]="${TestMultiDescriptions[((i - 1))]}"
    done
  fi
}

getCurrentOrgExt() {
  local org="${ASSIGNMENT_METADATA["$USER_ASSIGNMENT"":organisation"]}"
  if [[ -n "$org" ]]; then
    printf ".%s" "$org"
  fi
  return 0
}

loadAllTestsForCurrentAssignment() {

  local orgext file
  orgext="$(getCurrentOrgExt)"

  declare -a tests=("$(csdir)"/tests"$orgext"/"${USER_ASSIGNMENT%"$orgext"}"/*.sh)
  
  if [[ "${#tests[@]}" -eq 0 ]]; then
    fatalMsg "There are no test files for assignment $USER_ASSIGNMENT"
    return 1
  fi

  for file in "${tests[@]}"; do
    [[ -d "$file" ]] && { errorMsg "Test $file is a directory"; continue; }
    loadTest "$file" || return
  done
}

getMultiReportStylePrefix() {  
    case "${TEST_METADATA["$1"":testMultiReportStyle"]}" in
      grouped) printf "%s " "-" ;;
      split) ;;
      *) errorMsg "Unknown report style in test $1" ; return 1 ;;
    esac
}

testMsgBase() {
  case "${TEST_METADATA["$1:testStyle"]}" in
    basic)
      printf "<%s> %s\n" "$2" "${TEST_METADATA["$1"":namePretty"]}"
      ;;
    multi)
      local description
      description="${TEST_METADATA["$1:testMultiDescriptions:$MULTI_RUN_INDEX"]}"
      printf "%s<%s> %s\n" "$(getMultiReportStylePrefix "$1")" "$2" "$description"
      ;;
    *)
      errorMsg "Test $1 has unknown test style - cannot print"
      return 1
      ;;    
  esac
}

testFailMsg() {
  isTerminal && local _C=$'\e[31m' _R=$'\e[m'
  testMsgBase "$1" "${_C}FAIL${_R}"
}

testSuccessMsg() {
  isTerminal && local _C=$'\e[32m' _R=$'\e[m'
  testMsgBase "$1" "${_C} OK ${_R}"
}

testtf() {
  mktemp --tmpdir learnshell_test.XXXXXXXX
}

bytesLength() {
  wc -c "$1" | cut -d' ' -f1
}

# Makes path relative to default home of the environment
envHome() {
  # shellcheck disable=SC2153
  printf "%s%s/%s" "$ENVDIR" "$DEFHOME" "$1"
}

# shellcheck disable=SC2059
testCompare() {
  if ! cmp -s "$1" "$2"; then
    printf "$3:\n" "$(bytesLength "$1")"
    cat "$1"
    echo
    printf "$4:\n" "$(bytesLength "$2")"
    cat "$2"
    echo
    return 1
  fi
}

testCompareStdout() {
  isTerminal && local _C=$'\e[44m' _R=$'\e[m'
  testCompare "$1" "$2" "${_C}Expected standard output (%d bytes)${_R}" "${_C}Received standard output (%d bytes)${_R}"
}

testCompareStderr() {
  isTerminal && local _C=$'\e[41m' _R=$'\e[m'
  testCompare "$1" "$2" "${_C}Expected standard error (%d bytes)${_R}" "${_C}Received standard error (%d bytes)${_R}"
}

# shellcheck disable=SC2059
testVerifyPermissions() {
  isTerminal && local _C=$'\e[43m' _R=$'\e[m'

  if [[ -e "$2" ]] && (( "$1" == "$(stat -c%#a "$2" )" )); then
    return 0
  fi

  printf "${_C}Expected file %s to have permissions %s${_R}\n\n" "$3" "$1"
  if [[ -e "$2" ]]; then
    printf "${_C}Received file %s has permissions %s${_R}\n\n" "$3" "$(stat -c%#.4a "$2")"
  else
    printf "${_C}Received file %s does not exist${_R}\n\n" "$3"
  fi

  return 1
}

# EVNDIR relative version of testVerifyPermissions
testVerifyPermissions_r() {
  testVerifyPermissions "$1" "$ENVDIR/$2" "$2"
}

# shellcheck disable=SC2059
testCompareFiles() {
  isTerminal && local _C=$'\e[42m' _R=$'\e[m'

  if ! cmp -s "$1" "$2"; then
    printf "${_C}Expected file %s (%d bytes)${_R}:\n" "$3" "$(bytesLength "$1")"
    cat "$1"
    echo
    if [[ -e "$2" ]]; then
      printf "${_C}Received file %s (%d bytes)${_R}:\n" "$3" "$(bytesLength "$2")"
      cat "$2"
    else
      printf "${_C}Received file %s does not exist${_R}\n" "$3"
    fi
    echo
    return 1
  fi
}

# EVNDIR relative version of testCompareFiles
testCompareFiles_r() {
  testCompareFiles "$1" "$ENVDIR/$2" "$2"
}

# Makes sure there are no work files in selected directories
# Defaults to /tmp and /home/student
testVerifyWorkFiles() {
  if [[ $# -eq 0 ]]; then
    set -- "${DEFENVDIRS[@]}" "\0"
  fi

  declare -a args

  local tf status=0 directory end_of_dirs=no

  for directory; do
    [[ "$directory" == "\0" ]] && { end_of_dirs=yes; args+=(")"); continue; }
    if [[ "$end_of_dirs" == yes ]]; then
      args+=("!" "-path" "${ENVDIR}$directory")
    else
      if (( "${#args[@]}" == 0 )); then
        args+=("(" "-path" "${ENVDIR}${directory}/*")
      else
        args+=("-o" "-path" "${ENVDIR}${directory}/*")
      fi
    fi
  done

  tf=$(testtf) || {
    errorMsg "Could not create temporary file"
    return 2
  }

  find "$ENVDIR"  -mindepth 1 -type f "${args[@]}" -printf "/%P\n" >> "$tf"

  [[ -s "$tf" ]] && {
    isTerminal && local _C=$'\e[45m' _R=$'\e[m'

    printf "%sFound extra work files%s\n" "$_C" "$_R"

    cat "$tf"

    printf "\n%sEnd of extra work files%s\n\n" "$_C" "$_R"

    status=1
  }

  rm "$tf"
  return $status
}

reportDifferingStatusCodes() {
  isTerminal && local _C=$'\e[30;46m' _R=$'\e[m'

  printf "${_C}Expected status code: %s\n\n${_R}" "$1"
  printf "${_C}Received status code: %s\n\n${_R}" "$2"
}

# shellcheck disable=SC2120
runUserCommand() {
  HOME="${DEFHOME}" fakechroot -- chroot "${ENVDIR}" \
    /bin/bash -c "cd '${ENVCWD:-$DEFHOME}'; exec /bin/bash /student.sh "'"$@"' startup_script "$@"
}

expectedUserCommand() {
  stdouttf="$(testtf)" || {
    errorMsg "Could not create temporary file for stdout"
    return 2
  }

  stderrtf="$(testtf)" || {
    errorMsg "Could not create temporary file for stderr"
    return 2
  }

  local expectedStdout="$1" expectedStderr="$2" dlt1=no dlt2=no
  shift 2

  if [[ "$expectedStdout" =~ /dev/fd/[0-9]+ ]]; then
    local stdoutCopy
    stdoutCopy=$(testtf) || {
      errorMsg "Could not create temporary file for stdout copy"
      return 2
    }

    cat "$expectedStdout" > "$stdoutCopy"
    expectedStdout="$stdoutCopy"

    dlt1=yes
  fi

  if [[ "$expectedStderr" =~ /dev/fd/[0-9]+ ]]; then
    local stderrCopy
    stderrCopy=$(testtf) || {
      errorMsg "Could not create temporary file for stderr copy"
      return 2
    }

    cat "$expectedStderr" > "$stderrCopy"
    expectedStderr="$stderrCopy"

    dlt2=yes
  fi
  
  runUserCommand "$@" <&0 >"$stdouttf" 2>"$stderrtf"
  local status=$?

  testCompareStdout "$expectedStdout" "$stdouttf"
  local stdoutStatus=$?

  testCompareStderr "$expectedStderr" "$stderrtf"
  local stderrStatus=$?

  rm "$stdouttf" "$stderrtf"
  [[ $dlt1 == yes ]] && rm "$expectedStdout"
  [[ $dlt2 == yes ]] && rm "$expectedStderr"

  local exitStatus=0

  if [[ "$EXPECT_STATUS" =~ ^[0-9]+$ ]] && (( "$EXPECT_STATUS" != status )); then
    reportDifferingStatusCodes "$EXPECT_STATUS" "$status"
    exitStatus=1
  fi

  return $((exitStatus | ((stdoutStatus > stderrStatus ? stdoutStatus : stderrStatus) << 6)))
}

runTestBase() {
  local envdir outputtf orgext testId="${1?}" status
  shift 1

  orgext="$(getCurrentOrgExt)"
  local fnprefix="test_${USER_ASSIGNMENT%"$orgext"}_${testId}"
  
  envdir="$(prepareBaseEnvironment)" || {
    errorMsg "Could not create base environment"
    return 1
  }

  outputtf="$(testtf)" || {
    errorMsg "Failed to create temporary output file for test $testId"
    return 1
  }

  ENVDIR="$envdir" "${fnprefix}_preparation" "$@" || {
    errorMsg "Failed to run preparation script for test $testId"
    return 1
  }

  ENVDIR="$envdir" \
    "${fnprefix}_test" "$@" > "$outputtf"

  status=$?

  if [[ "$status" -eq 0 ]]; then
    testSuccessMsg "$testId"
  else
    testFailMsg "$testId"
    cat "$outputtf"
    rm -rf "$envdir" "$outputtf"
    return 2
  fi

  rm -rf "$envdir" "$outputtf"
}

runBasicTest() {
  runTestBase "$1"
}

runMultiTest() {
  local it name status=0 outputs

  outputs=$(testtf) || {
    errorMsg "Could not create temporary file for multi-test output"
    return 2
  }

  for it in $(seq "${TEST_METADATA["$1:testMultiNamesSize"]}"); do
    name="${TEST_METADATA["$1:testMultiNames:$it"]}"
    MULTI_RUN_INDEX="$it" runTestBase "$1" "$name" >> "$outputs"
    status=$(( $? > status ? $? : status ))
    [[ "$status" -ne 0 ]] && break
  done

  if [[ "${TEST_METADATA["$1:testMultiReportStyle"]}" == grouped ]]; then
    local msg
    isTerminal && local _FR=$'\e[31m' _FG=$'\e[32m' _R=$'\e[m'
    if [[ "$status" -eq 0 ]]; then
      msg="${_FG} OK ${_R}"
    else
      msg="${_FR}FAIL${_R}"
    fi

    printf "<%s> %s\n" "$msg" "${TEST_METADATA["$1:namePretty"]}"
  fi

  cat "$outputs"
  rm "$outputs"

  return $status
}

testAssignment() {
  isTerminal && declare -x OVERRIDE_ISTERMINAL=yes

  for testId in "${TESTS[@]}"; do
    if [[ "${TEST_METADATA["$testId:testStyle"]}" == basic ]]; then
      runBasicTest "$testId" || return
    elif [[ "${TEST_METADATA["$testId:testStyle"]}" == multi ]]; then
      runMultiTest "$testId" || return
    else
      errorMsg "Unknown test style in test $testId"
    fi
  done
}

main() {
  shopt -s nullglob
  
  checkIfRoot
  checkForPackages || exit

  declare -ga ASSIGNMENTS
  declare -gA ASSIGNMENT_METADATA
  loadAllAssignments || exit

  declare -g USER_ASSIGNMENT SCRIPT
  parseArgs "$@" || exit

  declare -ga TESTS
  declare -gA TEST_METADATA
  loadAllTestsForCurrentAssignment || exit

  testAssignment || exit
}
# /Functions

main "$@"
