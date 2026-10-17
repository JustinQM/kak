LC_ALL=C
export LC_ALL
unset CDPATH

nl='
'
tab=$(printf '\t')

usage='usage: oil.sh [--state-dir DIR] [--session NAME] COMMAND ...

commands:
  list [--hidden] DIR                       print the listing of DIR, assigning IDs
  apply [--dry-run] DIR FILE [DIR FILE]...  apply edited listings (FILE holds the edited listing of DIR)

The state dir defaults to /tmp/kak-oil.SESSION. Both can also be set with
$OIL_STATE_DIR and $OIL_SESSION; inside Kakoune $kak_session is used.'

plan_awk='
function err(msg)
{
    if (!(msg in seen_err))
    {
        seen_err[msg] = 1
        errs[++nerr] = msg
    }
}

function join(d, n)
{
    return d == "/" ? "/" n : d "/" n
}

function parent(p)
{
    sub(/\/[^\/]*$/, "", p)
    return p == "" ? "/" : p
}

function depth(p)
{
    return gsub(/\//, "/", p)
}

function show(p)
{
    if (home != "" && (p == home || substr(p, 1, length(home) + 1) == home "/"))
    {
        return "~" substr(p, length(home) + 1)
    }
    return p
}

function show_dir(p)
{
    return p == "/" ? "/" : show(p) "/"
}

function sort_by(arr, key, n,    i, j, v)
{
    for (i = 2; i <= n; i++)
    {
        v = arr[i]
        j = i - 1
        while (j > 0 && key[arr[j]] > key[v])
        {
            arr[j + 1] = arr[j]
            j--
        }
        arr[j + 1] = v
    }
}

function read_ids(f,    l, i, id, r)
{
    while ((getline l < f) > 0)
    {
        i = index(l, "\t")
        id = substr(l, 1, i - 1) + 0
        r = substr(l, i + 1)
        typ[id] = substr(r, 1, 1)
        path[id] = substr(r, 3)
    }
    close(f)
}

function check_name(name, where,    n, parts, i)
{
    if (name == "")
    {
        err(where ": empty name")
        return 0
    }
    n = split(name, parts, "/")
    for (i = 1; i <= n; i++)
    {
        if (parts[i] == "" || parts[i] == "." || parts[i] == "..")
        {
            err(where ": invalid name: " name)
            return 0
        }
    }
    return 1
}

function warn(msg)
{
    if (!(msg in seen_warn))
    {
        seen_warn[msg] = 1
        warns[++nwarn] = msg
    }
}

function live_id(d)
{
    return d ~ /^[0-9]+$/ && (d + 0) in path && sprintf("%04d", d + 0) == d
}

function check_lookalike(line, where,    s, d)
{
    if (match(line, /^[0-9]+ /))
    {
        d = substr(line, 1, RLENGTH - 1)
        if (live_id(d))
        {
            warn(where ": \"" line "\" begins like ID /" d " (" show(path[d + 0]) "), it will be created as a new entry")
        }
    }
    s = line
    while (match(s, /\/[0-9]+ /))
    {
        d = substr(s, RSTART + 1, RLENGTH - 2)
        if (live_id(d))
        {
            warn(where ": \"" line "\" contains ID /" d " (" show(path[d + 0]) "), it will be created as a new entry")
        }
        s = substr(s, RSTART + RLENGTH)
    }
}

function parse_line(b, ln, line,    where, id, name, isdir)
{
    if (line ~ /^[ \t]*$/)
    {
        return
    }
    where = "line " ln " of " show_dir(bdir[b])
    if (substr(line, 1, 1) == "/")
    {
        if (!match(line, /^\/[0-9]+ /))
        {
            if (match(line, /^\/[0-9]+/) && live_id(substr(line, 2, RLENGTH - 1)))
            {
                err(where ": mangled ID: " line)
            }
            else
            {
                err(where ": not a valid ID, and names cannot start with /: " line)
            }
            return
        }
        id = substr(line, 2, RLENGTH - 2) + 0
        name = substr(line, RLENGTH + 1)
        if (!(id in path))
        {
            err(where ": unknown ID: " line)
            return
        }
        isdir = sub(/\/$/, "", name)
        if (!check_name(name, where))
        {
            return
        }
        if (isdir && typ[id] != "d")
        {
            err(where ": " show(path[id]) " is a file, it cannot become a directory")
            return
        }
        nocc[id]++
        occ[id, nocc[id]] = join(bdir[b], name)
        occdir[id, nocc[id]] = bdir[b]
        return
    }
    check_lookalike(line, where)
    name = line
    isdir = sub(/\/$/, "", name)
    if (!check_name(name, where))
    {
        return
    }
    nnew++
    newpath[nnew] = join(bdir[b], name)
    newdir[nnew] = isdir
    newbuf[nnew] = bdir[b]
}

function read_manifest(f,    d, lf, bf, l, ln)
{
    while ((getline d < f) > 0)
    {
        getline lf < f
        getline bf < f
        nb++
        bdir[nb] = d
        if ((getline l < lf) > 0 && l == d)
        {
            while ((getline l < lf) > 0)
            {
                listed[l + 0] = 1
            }
        }
        close(lf)
        ln = 0
        while ((getline l < bf) > 0)
        {
            parse_line(nb, ++ln, l)
        }
        close(bf)
    }
    close(f)
}

function claim(t, kind)
{
    if (t in claimed)
    {
        if (claimed[t] == "stay" || kind == "stay")
        {
            err("already exists: " show(t))
        }
        else
        {
            err("duplicate target: " show(t))
        }
    }
    claimed[t] = kind
}

function under(p, d)
{
    return p == d || d == "/" || substr(p, 1, length(d) + 1) == d "/"
}

function add_op(kind, src, dst, dir)
{
    nops++
    okind[nops] = kind
    osrc[nops] = src
    odst[nops] = dst
    odir[nops] = dir
    if (dst != "")
    {
        claim(dst, kind)
        dstop[dst] = nops
    }
    if (kind == "mv" || kind == "rm")
    {
        freed[src] = 1
    }
}

function build_ops(    id, k, n, list, src, prim, j, t)
{
    n = 0
    for (id in listed)
    {
        if (!(id in nocc))
        {
            list[++n] = id + 0
        }
    }
    for (id in nocc)
    {
        list[++n] = id + 0
    }
    for (k = 1; k <= n; k++)
    {
        numkey[list[k]] = list[k]
    }
    sort_by(list, numkey, n)
    for (k = 1; k <= n; k++)
    {
        id = list[k]
        src = path[id]
        if ((id in listed) && !(id in nocc))
        {
            add_op("rm", src, "", "")
            continue
        }
        prim = 0
        if (id in listed)
        {
            for (j = 1; j <= nocc[id]; j++)
            {
                if (occ[id, j] == src)
                {
                    prim = j
                    break
                }
            }
            if (!prim)
            {
                prim = 1
            }
        }
        for (j = 1; j <= nocc[id]; j++)
        {
            t = occ[id, j]
            if (j == prim)
            {
                if (t == src)
                {
                    claim(t, "stay")
                }
                else
                {
                    add_op("mv", src, t, occdir[id, j])
                }
            }
            else if (!(id in listed) && t == src)
            {
                claim(t, "stay")
            }
            else
            {
                add_op("cp", src, t, occdir[id, j])
            }
        }
    }
    for (k = 1; k <= nnew; k++)
    {
        add_op(newdir[k] ? "mkdir" : "touch", "", newpath[k], newbuf[k])
    }
}

function query(p)
{
    if (!(p in queried))
    {
        queried[p] = 1
        print p
    }
}

function write_query(    i, a)
{
    for (i = 1; i <= nops; i++)
    {
        if (osrc[i] != "")
        {
            query(osrc[i])
        }
        if (odst[i] != "")
        {
            a = odst[i]
            query(a)
            while (a != "/")
            {
                a = parent(a)
                query(a)
            }
        }
    }
}

function read_facts(f,    l)
{
    while ((getline l < f) > 0)
    {
        fact[substr(l, 2)] = substr(l, 1, 1)
    }
    close(f)
}

function makes_dir(i)
{
    return okind[i] == "mkdir" || (okind[i] != "touch" && fact[osrc[i]] == "d")
}

function validate(    i, n, t, a, creating)
{
    n = nops
    for (i = 1; i <= n; i++)
    {
        if (osrc[i] != "" && fact[osrc[i]] == "-")
        {
            err("no longer exists: " show(osrc[i]) " (refresh and try again)")
        }
        t = odst[i]
        if (t == "")
        {
            continue
        }
        if (fact[t] != "-" && !(t in freed))
        {
            err("already exists: " show(t))
        }
        if (okind[i] == "mv" && under(t, osrc[i]))
        {
            err("cannot move " show(osrc[i]) " into itself")
            continue
        }
        a = t
        creating = 1
        while (a != "/")
        {
            a = parent(a)
            if (a in dstop)
            {
                if (!makes_dir(dstop[a]))
                {
                    err(show(t) ": " show(a) " is not a directory")
                    break
                }
                creating = 0
            }
            else if (a in freed && under(odir[i], a))
            {
                err(show(t) ": " show(a) " is being moved or removed")
                break
            }
            else if (creating)
            {
                if (a in freed)
                {
                    if (!(a in implicit))
                    {
                        implicit[a] = 1
                        nimpl++
                        impl[nimpl] = a
                    }
                }
                else if (fact[a] == "d")
                {
                    creating = 0
                }
                else if (fact[a] == "f")
                {
                    err(show(t) ": " show(a) " is not a directory")
                    break
                }
                else if (!(a in implicit))
                {
                    implicit[a] = 1
                    nimpl++
                    impl[nimpl] = a
                }
            }
        }
    }
    for (i = 1; i <= nimpl; i++)
    {
        nops++
        okind[nops] = "mkdir"
        odst[nops] = impl[i]
        dstop[impl[i]] = nops
    }
}

function tmp_for(src,    a, top)
{
    top = ""
    a = src
    while (a != "/")
    {
        if (a in freed)
        {
            top = a
        }
        a = parent(a)
    }
    if (top == "")
    {
        top = src
    }
    ntmp++
    return join(parent(top), ".oil-tmp." token "." ntmp)
}

function rec(op, a, b)
{
    printf "%s\n%s\n%s\n", op, a, b > planf
}

function line(s)
{
    print s > sumf
    nsum++
}

function src_disp(i)
{
    return fact[osrc[i]] == "d" ? show_dir(osrc[i]) : show(osrc[i])
}

function write_plan(    i, n, order, key, tmp, k, kinds, nk, count, head)
{
    planf = ENVIRON["OIL_PLAN"]
    sumf = ENVIRON["OIL_SUMMARY"]
    movf = ENVIRON["OIL_MOVED"]
    printf "" > planf
    printf "" > sumf
    printf "" > movf
    for (i = 1; i <= nops; i++)
    {
        if (okind[i] == "cp")
        {
            tmp[i] = tmp_for(osrc[i])
            rec("cp", osrc[i], tmp[i])
        }
    }
    n = 0
    for (i = 1; i <= nops; i++)
    {
        if (okind[i] == "mv" || okind[i] == "rm")
        {
            order[++n] = i
            key[i] = -depth(osrc[i])
        }
    }
    sort_by(order, key, n)
    for (k = 1; k <= n; k++)
    {
        i = order[k]
        tmp[i] = tmp_for(osrc[i])
        rec("mv", osrc[i], tmp[i])
    }
    n = 0
    for (i = 1; i <= nops; i++)
    {
        if (odst[i] != "")
        {
            order[++n] = i
            key[i] = depth(odst[i])
        }
    }
    sort_by(order, key, n)
    for (k = 1; k <= n; k++)
    {
        i = order[k]
        if (okind[i] == "mkdir" || okind[i] == "touch")
        {
            rec(okind[i], odst[i], "")
        }
        else
        {
            rec("put", tmp[i], odst[i])
        }
    }
    for (i = 1; i <= nops; i++)
    {
        if (okind[i] == "rm")
        {
            rec("rm", tmp[i], "")
        }
        if (okind[i] == "mv")
        {
            printf "%s\n%s\n", osrc[i], odst[i] > movf
        }
    }
    nk = split("mkdir touch mv cp rm", kinds, " ")
    head = ""
    for (k = 1; k <= nk; k++)
    {
        count = 0
        for (i = 1; i <= nops; i++)
        {
            if (okind[i] == kinds[k])
            {
                count++
            }
        }
        if (count)
        {
            head = head (head == "" ? "" : ", ") count " " kinds[k]
        }
    }
    if (head == "")
    {
        return
    }
    line(head)
    for (i = 1; i <= nops; i++)
    {
        if (okind[i] == "rm")
        {
            line("rm     " src_disp(i))
        }
    }
    for (i = 1; i <= nwarn; i++)
    {
        line("warning: " warns[i])
    }
    for (k = 1; k <= n; k++)
    {
        i = order[k]
        if (okind[i] == "mkdir")
        {
            line("mkdir  " show_dir(odst[i]))
        }
    }
    for (k = 1; k <= n; k++)
    {
        i = order[k]
        if (okind[i] == "touch")
        {
            line("touch  " show(odst[i]))
        }
    }
    for (i = 1; i <= nops; i++)
    {
        if (okind[i] == "mv" || okind[i] == "cp")
        {
            line(okind[i] "     " src_disp(i) "  ->  " (fact[osrc[i]] == "d" ? show_dir(odst[i]) : show(odst[i])))
        }
    }
}

function write_errors(    i, f)
{
    f = ENVIRON["OIL_ERRORS"]
    for (i = 1; i <= nerr; i++)
    {
        print errs[i] > f
    }
    close(f)
}

function main()
{
    home = ENVIRON["HOME"]
    sub(/\/+$/, "", home)
    token = ENVIRON["OIL_TOKEN"]
    read_ids(ENVIRON["OIL_IDS"])
    read_manifest(ENVIRON["OIL_MANIFEST"])
    build_ops()
    if (nerr)
    {
        write_errors()
        exit 1
    }
    if (mode == "query")
    {
        write_query()
        exit 0
    }
    read_facts(ENVIRON["OIL_FACTS"])
    validate()
    if (nerr)
    {
        write_errors()
        exit 1
    }
    write_plan()
    exit 0
}

BEGIN {
    main()
}
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
    if [ "$kak_mode" = 1 ]
    then
        emit fail "oil: $1"
    else
        printf 'oil: %s\n' "$1" >&2
    fi
    exit 1
}

