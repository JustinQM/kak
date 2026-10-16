LC_ALL=C
export LC_ALL

errf=$(mktemp "${TMPDIR:-/tmp}/kak-jj-err.XXXXXX") || exit
trap 'rm -f "$errf"' EXIT

log_tpl='separate(" ", change_id.shortest(8), commit_id.shortest(8), if(conflict, "(conflict)"), if(empty, "(empty)"), if(divergent, "(divergent)"), if(bookmarks, "[" ++ bookmarks.join(" ") ++ "]"), if(description, description.first_line(), "(no description)"), "·", author.email().local(), committer.timestamp().ago()) ++ "\n"'
annotate_tpl='commit.change_id().shortest(8) ++ " " ++ commit.commit_id().shortest(8) ++ " " ++ pad_start(5, line_number) ++ ": " ++ content'
nl='
'

kq()
{
    rest=$1
    out=
    while :
    do
        case "$rest" in
            *\'*)
                out="$out${rest%%\'*}''"
                rest=${rest#*\'}
                ;;
            *)
                out="$out$rest"
                break
                ;;
        esac
    done
    printf "'%s'" "$out"
}

emit()
{
    first=1
    for arg
    do
        if [ $first = 1 ]
        then
            printf '%s' "$arg"
            first=0
        else
            printf ' %s' "$(kq "$arg")"
        fi
    done
    printf '\n'
}

die()
{
    emit fail "jj: $1"
    exit
}

find_root()
{
    if [ -n "$kak_opt_jj_root" ]
    then
        root=$kak_opt_jj_root
        return
    fi
    dir=.
    case "$kak_buffile" in
        /*/*)
            [ -d "${kak_buffile%/*}" ] && dir=${kak_buffile%/*}
            ;;
    esac
    if ! root=$(cd "$dir" && jj root 2>&1 </dev/null)
    then
        die "no jj repo at $(cd "$dir" && pwd)"
    fi
}

run_jj()
{
    out=$(cd "$root" && JJ_EDITOR=false jj --no-pager --color=never "$@" </dev/null 2>"$errf")
}

jj_error()
{
    msg=$(cat "$errf")
    [ -n "$msg" ] || msg="command failed: jj $1"
    emit info -title 'jj error' "$msg"
    emit fail "jj: ${msg%%"$nl"*}"
    exit
}

refresh_root()
{
    emit set-option global jj_refresh_root "$root"
    printf 'jj-refresh-all\n'
    printf 'set-option global jj_refresh_root ""\n'
}

mutate()
{
    run_jj "$@" || jj_error "$1"
    refresh_root
    msg=$(cat "$errf")
    if [ -n "$msg" ]
    then
        emit echo "jj: ${msg%%"$nl"*}"
    fi
}

is_change_id()
{
    case "$1" in
        *[!k-z]* | '')
            return 1
            ;;
        ????????*)
            return 0
            ;;
    esac
    return 1
}

is_commit_id()
{
    case "$1" in
        *[!0-9a-f]* | '')
            return 1
            ;;
        ????????*)
            return 0
            ;;
    esac
    return 1
}

change_at_line()
{
    set -f
    prev=
    for word in $1
    do
        if is_change_id "$prev" && is_commit_id "$word"
        then
            printf '%s' "$prev"
            set +f
            return 0
        fi
        prev=$word
    done
    set +f
    return 1
}

single_change()
{
    run_jj log --no-graph -r "$1" -T 'change_id.shortest(8) ++ "\n"' || jj_error log
    case "$out" in
        '')
            die "revset matches no change: $1"
            ;;
        *"$nl"*)
            die "revset matches more than one change: $1"
            ;;
    esac
    change=$out
}

rel_path()
{
    case "$kak_buffile" in
        /*)
            ;;
        *)
            die "not a file buffer: $kak_bufname"
            ;;
    esac
    real_dir=$(cd "${kak_buffile%/*}" 2>/dev/null && pwd -P) || die "no such directory: ${kak_buffile%/*}"
    real=$real_dir/${kak_buffile##*/}
    rel=${real#"$root"/}
    [ "$rel" != "$real" ] || die "file is not in this repo: $kak_buffile"
}

string_literal()
{
    rest=$1
    out=
    while [ -n "$rest" ]
    do
        char=${rest%"${rest#?}"}
        rest=${rest#?}
        case "$char" in
            \\ | \")
                out="$out\\$char"
                ;;
            *)
                out="$out$char"
                ;;
        esac
    done
    printf '"%s"' "$out"
}

