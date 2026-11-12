# Entry point: read -> choose -> plan -> review -> apply.
REPO_DIR=$installer_root
# shellcheck source=installer/core.sh
source "$REPO_DIR/installer/core.sh"
# shellcheck source=installer/selection.sh
source "$REPO_DIR/installer/selection.sh"
# shellcheck source=installer/recipes.sh
source "$REPO_DIR/installer/recipes.sh"
# shellcheck source=installer/android.sh
source "$REPO_DIR/installer/android.sh"
# shellcheck source=installer/receipts.sh
source "$REPO_DIR/installer/receipts.sh"
# shellcheck source=installer/planner.sh
source "$REPO_DIR/installer/planner.sh"
# shellcheck source=installer/executor.sh
source "$REPO_DIR/installer/executor.sh"
# shellcheck source=installer/ui.sh
source "$REPO_DIR/installer/ui.sh"
declare -ga ACTION_KIND=() ACTION_LABEL=() PLAN_NOTES=() TEMP_DIRS=()

main() {
    load_catalog
    parse_arguments "$@"
    if [[ $SHOW_HELP == true ]]; then
        usage
        return 0
    fi
    detect_platform
    if [[ $LIST == true ]]; then
        case $DISTRO in debian | ubuntu | fedora | arch) select_backend ;; esac
        list_catalog
        return 0
    fi
    select_backend
    backend_scan_installed
    if [[ $NON_INTERACTIVE == false && -z $PRESET && -z $PROFILE ]]; then select_installed_choices; fi
    merge_choices
    if [[ $NON_INTERACTIVE == true ]]; then
        build_plan || {
            fail "$PLAN_ERROR"
            return 1
        }
        printf '%s' "$PLAN"
        if [[ $DRY_RUN == true ]]; then return 0; fi
        [[ $AUTO_YES == true ]] || {
            fail 'Non-interactive application requires --yes. Use --dry-run to preview.'
            return 1
        }
    else
        [[ -t 0 && -t 1 ]] || {
            fail 'Interactive mode needs a terminal. Use --non-interactive --dry-run for a headless preview.'
            return 1
        }
        if [[ $DRY_RUN == false && $EUID == 0 ]]; then
            fail 'Run as your normal user; sudo is used only for system changes.'
            return 1
        fi
        choose_ui
        if ! interactive_choices; then
            printf '%s\n' 'Cancelled.'
            return 0
        fi
        printf '%s' "$PLAN"
        [[ $DRY_RUN == false ]] || return 0
    fi
    ((EUID != 0)) || {
        fail 'Run as your normal user; sudo is used only for system changes.'
        return 1
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    apply_plan
}