init_state()
{
    if [ -z "$state_dir" ]
    then
        [ -n "$session" ] || die 'no session: pass --session or --state-dir'
        case "$session" in
            */* | . | ..)
                die "bad session name: $session"
                ;;
        esac
        state_dir=/tmp/kak-oil.$session
    fi
    if [ ! -d "$state_dir" ]
    then
        mkdir -p -- "${state_dir%/*}" 2>/dev/null
        mkdir -m 700 -- "$state_dir" 2>/dev/null || [ -d "$state_dir" ] || die "cannot create $state_dir"
    fi
    [ -O "$state_dir" ] || die "$state_dir is not owned by you"
    mkdir -p "$state_dir/listed" || die "cannot write to $state_dir"
    [ -f "$state_dir/ids" ] || : > "$state_dir/ids"
    tmp=$(mktemp -d "$state_dir/tmp.XXXXXX") || die "cannot write to $state_dir"
    trap 'rm -rf "$tmp"' EXIT
}

canon()
{
    p=$1
    case "$p" in
        '~')
            p=$HOME
            ;;
        '~/'*)
            p=$HOME/${p#'~/'}
            ;;
    esac
    case "$p" in
        /*)
            ;;
        *)
            p=$PWD/$p
            ;;
    esac
    case "$p" in
        *"$nl"*)
            return 1
            ;;
    esac
    (cd -- "$p" 2>/dev/null && pwd)
}

listed_file()
{
    key=$(printf '%s' "$1" | cksum)
    printf '%s/listed/%s' "$state_dir" "$(printf '%s' "$key" | tr ' ' .)"
}

named()
{
    case "$1" in
        /)
            printf '*oil:/*'
            ;;
        *)
            printf '*oil:%s/*' "$1"
            ;;
    esac
}

oil_label()
{
    case "$1" in
        /)
            printf 'oil:/'
            ;;
        *)
            printf 'oil:%s/' "$1"
            ;;
    esac
}

name_dir()
{
    case "$1" in
        '*oil*')
            [ -n "$kak_opt_oil_main_dir" ] || return 1
            printf '%s' "$kak_opt_oil_main_dir"
            ;;
        '*oil:/'*'*')
            nd=${1#'*oil:'}
            nd=${nd%'*'}
            nd=${nd%/}
            printf '%s' "${nd:-/}"
            ;;
        *)
            return 1
            ;;
    esac
}

exists()
{
    [ -e "$1" ] || [ -L "$1" ]
}

make_listing()
{
    dir=$1
    [ -d "$dir" ] || die "no such directory: $dir"
    [ -r "$dir" ] && [ -x "$dir" ] || die "cannot read directory: $dir"
    base=${dir%/}
    if [ "$2" = true ]
    then
        set -- "$base"/* "$base"/.[!.]* "$base"/..?*
    else
        set -- "$base"/*
    fi
    for p
    do
        exists "$p" || continue
        name=${p#"$base"/}
        case "$name" in
            *"$nl"*)
                continue
                ;;
        esac
        if [ -d "$p" ]
        then
            printf 'd\t%s\n' "$name"
        else
            printf 'f\t%s\n' "$name"
        fi
    done | sort > "$tmp/entries"
    lf=$(listed_file "$dir")
    OIL_DIR=$dir OIL_IDS=$state_dir/ids OIL_NEWIDS=$tmp/ids OIL_LISTED=$tmp/listed awk '
        function join(d, n)
        {
            return d == "/" ? "/" n : d "/" n
        }
        BEGIN {
            dir = ENVIRON["OIL_DIR"]
            idsf = ENVIRON["OIL_IDS"]
            listedf = ENVIRON["OIL_LISTED"]
            print dir > listedf
            while ((getline l < idsf) > 0)
            {
                i = index(l, "\t")
                id = substr(l, 1, i - 1) + 0
                r = substr(l, i + 1)
                typ[id] = substr(r, 1, 1)
                pth[id] = substr(r, 3)
                idof[pth[id]] = id
                if (id > max)
                {
                    max = id
                }
            }
            close(idsf)
        }
        {
            t = substr($0, 1, 1)
            name = substr($0, 3)
            p = join(dir, name)
            if (p in idof)
            {
                id = idof[p]
            }
            else
            {
                id = ++max
                idof[p] = id
                pth[id] = p
            }
            typ[id] = t
            printf "/%04d %s%s\n", id, name, t == "d" ? "/" : ""
            print id > listedf
        }
        END {
            f = ENVIRON["OIL_NEWIDS"]
            printf "" > f
            for (id = 1; id <= max; id++)
            {
                if (id in pth)
                {
                    printf "%d\t%s\t%s\n", id, typ[id], pth[id] > f
                }
            }
        }
    ' "$tmp/entries" > "$tmp/listing" || die "listing failed: $dir"
    mv -f "$tmp/ids" "$state_dir/ids" && mv -f "$tmp/listed" "$lf" || die "cannot write to $state_dir"
}

id_path()
{
    OIL_WANT=$1 awk '
        {
            i = index($0, "\t")
            if (substr($0, 1, i - 1) + 0 == ENVIRON["OIL_WANT"] + 0)
            {
                print substr($0, i + 3)
                exit
            }
        }
    ' "$state_dir/ids"
}

line_id()
{
    case "$1" in
        /[0-9]*' '*)
            id=${1#/}
            id=${id%%' '*}
            case "$id" in
                *[!0-9]*)
                    return 1
                    ;;
            esac
            printf '%s' "$id"
            ;;
        *)
            return 1
            ;;
    esac
}

plan()
{
    rm -f "$tmp/errors"
    : > "$tmp/plan"
    : > "$tmp/summary"
    : > "$tmp/moved"
    export OIL_IDS="$state_dir/ids" OIL_MANIFEST="$tmp/manifest" OIL_FACTS="$tmp/facts" OIL_ERRORS="$tmp/errors"
    export OIL_PLAN="$tmp/plan" OIL_SUMMARY="$tmp/summary" OIL_MOVED="$tmp/moved" OIL_TOKEN="$token"
    awk -v mode=query "$plan_awk" > "$tmp/query" || return 1
    while IFS= read -r p
    do
        if [ -d "$p" ]
        then
            printf 'd%s\n' "$p"
        elif exists "$p"
        then
            printf 'f%s\n' "$p"
        else
            printf -- '-%s\n' "$p"
        fi
    done < "$tmp/query" > "$tmp/facts"
    awk -v mode=plan "$plan_awk" || return 1
}

plan_errors()
{
    if [ -s "$tmp/errors" ]
    then
        cat "$tmp/errors"
    else
        echo 'planning failed'
    fi
}

run_plan()
{
    while IFS= read -r op && IFS= read -r a && IFS= read -r b
    do
        case "$op" in
            cp)
                ! exists "$b" || { step_error "temporary name already exists: $b"; return 1; }
                cp -RP -- "$a" "$b" 2>"$tmp/err" || { step_error "cp $a: $(cat "$tmp/err")"; return 1; }
                ;;
            mv | put)
                ! exists "$b" || { step_error "already exists: $b"; return 1; }
                mv -- "$a" "$b" 2>"$tmp/err" || { step_error "mv $a $b: $(cat "$tmp/err")"; return 1; }
                ;;
            mkdir)
                mkdir -- "$a" 2>"$tmp/err" || { step_error "mkdir $a: $(cat "$tmp/err")"; return 1; }
                ;;
            touch)
                (set -C; : > "$a") 2>"$tmp/err" || { step_error "touch $a: $(cat "$tmp/err")"; return 1; }
                ;;
            rm)
                rm -rf -- "$a" 2>"$tmp/err" || { step_error "rm $a: $(cat "$tmp/err")"; return 1; }
                ;;
        esac
    done < "$1"
}

step_error()
{
    msg=$1
    left=$(awk -v tok=".oil-tmp.$token." 'NR % 3 != 1 && index($0, tok) { print }' "$plan_file" | sort -u | while IFS= read -r p
    do
        exists "$p" && printf '%s\n' "$p"
    done)
    if [ -n "$left" ]
    then
        msg="$msg${nl}these temporaries were left behind:$nl$left"
    fi
    printf '%s\n' "$msg" > "$tmp/exec-error"
}

box_fits()
{
    [ -n "$kak_window_height" ] && [ -n "$kak_window_width" ] || return 1
    awk -v h="$kak_window_height" -v w="$kak_window_width" '
        {
            gsub(/\t/, "        ")
            if (length($0) > max)
            {
                max = length($0)
            }
        }
        END {
            exit !(NR + 4 <= h && max + 4 <= w)
        }
    ' "$1"
}

mark_seen()
{
    set -- $kak_window_range
    touch "$state_dir/plan.seen"
    awk -v top="${1:-0}" -v h="${3:-0}" -v w="${4:-0}" '
        function rows(n)
        {
            if (w <= 4)
            {
                return n + 1
            }
            if (n <= w)
            {
                return 1
            }
            return 2 * int((n + w - 3) / (w - 2)) + 1
        }
        {
            gsub(/\t/, "        ")
            if (NR > top && !full)
            {
                used += rows(length($0))
                if (used > h)
                {
                    full = 1
                }
                else if (NR > 1 && substr($0, 1, 3) == "rm ")
                {
                    print NR
                }
            }
        }
    ' "$state_dir/plan.summary" >> "$state_dir/plan.seen"
}

unseen()
{
    OIL_SEEN=$state_dir/plan.seen awk '
        BEGIN {
            while ((getline l < ENVIRON["OIL_SEEN"]) > 0)
            {
                seen[l + 0] = 1
            }
        }
        NR > 1 && substr($0, 1, 3) == "rm " && !(NR in seen) {
            print NR
        }
    ' "$state_dir/plan.summary"
}

plan_current()
{
    saved=$(cat "$state_dir/plan.token" 2>/dev/null)
    [ -n "$saved" ] && [ "$saved" = "$kak_opt_oil_token" ] && [ -f "$state_dir/plan.summary" ]
}

execute_plan()
{
    plan_file=$state_dir/plan
    if run_plan "$plan_file"
    then
        emit echo 'oil: applied'
    else
        emit info -title 'oil: apply failed part way' "$(cat "$tmp/exec-error")"
        emit echo -markup '{Error}oil: apply failed part way, see the info box'
    fi
    mv -f "$state_dir/plan.moved" "$state_dir/moved"
    rm -f "$state_dir/plan" "$state_dir/plan.token" "$state_dir/plan.summary" "$state_dir/plan.seen"
    if [ -s "$state_dir/moved" ]
    then
        printf 'evaluate-commands -buffer * %%{ try %%{ oil-sh follow } }\n'
    fi
    printf 'oil-refresh-all\n'
}

drop_plan()
{
    rm -f "$state_dir/plan" "$state_dir/plan.token" "$state_dir/plan.moved" "$state_dir/plan.summary" "$state_dir/plan.seen"
}

leave_plan_buffer()
{
    printf 'remove-hooks global oil-plan\n'
    if [ "$1" != stay ] && [ -n "$kak_opt_oil_plan_origin" ]
    then
        printf 'try %%{ buffer %s }\n' "$(kq "$kak_opt_oil_plan_origin")"
    fi
    printf "try %%{ delete-buffer! '*oil-plan*' }\n"
}

is_oil_buf()
{
    case "$1" in
        '*oil*' | '*oil:/'*'*')
            return 0
            ;;
    esac
    return 1
}

moved_path()
{
    [ -s "$state_dir/moved" ] || return 1
    OIL_PATH=$1 awk '
        NR % 2 == 1 {
            src = $0
            next
        }
        {
            p = ENVIRON["OIL_PATH"]
            if (p == src)
            {
                found = $0
            }
            else if (substr(p, 1, length(src) + 1) == src "/")
            {
                found = $0 substr(p, length(src) + 1)
            }
        }
        END {
            if (found == "")
            {
                exit 1
            }
            print found
        }
    ' "$state_dir/moved"
}

buffer_exists()
{
    want=$1
    eval "set -- $kak_quoted_buflist"
    for other
    do
        [ "$other" = "$want" ] && return 0
    done
    return 1
}

is_clean()
{
    [ "$kak_history_id" = "$kak_opt_oil_history" ]
}

find_buf()
{
    if buffer_exists "$(named "$1")"
    then
        named "$1"
    elif buffer_exists '*oil*' && [ "$kak_opt_oil_main_dir" = "$1" ]
    then
        printf '*oil*'
    else
        return 1
    fi
}

goto_dir()
{
    target=$(find_buf "$1") || target=
    kept=
    if [ -n "$kak_opt_oil_dir" ] && [ "$kak_bufname" != "$target" ] && is_clean
    then
        if [ -n "$target" ]
        then
            emit buffer "$target"
            emit delete-buffer "$kak_bufname"
        elif [ "$kak_bufname" = '*oil*' ]
        then
            target='*oil*'
        else
            target=$(named "$1")
            emit rename-buffer -scratch "$target"
        fi
    elif [ -z "$target" ] || [ "$kak_bufname" != "$target" ]
    then
        [ -z "$kak_opt_oil_dir" ] || kept=$kak_opt_oil_dir
        if [ -n "$target" ]
        then
            emit buffer "$target"
        else
            if buffer_exists '*oil*'
            then
                target=$(named "$1")
            else
                target='*oil*'
            fi
            emit edit -scratch "$target"
        fi
    fi
    emit oil-sh show "$1" "$2"
    emit set-option global oil_last "$target"
    if [ -n "$kept" ]
    then
        emit echo "oil: kept $(oil_label "$kept"), it has unsaved edits"
    fi
}

render()
{
    make_listing "$1" "$kak_opt_oil_hidden"
    focus=$(OIL_FOCUS=$2 OIL_LINE=$3 awk '
        BEGIN {
            f = ENVIRON["OIL_FOCUS"]
            kind = substr(f, 1, index(f, ":") - 1)
            want = substr(f, index(f, ":") + 1)
            if (kind == "id" && ENVIRON["OIL_LINE"] != "")
            {
                fallback = ENVIRON["OIL_LINE"] + 0
            }
        }
        {
            p = index($0, " ")
            col[NR] = p + 1
            id = substr($0, 2, p - 2) + 0
            if (!found && ((kind == "id" && id == want + 0) || (kind == "name" && substr($0, p + 1) == want)))
            {
                found = NR
            }
        }
        END {
            if (!found && kind == "line")
            {
                fallback = want + 0
            }
            if (!found && fallback > 0)
            {
                found = fallback > NR ? NR : fallback
            }
            if (found > 0)
            {
                printf "%d.%d,%d.%d", found, col[found], found, col[found]
            }
        }
    ' "$tmp/listing")
    emit set-option buffer oil_dir "$1"
    if [ "$kak_bufname" = '*oil*' ]
    then
        emit set-option global oil_main_dir "$1"
    fi
    emit set-option buffer oil_label "$(oil_label "$1" | sed 's/\\/\\\\/g')"
    emit set-option buffer oil_content "$(cat "$tmp/listing")$nl"
    printf 'oil-load\n'
    if [ -n "$focus" ]
    then
        emit select "$focus"
    fi
}

need_oil()
{
    [ -n "$kak_opt_oil_dir" ] || die 'not an oil buffer'
}

line_focus()
{
    text=${kak_opt_oil_line_text%"$nl"}
    if id=$(line_id "$text")
    then
        printf 'id:%s' "$id"
    else
        printf 'line:%s' "$kak_cursor_line"
    fi
}

state_dir=${OIL_STATE_DIR:-}
session=${OIL_SESSION:-${kak_session:-}}
dry_run=0
hidden=false
kak_mode=0
token=$(date +%s).$$

sq()
{
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

args=
while [ $# -gt 0 ]
do
    case "$1" in
        --state-dir)
            [ $# -ge 2 ] || die '--state-dir needs an argument'
            state_dir=$2
            shift 2
            ;;
        --session)
            [ $# -ge 2 ] || die '--session needs an argument'
            session=$2
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --hidden)
            hidden=true
            shift
            ;;
        -h | --help)
            printf '%s\n' "$usage"
            exit 0
            ;;
        --)
            shift
            for arg
            do
                args="$args $(sq "$arg")"
            done
            break
            ;;
        -?*)
            die "unknown option: $1"
            ;;
        *)
            args="$args $(sq "$1")"
            shift
            ;;
    esac
done
eval "set -- $args"

[ $# -gt 0 ] || die "no command$nl$usage"
action=$1
shift

case "$action" in
    list | apply)
        ;;
    *)
        kak_mode=1
        ;;
esac

case "$action" in
    list)
        [ $# -eq 1 ] || die "list takes one directory$nl$usage"
        init_state
        dir=$(canon "$1") || die "no such directory: $1"
        make_listing "$dir" "$hidden"
        cat "$tmp/listing"
        ;;
    apply)
        [ $# -ge 2 ] && [ $(($# % 2)) -eq 0 ] || die "apply takes DIR FILE pairs$nl$usage"
        init_state
        : > "$tmp/manifest"
        while [ $# -gt 0 ]
        do
            dir=$(canon "$1") || die "no such directory: $1"
            [ -f "$2" ] || die "no such file: $2"
            printf '%s\n%s\n%s\n' "$dir" "$(listed_file "$dir")" "$2" >> "$tmp/manifest"
            shift 2
        done
        if ! plan
        then
            plan_errors >&2
            exit 1
        fi
        if [ ! -s "$tmp/summary" ]
        then
            echo 'no changes'
            exit 0
        fi
        cat "$tmp/summary"
        [ "$dry_run" = 0 ] || exit 0
        plan_file=$tmp/plan
        if ! run_plan "$plan_file"
        then
            cat "$tmp/exec-error" >&2
            exit 1
        fi
        cp "$tmp/moved" "$state_dir/moved"
        ;;
    open)
        init_state
        focus=
        if [ -n "$1" ]
        then
            if ! dir=$(canon "$1")
            then
                case "$1" in
                    */*)
                        dir=$(canon "${1%/*}/") || die "no such directory: $1"
                        ;;
                    *)
                        dir=$PWD
                        ;;
                esac
                exists "$dir/${1##*/}" || die "no such directory: $1"
                focus=name:${1##*/}
            fi
        elif [ -n "$kak_opt_oil_dir" ]
        then
            dir=$kak_opt_oil_dir
        else
            case "$kak_buffile" in
                /*)
                    dir=$(canon "${kak_buffile%/*}/") || dir=$PWD
                    focus=name:${kak_buffile##*/}
                    ;;
                *)
                    dir=$PWD
                    ;;
            esac
        fi
        goto_dir "$dir" "$focus"
        ;;
    parent | up)
        init_state
        if [ -n "$kak_opt_oil_dir" ]
        then
            dir=$kak_opt_oil_dir
            [ "$dir" != / ] || die 'already at /'
            up=${dir%/*}
            goto_dir "${up:-/}" "name:${dir##*/}/"
        else
            [ "$action" = parent ] || die 'not an oil buffer'
            case "$kak_buffile" in
                /*)
                    dir=$(canon "${kak_buffile%/*}/") || die "no such directory: ${kak_buffile%/*}"
                    goto_dir "$dir" "name:${kak_buffile##*/}"
                    ;;
                *)
                    goto_dir "$PWD" ''
                    ;;
            esac
        fi
        ;;
    show)
        init_state
        if [ -z "$kak_opt_oil_dir" ]
        then
            printf 'oil-buffer-setup\n'
            render "$1" "$2"
        elif [ "$kak_opt_oil_dir" != "$1" ]
        then
            render "$1" "$2"
        fi
        ;;
    edit-dir)
        init_state
        dir=$(canon "$1") || die "no such directory: $1"
        goto_dir "$dir" ''
        [ "$2" = quiet ] || emit oil-notice "oil: $1 is a directory, opened it in oil"
        ;;
    startup)
        init_state
        f=$state_dir/startup-debug
        rm -f "$f"
        printf 'evaluate-commands -buffer *debug* %%{ write -force %s }\n' "$(kq "$f")"
        emit oil-sh startup-dirs "$kak_bufname"
        ;;
    startup-dirs)
        init_state
        f=$state_dir/startup-debug
        [ -f "$f" ] || exit 0
        awk '
            prev != "" && $0 == "    " prev ": is a directory" && !(prev in seen) {
                seen[prev] = 1
                print prev
            }
            {
                prev = ""
            }
            /^error while opening file \047.*\047:$/ {
                prev = substr($0, 27, length($0) - 28)
            }
        ' "$f" > "$tmp/dirs"
        rm -f "$f"
        [ -s "$tmp/dirs" ] || exit 0
        while IFS= read -r d
        do
            printf 'try %%{ buffer %s }\n' "$(kq "$1")"
            printf 'try %%{ oil-sh edit-dir %s quiet }\n' "$(kq "$d")"
        done < "$tmp/dirs"
        emit oil-notice "oil: opened $(tr '\n' ' ' < "$tmp/dirs")in oil"
        if [ "$1" = '*scratch*' ]
        then
            printf "try %%{ delete-buffer '*scratch*' }\n"
        else
            printf 'try %%{ buffer %s }\n' "$(kq "$1")"
        fi
        ;;
    back)
        init_state
        target=
        if [ -n "$kak_opt_oil_last" ] && buffer_exists "$kak_opt_oil_last"
        then
            target=$kak_opt_oil_last
        else
            eval "set -- $kak_quoted_buflist"
            for buf
            do
                is_oil_buf "$buf" && target=$buf
            done
        fi
        [ -n "$target" ] || die 'no oil buffer to go back to'
        emit buffer "$target"
        ;;
    enter)
        need_oil
        init_state
        text=${kak_opt_oil_line_text%"$nl"}
        case "$text" in
            *[!\ $tab]*)
                ;;
            *)
                exit
                ;;
        esac
        id=$(line_id "$text") || die 'not created yet, :w first'
        p=$(id_path "$id")
        [ -n "$p" ] || die "unknown ID: /$id"
        if [ -d "$p" ]
        then
            goto_dir "$p" ''
        elif exists "$p"
        then
            emit edit -existing "$p"
        else
            die "no longer exists: $p"
        fi
        ;;
    refresh)
        need_oil
        init_state
        render "$kak_opt_oil_dir" "$(line_focus)" "$kak_cursor_line"
        ;;
    render-bg)
        init_state
        if [ -n "$1" ]
        then
            if [ "$kak_bufname" != '*oil*' ]
            then
                emit rename-buffer -scratch "$(named "$1")"
            fi
            render "$1" ''
        else
            render "$kak_opt_oil_dir" ''
        fi
        ;;
    toggle-hidden)
        need_oil
        init_state
        if [ "$kak_opt_oil_hidden" = true ]
        then
            kak_opt_oil_hidden=false
        else
            kak_opt_oil_hidden=true
        fi
        emit set-option buffer oil_hidden "$kak_opt_oil_hidden"
        render "$kak_opt_oil_dir" "$(line_focus)" "$kak_cursor_line"
        ;;
    refresh-list)
        init_state
        eval "set -- $kak_quoted_buflist"
        for buf
        do
            is_oil_buf "$buf" || continue
            dir=$(name_dir "$buf") || continue
            if [ -d "$dir" ]
            then
                if [ "$buf" = "$kak_bufname" ]
                then
                    printf 'try %%{ oil-at refresh }\n'
                else
                    printf 'try %%{ evaluate-commands -buffer %s %%{ oil-sh render-bg } }\n' "$(kq "$buf")"
                fi
            elif new=$(moved_path "$dir") && [ -d "$new" ] && ! find_buf "$new" > /dev/null
            then
                printf 'try %%{ evaluate-commands -buffer %s %%{ oil-sh render-bg %s } }\n' "$(kq "$buf")" "$(kq "$new")"
            else
                emit delete-buffer! "$buf"
            fi
        done
        ;;
    apply-collect)
        init_state
        rm -rf "$state_dir/dump"
        mkdir "$state_dir/dump" || die "cannot write to $state_dir"
        n=0
        eval "set -- $kak_quoted_buflist"
        for buf
        do
            is_oil_buf "$buf" || continue
            n=$((n + 1))
            f=$state_dir/dump/$n
            printf 'evaluate-commands -no-hooks -buffer %s %%{\n' "$(kq "$buf")"
            printf '    write -force %s\n' "$(kq "$f")"
            printf '    echo -to-file %s %%val{history_id} %%opt{oil_history}\n' "$(kq "$f.hist")"
            printf '    echo -to-file %s %%opt{oil_dir}\n' "$(kq "$f.dir")"
            printf '}\n'
        done
        [ $n -gt 0 ] || die 'no oil buffers'
        emit oil-sh apply-plan "$n"
        ;;
    apply-plan)
        init_state
        : > "$tmp/manifest"
        stale=
        i=0
        while [ $i -lt "$1" ]
        do
            i=$((i + 1))
            f=$state_dir/dump/$i
            dir=$(cat "$f.dir" 2>/dev/null)
            [ -n "$dir" ] || continue
            hist=0
            oil_hist=0
            { read -r hist oil_hist || :; } < "$f.hist"
            if [ "${hist:-0}" -lt "${oil_hist:-0}" ] 2>/dev/null
            then
                stale="$stale$(oil_label "$dir") was undone past its last refresh, refresh it first$nl"
            fi
            printf '%s\n%s\n%s\n' "$dir" "$(listed_file "$dir")" "$f" >> "$tmp/manifest"
        done
        if [ -n "$stale" ]
        then
            emit info -title 'oil: cannot apply' "${stale%"$nl"}"
            die "${stale%%"$nl"*}"
        fi
        if ! plan
        then
            msg=$(plan_errors)
            emit info -title 'oil: cannot apply' "$(printf '%s\n' "$msg" | head -n 30)"
            die "${msg%%"$nl"*}"
        fi
        if [ ! -s "$tmp/summary" ]
        then
            emit echo 'oil: no changes'
            exit
        fi
        cp "$tmp/plan" "$state_dir/plan"
        cp "$tmp/moved" "$state_dir/plan.moved"
        cp "$tmp/summary" "$state_dir/plan.summary"
        rm -f "$state_dir/plan.seen"
        printf '%s\n' "$token" > "$state_dir/plan.token"
        if box_fits "$tmp/summary"
        then
            emit info -title 'oil: press y to apply, any other key cancels' "$(cat "$tmp/summary")"
            printf 'on-key %%{ oil-sh apply-confirm %%val{key} %s }\n' "$(kq "$token")"
        else
            emit set-option global oil_plan_origin "$kak_bufname"
            printf "try %%{ delete-buffer! '*oil-plan*' }\n"
            printf "edit -scratch '*oil-plan*'\n"
            emit set-option buffer oil_content "$(cat "$tmp/summary")$nl"
            emit oil-plan-show "$token"
        fi
        ;;
    apply-confirm)
        init_state
        key=$1
        token=$2
        printf "info ''\n"
        saved=$(cat "$state_dir/plan.token" 2>/dev/null)
        if [ "$key" != y ]
        then
            drop_plan
            emit echo 'oil: cancelled'
            exit
        fi
        [ "$saved" = "$token" ] || die 'the plan is out of date, :w again'
        execute_plan
        ;;
    plan-seen)
        init_state
        plan_current || exit 0
        mark_seen
        ;;
    plan-key)
        init_state
        case "$1" in
            y)
                if ! plan_current
                then
                    leave_plan_buffer
                    die 'the plan is out of date, :w again'
                fi
                touch "$state_dir/plan.seen"
                left=$(unseen)
                if [ -z "$left" ]
                then
                    leave_plan_buffer
                    execute_plan
                else
                    count=$(grep -c '^rm ' "$state_dir/plan.summary")
                    nleft=$(printf '%s\n' "$left" | wc -l)
                    printf 'execute-keys %sg vt\n' "${left%%"$nl"*}"
                    emit echo -markup "{Information}oil: $nleft of $count deletions not seen yet; scrolled to the first, press y again once you have reviewed them"
                fi
                ;;
            expire)
                drop_plan
                leave_plan_buffer stay
                emit echo 'oil: plan discarded because its buffer was left, :w again'
                ;;
            *)
                drop_plan
                leave_plan_buffer
                emit echo 'oil: cancelled'
                ;;
        esac
        ;;
    follow)
        case "$kak_buffile" in
            /*)
                ;;
            *)
                exit
                ;;
        esac
        init_state
        if new=$(moved_path "$kak_buffile")
        then
            emit rename-buffer -file "$new"
        fi
        ;;
    modeline)
        fmt=$kak_opt_modelinefmt
        case "$fmt" in
            *'%opt{oil_label}'*)
                exit 0
                ;;
            *'%val{bufname}'*)
                fmt="${fmt%%'%val{bufname}'*}%opt{oil_label}%opt{oil_flag}${fmt#*'%val{bufname}'}"
                ;;
            *)
                fmt="%opt{oil_label}%opt{oil_flag} $fmt"
                ;;
        esac
        case "$fmt" in
            *'{{context_info}}'*)
                ;;
            *)
                fmt="$fmt {{context_info}}"
                ;;
        esac
        emit set-option window modelinefmt "$fmt"
        ;;
    cleanup)
        [ -n "$session" ] || exit
        case "$session" in
            */* | . | ..)
                exit
                ;;
        esac
        [ -O "/tmp/kak-oil.$session" ] && rm -rf "/tmp/kak-oil.$session"
        exit 0
        ;;
    *)
        die "unknown command: $action$nl$usage"
        ;;
esac