render()
{
    view=$1
    mode=$2
    shift 2
    rev=@
    case "$view" in
        status)
            run_jj status || jj_error status
            ;;
        log)
            if [ -n "$1" ]
            then
                run_jj log -r "$1" -T "$log_tpl" || jj_error log
            else
                run_jj log -T "$log_tpl" || jj_error log
            fi
            rev=
            ;;
        diff)
            rev=${1:-@}
            run_jj diff --git -r "$rev" || jj_error diff
            [ -n "$out" ] || out="No changes in $rev"
            ;;
        file-log)
            run_jj log -r '::@' -T "$log_tpl" "root-file:$(string_literal "$1")" || jj_error log
            rev=
            ;;
        annotate)
            run_jj file annotate -T "$annotate_tpl" -- "$1" || jj_error 'file annotate'
            rev=
            ;;
    esac
    if [ "$mode" = show ]
    then
        printf 'try %%{ buffer *jj-%s* } catch %%{ edit -scratch *jj-%s* }\n' "$view" "$view"
    fi
    emit set-option buffer jj_root "$root"
    emit set-option buffer jj_view "$view"
    emit set-option buffer jj_args "$@"
    emit set-option buffer jj_rev "$rev"
    emit set-option buffer jj_content "$out$nl"
    printf 'jj-load-content %s\n' "$mode"
    if [ "$mode" = show ]
    then
        case "$view" in
            file-log)
                printf 'set-option buffer filetype jj-log\n'
                ;;
            *)
                printf 'set-option buffer filetype jj-%s\n' "$view"
                ;;
        esac
        printf 'jj-view-keys\n'
    fi
}

action=$1
shift

