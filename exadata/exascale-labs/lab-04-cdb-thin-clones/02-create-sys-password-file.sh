#!/usr/bin/env bash
# Create the encrypted SYS password file used by gDBClone.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lab-04-common.sh
. "$script_dir/lab-04-common.sh"

load_lab04_environment
require_gdbclone
require_lab04_value LAB04_SYS_PASSWORD_FILE

if [ -e "$LAB04_SYS_PASSWORD_FILE" ]; then
    confirm_lab04_action "The encrypted password file $LAB04_SYS_PASSWORD_FILE already exists and may be replaced."
fi

echo "Creating encrypted gDBClone SYS password file: $LAB04_SYS_PASSWORD_FILE"
run_gdbclone syspwf -syspwf "$LAB04_SYS_PASSWORD_FILE"
run_lab04_sudo chmod 600 "$LAB04_SYS_PASSWORD_FILE"

echo "PASS: Encrypted SYS password file created."
