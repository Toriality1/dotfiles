#!/usr/bin/env bash
# The installer needs only Bash and standard OS tools. UI setup is automatic.
set -Eeuo pipefail
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
    printf '%s\n' 'This launcher requires Bash 4.4 or newer.' >&2
    exit 1
fi
installer_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=installer/main.sh
source "$installer_root/installer/main.sh"
main "$@"
