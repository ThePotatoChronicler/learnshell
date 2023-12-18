#!/usr/bin/env bash

# Constants
readonly DEFHOME=/home/student
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
        $installer $1
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
  local packages
  packages=(fakechroot stty)

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
    local _B=$'\e[1m' _R=$'\e[m' \
      _BB=$'\e[44m' \
      _CB

    local cols
    cols=$(stty size | cut -d' ' -f2) || errorMsg "Could not obtain terminal size"

    spaces=$((cols > 80 ? 80 : cols))

    _CB=$'\e[44m'$(printf ' %.0s' $(seq "$spaces"))$'\e['"$spaces"'D'
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
  ASSIGNMENT_METADATA["$name"":namePretty"]="$AssignmentNamePretty"
  ASSIGNMENT_METADATA["$name"":description"]="$AssignmentDescription"
  ASSIGNMENT_METADATA["$name"":script"]="$1"
  ASSIGNMENT_METADATA["$name"":organisation"]="$organisation"

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
    printf "%s\n" "$assignment|${ASSIGNMENT_METADATA["${assignment}:namePretty"]}"
  done | column -t -s'|' -C name=ID -C name=Name
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

  mkdir -p "${envdir}${DEFHOME}"

  printf "%s" "$envdir"
}

loadTest() {
  local TestName TestNamePretty
  
  # Example for shellcheck to shut up
  # shellcheck source=./tests/hello/basic.sh
  source "$1"

  TESTS+=("$TestName")
  TEST_METADATA["$TestName"":namePretty"]="$TestNamePretty"
}

getCurrentOrgExt() {
  local org="${ASSIGNMENT_METADATA["$USER_ASSIGNMENT"":organisation"]}"
  if [[ -n "$org" ]]; then
    printf ".%s" "$org"
  fi
  return 0
}

loadAllTestsForCurrentAssignment() {

  local orgext
  orgext="$(getCurrentOrgExt)"

  declare -a tests=("$(csdir)"/tests"$orgext"/"${USER_ASSIGNMENT%"$orgext"}"/*.sh)
  
  if [[ "${#tests[@]}" -eq 0 ]]; then
    fatalMsg "There are no test files for assignment $USER_ASSIGNMENT"
    return 1
  fi

  for file in "${tests[@]}"; do
    [[ -d "$file" ]] && { errorMsg "Test $file is a directory"; continue; }
    loadTest "$file"
  done
}

testFailMsg() {
  isTerminal && local _C=$'\e[31m' _R=$'\e[m'

  printf "< ${_C}FAIL${_R}> %s\n" "${TEST_METADATA["$1"":namePretty"]}"
}

testSuccessMsg() {
  isTerminal && local _C=$'\e[32m' _R=$'\e[m'

  printf "<  ${_C}OK${_R} > %s\n" "${TEST_METADATA["$1"":namePretty"]}"
}

testtf() {
  mktemp --tmpdir learnshell_test.XXXXXXXX
}

bytesLength() {
  wc -c "$1" | cut -d' ' -f1
}

# Makes path relative to default home of the environment
envHome() {
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


# shellcheck disable=SC2120
runUserCommand() {
  HOME="${DEFHOME}" fakechroot -- chroot "${ENVDIR}" \
    /bin/bash -c "cd '${ENVCWD:-$DEFHOME}'; exec /bin/bash /student.sh "'"$@"' startup_script "$@"
}

expectedUserCommand() {
  stdouttf="$(testtf)"
  stderrtf="$(testtf)"

  local expectedStdout="$1" expectedStderr="$2" status=0
  shift 2
  
  runUserCommand "$@" <&0 >"$stdouttf" 2>"$stderrtf"
  # status=$?

  testCompareStdout "$expectedStdout" "$stdouttf"
  status=$(($? > status ? $? : status))

  testCompareStderr "$expectedStderr" "$stderrtf"
  status=$(($? > status ? $? : status))

  rm "$stdouttf" "$stderrtf"

  return $status
}

testAssignment() {
  local envdir outputtf orgext
  orgext="$(getCurrentOrgExt)"
  
  for testId in "${TESTS[@]}"; do
    local fnprefix="test_${USER_ASSIGNMENT%"$orgext"}_${testId}" status override
    
    envdir="$(prepareBaseEnvironment)" || {
      errorMsg "Could not create base environment"
      return 1
    }

    outputtf="$(testtf)" || {
      errorMsg "Failed to create temporary output file for test $testId"
      return 1
    }

    ENVDIR="$envdir" "${fnprefix}_preparation" || {
      errorMsg "Failed to run preparation script for test $testId"
      return 1
    }

    isTerminal && override=yes

    OVERRIDE_ISTERMINAL="$override" ENVDIR="$envdir" \
      "${fnprefix}_test" > "$outputtf"

    # The previous line is just too damned long to put this in front of it
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
