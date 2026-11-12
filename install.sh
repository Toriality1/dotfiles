#!/usr/bin/env bash
# Public entry point; retain .install.sh for existing checkouts and automation.
set -Eeuo pipefail
installer_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case $(uname -s) in
    MINGW* | MSYS* | CYGWIN*)
        command -v powershell.exe >/dev/null || { printf '%s\n' 'Run install.ps1 from PowerShell.' >&2; exit 1; }
        # Native Windows parameters have PowerShell names, listed by -Help.
        script=$installer_root/install.ps1
        if command -v cygpath >/dev/null; then script=$(cygpath -w "$script"); fi
        exec powershell.exe -NoProfile -File "$script" "$@"
        ;;
    *) exec bash "$installer_root/.install.sh" "$@" ;;
esac