case "$action" in
    show)
        find_root
        view=$1
        shift
        case "$view" in
            file-log | annotate)
                rel_path
                render "$view" show "$rel"
                ;;
            *)
                render "$view" show "$@"
                ;;
        esac
        ;;
    refresh)
        root=$kak_opt_jj_root
        [ -n "$root" ] || exit
        eval "set -- $kak_quoted_opt_jj_args"
        render "$kak_opt_jj_view" refresh "$@"
        ;;
    refresh-list)
        eval "set -- $kak_quoted_buflist"
        for buf
        do
            case "$buf" in
                '*jj-'*'*')
                    if [ "$buf" = "$kak_bufname" ]
                    then
                        printf 'try %%{ jj-refresh-if-match }\n'
                    else
                        printf 'try %%{ evaluate-commands -buffer %s jj-refresh-if-match }\n' "$(kq "$buf")"
                    fi
                    ;;
            esac
        done
        ;;
    at)
        what=$1
        if ! change=$(change_at_line "$kak_opt_jj_line_text")
        then
            change=$kak_opt_jj_rev
            [ "$kak_opt_jj_view" = status ] && change=${change:-@}
        fi
        case "$what" in
            ret)
                case "$kak_opt_jj_view" in
                    status)
                        case "$kak_opt_jj_line_text" in
                            [MAD]' '*)
                                file=${kak_opt_jj_line_text#??}
                                file=${file%"$nl"}
                                emit edit "$kak_opt_jj_root/$file"
                                exit
                                ;;
                        esac
                        ;;
                    diff)
                        printf 'jj-diff-jump\n'
                        exit
                        ;;
                esac
                what=diff
                ;;
        esac
        [ -n "$change" ] || die 'no change on this line'
        case "$what" in
            diff | edit | abandon | new | describe | squash)
                emit "jj-$what" "$change"
                ;;
            rebase)
                if [ -z "$kak_opt_jj_rebase_source" ] || [ -z "$kak_opt_jj_rebase_mode" ]
                then
                    emit set-option global jj_rebase_source "$change"
                    printf 'set-option global jj_rebase_mode ""\n'
                    printf 'enter-user-mode jj-rebase\n'
                elif [ "$change" = "$kak_opt_jj_rebase_source" ]
                then
                    printf 'jj-rebase-cancel\n'
                    emit echo 'jj: rebase cancelled'
                else
                    emit jj-rebase "$kak_opt_jj_rebase_mode" "$kak_opt_jj_rebase_source" "$change"
                fi
                ;;
            bookmark-set)
                printf 'prompt %s %%{ jj-bookmark-set %%val{text} %s }\n' "$(kq "bookmark set at $change: ")" "$change"
                ;;
        esac
        ;;
    confirm)
        msg=$1
        shift
        emit set-option global jj_confirm "$@"
        printf 'prompt %s %%{ evaluate-commands %%sh{ case "$kak_text" in y | Y | yes) echo "jj-sh %%opt{jj_confirm}" ;; *) echo "echo jj: cancelled" ;; esac } }\n' "$(kq "$msg [y/N] ")"
        ;;
    rebase-mode)
        emit set-option global jj_rebase_mode "$1"
        emit echo "jj: rebase $1 $kak_opt_jj_rebase_source; press r on the destination (r on the source cancels)"
        ;;
    jump)
        file=$kak_opt_jj_tmp
        result=$(head -n "$kak_cursor_line" "$file" | awk '
            /^diff --git / { path = ""; old = ""; hunk = 0; cur = 0; next }
            !hunk && /^--- / { old = substr($0, 5); next }
            !hunk && /^\+\+\+ / { path = substr($0, 5); next }
            /^@@ / {
                start = $0
                sub(/^@@ -[0-9,]+ \+/, "", start)
                sub(/[ ,].*/, "", start)
                line = start - 1
                cur = start
                hunk = 1
                next
            }
            /^\\/ { next }
            hunk {
                if (substr($0, 1, 1) == "-")
                {
                    cur = line + 1
                }
                else
                {
                    line++
                    cur = line
                }
            }
            END {
                if (path == "" || path == "/dev/null")
                {
                    path = old
                }
                if (cur < 1)
                {
                    cur = 1
                }
                print cur
                print path
            }')
        rm -f "$file"
        line=${result%%"$nl"*}
        path=${result#*"$nl"}
        case "$path" in
            \"*\")
                path=${path#\"}
                path=${path%\"}
                path=$(printf '%s' "$path" | sed 's/\\"/"/g; s/\\\\/\\/g')
                ;;
        esac
        case "$path" in
            a/* | b/*)
                path=${path#??}
                ;;
            *)
                die 'no file on this line'
                ;;
        esac
        emit edit "$kak_opt_jj_root/$path" "$line"
        ;;
    help)
        common='d  diff of change
e  edit change (move @)
a  abandon change
n  new change on top
D  describe change
s  squash change into parent
r  rebase: start here / complete here
b  bookmark... (s set, d delete, t track)
g  refresh
q  close
?  this help'
        case "$kak_opt_jj_view" in
            diff)
                extra='<ret>  jump to file and line'
                ;;
            annotate)
                extra='<ret>  diff of the change on this line'
                ;;
            status)
                extra='<ret>  open file on this line'
                ;;
            *)
                extra='<ret>  diff of change'
                ;;
        esac
        emit info -title "jj $kak_opt_jj_view" "$common$nl$extra"
        ;;
    describe)
        find_root
        single_change "${1:-@}"
        run_jj log --no-graph -r "$change" -T 'if(immutable, "immutable")' || jj_error log
        [ -z "$out" ] || die "$change is immutable"
        run_jj log --no-graph -r "$change" -T description || jj_error log
        dir=$(mktemp -d /tmp/kak-jj-describe.XXXXXX) || die 'cannot create temp dir'
        file=$dir/$change.jjdescription
        printf '%s\n' "$out" > "$file"
        emit edit "$file"
        emit set-option buffer jj_root "$root"
        emit set-option buffer jj_describe_rev "$change"
        emit set-option buffer jj_describe_dir "$dir"
        printf 'jj-describe-hooks\n'
        emit echo "jj: describing $change; :w to save, :db! to abort"
        ;;
    describe-save)
        root=$kak_opt_jj_root
        msg=$(cat "$kak_buffile")
        out=$(cd "$root" && printf '%s\n' "$msg" | JJ_EDITOR=false jj --no-pager --color=never describe -r "$kak_opt_jj_describe_rev" --stdin 2>"$errf") || jj_error describe
        printf 'jj-describe-close\n'
        refresh_root
        ;;
    new)
        find_root
        [ $# -gt 0 ] || set -- @
        mutate new "$@"
        ;;
    edit)
        find_root
        mutate edit "$1"
        ;;
    abandon)
        find_root
        mutate abandon "$1"
        ;;
    undo)
        find_root
        mutate undo
        ;;
    squash)
        find_root
        single_change "${1:-@}"
        run_jj log --no-graph -r "$change" -T description || jj_error log
        src=$out
        run_jj log --no-graph -r "$change-" -T description || jj_error log
        dest=$out
        if [ -z "$src" ]
        then
            mutate squash -r "$change" -u
        elif [ -z "$dest" ]
        then
            mutate squash -r "$change" -m "$src"
        else
            mutate squash -r "$change" -m "$dest$nl$nl$src"
        fi
        ;;
    rebase)
        find_root
        case "$1" in
            -s | -r | -b)
                ;;
            *)
                die "rebase mode must be -s, -r or -b, not $1"
                ;;
        esac
        printf 'jj-rebase-cancel\n'
        mutate rebase "$1" "$2" -o "$3"
        ;;
    bookmark-set)
        find_root
        [ -n "$1" ] || die 'bookmark name is empty'
        mutate bookmark set "$1" -r "${2:-@}"
        ;;
    bookmark-delete)
        find_root
        [ -n "$1" ] || die 'bookmark name is empty'
        mutate bookmark delete "exact:$(string_literal "$1")"
        ;;
    bookmark-track)
        find_root
        [ -n "$1" ] || die 'bookmark name is empty'
        mutate bookmark track "$1"
        ;;
    fetch | push)
        find_root
        if [ "$action" = push ] && [ -n "$1" ]
        then
            run_jj git push -b "exact:$(string_literal "$1")" || jj_error 'git push'
        else
            run_jj git "$action" || jj_error "git $action"
        fi
        refresh_root
        msg=$(cat "$errf")
        emit info -title "jj git $action" "${msg:-done}"
        ;;
    term)
        find_root
        emit terminal sh -c '
            cd "$1" || exit
            session=$2
            client=$3
            shift 3
            if ! "$@"
            then
                printf "\njj failed; press enter to close"
                read -r answer
            fi
            printf "evaluate-commands -client %s jj-refresh-all\n" "$client" | kak -p "$session"
        ' jj-term "$root" "$kak_session" "$kak_client" jj "$@"
        ;;
esac
