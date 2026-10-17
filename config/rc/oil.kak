declare-option -hidden str oil_lib %sh{ printf '%s/oil.sh' "${kak_source%/*}" }
declare-option -docstring 'show hidden files in oil buffers' bool oil_hidden false
declare-option -hidden str oil_dir
declare-option -hidden str oil_content
declare-option -hidden int oil_history -1
declare-option -hidden str oil_line_text
declare-option -hidden range-specs oil_conceal
declare-option -hidden str oil_token
declare-option -hidden str oil_plan_origin
declare-option -hidden str oil_label
declare-option -hidden str oil_last
declare-option -hidden str oil_notice
declare-option -hidden str oil_main_dir
declare-option -hidden str oil_flag

define-command -hidden oil-sh -params 1.. %{
    evaluate-commands %sh{
        : "$kak_buffile $kak_bufname $kak_session $kak_client $kak_quoted_buflist $kak_cursor_line $kak_history_id $kak_modified"
        : "$kak_window_height $kak_window_width $kak_window_range $kak_opt_modelinefmt"
        : "$kak_opt_oil_dir $kak_opt_oil_hidden $kak_opt_oil_history $kak_opt_oil_line_text $kak_opt_oil_token $kak_opt_oil_plan_origin $kak_opt_oil_last $kak_opt_oil_main_dir"
        sh "$kak_opt_oil_lib" -- "$@"
    }
}

define-command -hidden oil-load %{
    evaluate-commands -buffer %val{bufname} -save-regs '"' %{
        set-register '"' %opt{oil_content}
        execute-keys '%R'
    }
    set-option buffer oil_content ''
    set-option buffer oil_history %val{history_id}
    oil-conceal
}

define-command -hidden oil-conceal %{
    evaluate-commands %sh{
        if [ "$kak_history_id" = "$kak_opt_oil_history" ]
        then
            echo "set-option buffer oil_flag ''"
        else
            echo "set-option buffer oil_flag ' [+]'"
        fi
    }
    evaluate-commands -draft %{
        try %{
            execute-keys '%s^/\d+ <ret>'
            evaluate-commands %sh{
                printf 'set-option buffer oil_conceal %%val{timestamp}'
                for desc in $kak_selections_desc
                do
                    printf " '%s|'" "$desc"
                done
                printf '\n'
            }
        } catch %{
            set-option buffer oil_conceal %val{timestamp}
        }
    }
}

define-command -hidden oil-plan-show -params 1 %{
    evaluate-commands -save-regs '"' %{
        set-register '"' %opt{oil_content}
        execute-keys '%R'
    }
    set-option buffer oil_content ''
    set-option buffer oil_token %arg{1}
    set-option buffer filetype oil-plan
    map buffer normal y ': oil-sh plan-key y<ret>' -docstring 'apply the plan'
    map buffer normal n ': oil-sh plan-key n<ret>' -docstring 'cancel'
    map buffer normal q ': oil-sh plan-key n<ret>' -docstring 'cancel'
    execute-keys gg
    hook buffer NormalIdle .* %{ oil-sh plan-seen }
    hook -group oil-plan global WinDisplay .* %{
        evaluate-commands %sh{
            [ "$kak_hook_param" = '*oil-plan*' ] || echo 'oil-sh plan-key expire'
        }
    }
    echo -markup '{Information}oil: review the plan; y applies once every deletion has been on screen, n or q cancels'
}

define-command -hidden oil-at -params 1 %{
    evaluate-commands -draft %{
        execute-keys x
        set-option global oil_line_text %val{selection}
    }
    oil-sh %arg{1}
}

define-command oil -params 0..1 -docstring 'oil [<dir>]: edit a directory as a buffer (default: the current file''s directory); :w applies' %{
    oil-sh open %arg{@}
}
complete-command oil file

define-command oil-parent -docstring 'oil-parent: open oil on the current file''s directory, or go up from an oil buffer' %{
    oil-sh parent
}

define-command oil-back -docstring 'oil-back: return to the most recently used oil buffer' %{
    oil-sh back
}

define-command -hidden oil-notice -params 1 %{
    set-option global oil_notice %arg{1}
    hook -once global NormalIdle .* %{ echo %opt{oil_notice} }
}

define-command oil-apply -docstring 'oil-apply: apply the edits in every oil buffer, after confirmation' %{
    oil-sh apply-collect
}

define-command oil-refresh -docstring 'oil-refresh: reload the current oil buffer, discarding its edits' %{
    oil-at refresh
}

define-command oil-toggle-hidden -docstring 'oil-toggle-hidden: show or hide dotfiles in the current oil buffer' %{
    oil-at toggle-hidden
}

define-command -hidden oil-refresh-all %{
    oil-sh refresh-list
}

define-command -hidden oil-buffer-setup %{
    set-option buffer filetype oil
    alias buffer w oil-apply
    map buffer normal <ret> ': oil-at enter<ret>' -docstring 'open file or directory'
    map buffer normal <minus> ': oil-sh up<ret>' -docstring 'go to the parent directory'
    map buffer normal <a-.> ': oil-toggle-hidden<ret>' -docstring 'toggle hidden files'
    map buffer normal <c-l> ': oil-refresh<ret>' -docstring 'refresh, discarding edits'
    hook -group oil buffer NormalIdle .* oil-conceal
    hook -group oil buffer InsertIdle .* oil-conceal
    hook -group oil buffer WinDisplay .* %{ set-option global oil_last %val{bufname} }
}

hook -group oil global RuntimeError "\d+:\d+: '(?:e|edit)!?': (.+): is a directory" %{
    oil-sh edit-dir %val{hook_param_capture_1}
}

hook -group oil -once global ClientCreate .* %{
    oil-sh startup
}

hook -group oil global KakEnd .* %{
    oil-sh cleanup
}

add-highlighter shared/oil group
add-highlighter shared/oil/ regex '^/\d+ ' 0:comment
add-highlighter shared/oil/ regex '^(?:/\d+ )?([^\n]*/)$' 1:function

add-highlighter shared/oil-plan group
add-highlighter shared/oil-plan/ regex '^rm [^\n]*' 0:Error
add-highlighter shared/oil-plan/ regex '^warning: [^\n]*' 0:yellow
add-highlighter shared/oil-plan/ regex '\A[^\n]*' 0:title

hook -group oil global WinSetOption filetype=oil-plan %{
    add-highlighter window/oil-plan ref oil-plan
    add-highlighter window/oil-plan-wrap wrap -word -marker '↪ '
    hook -once -always window WinSetOption filetype=.* %{
        remove-highlighter window/oil-plan
        remove-highlighter window/oil-plan-wrap
    }
}

hook -group oil global WinSetOption filetype=oil %{
    add-highlighter window/oil ref oil
    add-highlighter window/oil-conceal replace-ranges oil_conceal
    oil-sh modeline
    hook -once -always window WinSetOption filetype=.* %{
        remove-highlighter window/oil
        remove-highlighter window/oil-conceal
        unset-option window modelinefmt
    }
}
