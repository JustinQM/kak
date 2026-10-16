declare-option -hidden str jj_lib %sh{ printf '%s/jj.sh' "${kak_source%/*}" }
declare-option -hidden str jj_root
declare-option -hidden str jj_view
declare-option -hidden str-list jj_args
declare-option -hidden str jj_rev
declare-option -hidden str jj_content
declare-option -hidden int jj_line
declare-option -hidden str jj_line_text
declare-option -hidden str jj_tmp
declare-option -hidden str jj_refresh_root
declare-option -hidden str jj_rebase_source
declare-option -hidden str jj_rebase_mode
declare-option -hidden str-list jj_confirm
declare-option -hidden str jj_describe_rev
declare-option -hidden str jj_describe_dir

define-command -hidden jj-sh -params 1.. %{
    evaluate-commands %sh{
        : "$kak_buffile $kak_bufname $kak_cursor_line $kak_session $kak_client $kak_quoted_buflist"
        : "$kak_opt_jj_root $kak_opt_jj_view $kak_opt_jj_rev $kak_quoted_opt_jj_args $kak_opt_jj_line_text $kak_opt_jj_tmp"
        : "$kak_opt_jj_rebase_source $kak_opt_jj_rebase_mode $kak_opt_jj_describe_rev"
        sh "$kak_opt_jj_lib" "$@"
    }
}

define-command -hidden jj-load-content -params 1 %{
    set-option buffer jj_line %val{cursor_line}
    evaluate-commands -save-regs '"' %{
        set-register '"' %opt{jj_content}
        execute-keys '%R'
    }
    set-option buffer jj_content ''
    evaluate-commands %sh{
        if [ "$1" = refresh ]
        then
            echo 'try %{ execute-keys "%opt{jj_line}g" }'
        else
            echo 'execute-keys gg'
        fi
    }
}

define-command -hidden jj-confirm -params 2.. %{
    jj-sh confirm %arg{@}
}

define-command jj-status -docstring 'jj-status: show jj status' %{
    jj-sh show status
}

define-command jj-log -params 0..1 -docstring 'jj-log [<revset>]: show jj log' %{
    jj-sh show log %arg{@}
}

define-command jj-diff -params 0..1 -docstring 'jj-diff [<rev>]: show the diff of a change (default @)' %{
    jj-sh show diff %arg{@}
}

define-command jj-file-log -docstring 'jj-file-log: show the changes touching the current file' %{
    jj-sh show file-log
}

define-command jj-annotate -docstring 'jj-annotate: show which change last touched each line of the current file' %{
    jj-sh show annotate
}

define-command jj-describe -params 0..1 -docstring 'jj-describe [<rev>]: edit the description of a change (default @); :w saves' %{
    jj-sh describe %arg{@}
}

define-command jj-new -params 0.. -docstring 'jj-new [<rev>...]: create a new change on top of the given changes (default @)' %{
    jj-sh new %arg{@}
}

define-command jj-edit -params 1 -docstring 'jj-edit <rev>: make <rev> the working copy' %{
    jj-sh edit %arg{1}
}

define-command jj-abandon -params 0..1 -docstring 'jj-abandon [<rev>]: abandon a change (default @), after confirmation' %{
    evaluate-commands %sh{
        if [ -n "$1" ]
        then
            echo 'jj-confirm "Abandon %arg{1}?" abandon %arg{1}'
        else
            echo 'jj-confirm "Abandon @?" abandon @'
        fi
    }
}

define-command jj-undo -docstring 'jj-undo: undo the last jj operation' %{
    jj-sh undo
}

define-command jj-squash -params 0..1 -docstring 'jj-squash [<rev>]: squash a change into its parent (default @)' %{
    jj-sh squash %arg{@}
}

define-command jj-rebase -params 3 -docstring 'jj-rebase <-s|-r|-b> <source> <destination>: rebase onto destination' %{
    jj-sh rebase %arg{@}
}

define-command -hidden jj-rebase-cancel %{
    set-option global jj_rebase_source ''
    set-option global jj_rebase_mode ''
}

define-command jj-bookmark-set -params 1..2 -docstring 'jj-bookmark-set <name> [<rev>]: point a bookmark at a change (default @)' %{
    jj-sh bookmark-set %arg{@}
}

