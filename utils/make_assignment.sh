#!/usr/bin/env bash
cat <<OEND
# shellcheck shell=bash disable=SC2034
AssignmentName="$1"
AssignmentNamePretty="$2"
AssignmentDescription=\$(cat <<END
END
)
OEND