define-command jj-bookmark-delete -params 1 -docstring 'jj-bookmark-delete <name>: delete a bookmark, after confirmation' %{
    jj-confirm "Delete bookmark %arg{1}?" bookmark-delete %arg{1}
}

define-command jj-bookmark-track -params 1 -docstring 'jj-bookmark-track <name@remote>: track a remote bookmark' %{
    jj-sh bookmark-track %arg{1}
}

define-command jj-fetch -docstring 'jj-fetch: jj git fetch' %{
    jj-sh fetch
}

define-command jj-push -params 0..1 -docstring 'jj-push [<bookmark>]: jj git push, after confirmation' %{
    evaluate-commands %sh{
        if [ -n "$1" ]
        then
            echo 'jj-confirm "Push bookmark %arg{1}?" push %arg{1}'
        else
            echo 'jj-confirm "Push to the remote?" push'
        fi
    }
}

define-command jj-squash-interactive -params 0..1 -docstring 'jj-squash-interactive [<rev>]: jj squash -i in a terminal (default @)' %{
    jj-sh term squash -i --tool :builtin -r %sh{ printf '%s' "${1:-@}" }
}

define-command jj-split -params 0..1 -docstring 'jj-split [<rev>]: jj split in a terminal (default @)' %{
    jj-sh term split -i --tool :builtin -r %sh{ printf '%s' "${1:-@}" }
}

define-command jj-resolve -params 0..1 -docstring 'jj-resolve [<rev>]: jj resolve in a terminal (default @)' %{
    jj-sh term resolve --tool :builtin -r %sh{ printf '%s' "${1:-@}" }
}

define-command jj-refresh -docstring 'jj-refresh: refresh all jj view buffers' %{
    jj-refresh-all
}

define-command -hidden jj-refresh-all %{
    jj-sh refresh-list
}

define-command -hidden jj-refresh-if-match %{
    evaluate-commands %sh{
        if [ -z "$kak_opt_jj_refresh_root" ] || [ "$kak_opt_jj_refresh_root" = "$kak_opt_jj_root" ]
        then
            echo 'jj-sh refresh'
        fi
    }
}

define-command -hidden jj-at -params 1 %{
    evaluate-commands -draft %{
        execute-keys x
        set-option global jj_line_text %val{selection}
    }
    jj-sh at %arg{1}
}

define-command -hidden jj-diff-jump %{
    set-option global jj_tmp %sh{ mktemp "${TMPDIR:-/tmp}/kak-jj-diff.XXXXXX" }
    write -force %opt{jj_tmp}
    jj-sh jump
}

define-command -hidden jj-describe-hooks %{
    hook -group jj-describe buffer BufWritePost .* %{ jj-sh describe-save }
    hook -group jj-describe -always buffer BufClose .* %{
        nop %sh{
            case "$kak_opt_jj_describe_dir" in
                */kak-jj-describe.*)
                    rm -rf "$kak_opt_jj_describe_dir"
                    ;;
            esac
        }
    }
}

define-command -hidden jj-describe-close %{
    delete-buffer
}

define-command -hidden jj-view-keys %{
    map buffer normal d ': jj-at diff<ret>'
    map buffer normal e ': jj-at edit<ret>'
    map buffer normal a ': jj-at abandon<ret>'
    map buffer normal n ': jj-at new<ret>'
    map buffer normal D ': jj-at describe<ret>'
    map buffer normal s ': jj-at squash<ret>'
    map buffer normal r ': jj-at rebase<ret>'
    map buffer normal b ': enter-user-mode jj-bookmark<ret>'
    map buffer normal g ': jj-sh refresh<ret>'
    map buffer normal q ': delete-buffer<ret>'
    map buffer normal ? ': jj-sh help<ret>'
    map buffer normal <ret> ': jj-at ret<ret>'
}

declare-user-mode jj
map global user j ': enter-user-mode jj<ret>' -docstring 'jj...'
map global jj s ': jj-status<ret>' -docstring 'status'
map global jj l ': jj-log<ret>' -docstring 'log'
map global jj d ': jj-diff<ret>' -docstring 'diff of @'
map global jj f ': jj-file-log<ret>' -docstring 'log of this file'
map global jj a ': jj-annotate<ret>' -docstring 'annotate this file'
map global jj D ': jj-describe<ret>' -docstring 'describe @'
map global jj n ': jj-new<ret>' -docstring 'new change'
map global jj u ': jj-undo<ret>' -docstring 'undo'
map global jj F ': jj-fetch<ret>' -docstring 'git fetch'
map global jj P ': jj-push<ret>' -docstring 'git push'
map global jj i ': jj-squash-interactive<ret>' -docstring 'squash -i (terminal)'
map global jj S ': jj-split<ret>' -docstring 'split (terminal)'
map global jj R ': jj-resolve<ret>' -docstring 'resolve (terminal)'

declare-user-mode jj-bookmark
map global jj-bookmark s ': jj-at bookmark-set<ret>' -docstring 'set bookmark here'
map global jj-bookmark d ': prompt "bookmark delete: " %{ jj-bookmark-delete %val{text} }<ret>' -docstring 'delete bookmark'
map global jj-bookmark t ': prompt "bookmark track (name@remote): " %{ jj-bookmark-track %val{text} }<ret>' -docstring 'track remote bookmark'

declare-user-mode jj-rebase
map global jj-rebase s ': jj-sh rebase-mode -s<ret>' -docstring 'source and descendants (-s)'
map global jj-rebase r ': jj-sh rebase-mode -r<ret>' -docstring 'only this revision (-r)'
map global jj-rebase b ': jj-sh rebase-mode -b<ret>' -docstring 'whole branch (-b)'

hook -group jj global FocusIn .* %{ try %{ jj-refresh-all } }

add-highlighter shared/jj-log group
add-highlighter shared/jj-log/ regex '\b([k-z]{8,}) ([0-9a-f]{8,})\b' 1:value 2:comment
add-highlighter shared/jj-log/ regex '^[^\w\n]*(@)' 1:keyword
add-highlighter shared/jj-log/ regex '^[^\w\n]*(◆)' 1:meta
add-highlighter shared/jj-log/ regex '\[[^\]\n]+\]' 0:function
add-highlighter shared/jj-log/ regex '\((?:conflict|divergent)\)' 0:Error
add-highlighter shared/jj-log/ regex '\((?:empty|no description)\)' 0:comment
add-highlighter shared/jj-log/ regex '· ([^ \n]+) ([^\n]*)$' 1:type 2:comment

add-highlighter shared/jj-status group
add-highlighter shared/jj-status/ regex '^Working copy changes:$' 0:keyword
add-highlighter shared/jj-status/ regex '^(?:Warning: )?There are unresolved conflicts at these paths:$' 0:Error
add-highlighter shared/jj-status/ regex '^The working copy has no changes\.$' 0:comment
add-highlighter shared/jj-status/ regex '^(Working copy|Parent commit) *\(@-?\) *:' 0:keyword
add-highlighter shared/jj-status/ regex '\b([k-z]{8,}) ([0-9a-f]{8,})\b' 1:value 2:comment
add-highlighter shared/jj-status/ regex '^(A) ' 1:string
add-highlighter shared/jj-status/ regex '^(M) ' 1:type
add-highlighter shared/jj-status/ regex '^(D) ' 1:Error
add-highlighter shared/jj-status/ regex '^([RC]) ' 1:meta
add-highlighter shared/jj-status/ regex '\(conflict\)|\bconflict\b' 0:Error
add-highlighter shared/jj-status/ regex '\((?:empty|no description set)\)' 0:comment

add-highlighter shared/jj-annotate group
add-highlighter shared/jj-annotate/ regex '^([k-z]{8,}) ([0-9a-f]{8,}) +(\d+):' 1:value 2:comment 3:LineNumbers

hook -group jj global WinSetOption filetype=jj-diff %{
    require-module diff
    add-highlighter window/jj ref diff
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/jj }
}

hook -group jj global WinSetOption filetype=(jj-log|jj-status|jj-annotate) %{
    add-highlighter window/jj ref %val{hook_param_capture_1}
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/jj }
}
