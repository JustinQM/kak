#!/bin/sh
LC_ALL=C
export LC_ALL

oil=$(cd "$(dirname "$0")/../config/rc" && pwd)/oil.sh
root=$(mktemp -d /tmp/oil-test.XXXXXX) || exit 1
trap 'rm -rf "$root"' EXIT
pass=0
failed=0
nl='
'

run()
{
    sh "$oil" --state-dir "$root/state" "$@"
}

fresh()
{
    rm -rf "$root/fs" "$root/state" "$root/edit"
    mkdir -p "$root/fs" "$root/edit"
    cd "$root/fs" || exit 1
}

list()
{
    run list "$root/fs/$1" > "$root/edit/$2" || echo "list $1 failed" >&2
}

line_of()
{
    OIL_NAME=$2 awk '{ i = index($0, " "); if (substr($0, i + 1) == ENVIRON["OIL_NAME"]) print }' "$root/edit/$1"
}

rename()
{
    file=$1
    shift
    : > "$root/edit/pairs"
    while [ $# -ge 2 ]
    do
        printf '%s\n%s\n' "$1" "$2" >> "$root/edit/pairs"
        shift 2
    done
    OIL_PAIRS=$root/edit/pairs awk '
        BEGIN {
            f = ENVIRON["OIL_PAIRS"]
            while ((getline from < f) > 0)
            {
                getline to < f
                map[from] = to
            }
        }
        {
            i = index($0, " ")
            name = substr($0, i + 1)
            if (name in map)
            {
                print substr($0, 1, i) map[name]
            }
            else
            {
                print
            }
        }
    ' "$root/edit/$file" > "$root/edit/$file.new" && mv "$root/edit/$file.new" "$root/edit/$file"
}

drop()
{
    OIL_NAME=$2 awk '{ i = index($0, " "); if (substr($0, i + 1) != ENVIRON["OIL_NAME"]) print }' "$root/edit/$1" > "$root/edit/$1.new" && mv "$root/edit/$1.new" "$root/edit/$1"
}

add()
{
    printf '%s\n' "$2" >> "$root/edit/$1"
}

apply()
{
    out=$(run apply "$@" 2>&1)
}

snapshot()
{
    (cd "$root/fs" && find . -print | sort && find . -type f -exec cksum {} + | sort)
}

ok()
{
    pass=$((pass + 1))
    printf 'ok    %s\n' "$1"
}

bad()
{
    failed=$((failed + 1))
    printf 'FAIL  %s\n' "$1"
    [ -z "$2" ] || printf '%s\n' "$2" | sed 's/^/      /'
}

expect_tree()
{
    name=$1
    shift
    got=$(cd "$root/fs" && find . -mindepth 1 -print | sort)
    want=$(printf '%s\n' "$@" | sort)
    if [ "$got" = "$want" ]
    then
        ok "$name"
    else
        bad "$name" "want:$nl$want${nl}got:$nl$got${nl}output:$nl$out"
    fi
}

expect_content()
{
    if [ "$(cat "$root/fs/$2" 2>/dev/null)" = "$3" ]
    then
        ok "$1"
    else
        bad "$1" "$2 has: $(cat "$root/fs/$2" 2>&1)"
    fi
}

expect_abort()
{
    name=$1
    pattern=$2
    shift 2
    before=$(snapshot)
    if out=$(run apply "$@" 2>&1)
    then
        bad "$name" "apply succeeded:$nl$out"
        return
    fi
    if [ "$(snapshot)" != "$before" ]
    then
        bad "$name" "filesystem changed despite abort:$nl$out"
        return
    fi
    case "$out" in
        *"$pattern"*)
            ok "$name"
            ;;
        *)
            bad "$name" "error does not mention '$pattern':$nl$out"
            ;;
    esac
}

fresh
echo one > a
list . top
rename top a b
apply "$root/fs" "$root/edit/top"
expect_tree 'rename' ./b
expect_content 'rename keeps content' b one

fresh
echo A > a
echo B > b
list . top
rename top a b b a
apply "$root/fs" "$root/edit/top"
expect_tree 'swap' ./a ./b
expect_content 'swap a' a B
expect_content 'swap b' b A

fresh
echo X > x
echo Y > y
echo Z > z
list . top
rename top x y y z z x
apply "$root/fs" "$root/edit/top"
expect_content '3-way cycle x' x Z
expect_content '3-way cycle y' y X
expect_content '3-way cycle z' z Y
expect_tree '3-way cycle tree' ./x ./y ./z

fresh
mkdir d1 d2
mkdir d1/sub
mkdir d2/other
echo F > d2/other/f
echo M > d1/m
echo S > d1/sub/s
list . top
list d1 d1
list d2 d2
rename top d1/ d2/ d2/ d1/
apply "$root/fs" "$root/edit/top" "$root/fs/d1" "$root/edit/d1" "$root/fs/d2" "$root/edit/d2"
expect_tree 'swap non-empty directories' ./d1 ./d2 ./d1/other ./d1/other/f ./d2/sub ./d2/sub/s ./d2/m

fresh
mkdir src dst
echo M > src/moved
echo K > src/kept
list src src
list dst dst
line_of src moved >> "$root/edit/dst"
drop src moved
apply "$root/fs/src" "$root/edit/src" "$root/fs/dst" "$root/edit/dst"
expect_tree 'cross-directory move' ./src ./dst ./src/kept ./dst/moved
expect_content 'cross-directory move content' dst/moved M

fresh
mkdir src dst
echo M > src/moved
list src src
list dst dst
line_of src moved | sed 's/ moved$/ renamed/' >> "$root/edit/dst"
drop src moved
apply "$root/fs/src" "$root/edit/src" "$root/fs/dst" "$root/edit/dst"
expect_tree 'cross-directory move with rename' ./src ./dst ./dst/renamed

fresh
echo C > c
mkdir dir
echo inner > dir/i
mkdir other
list . top
list other other
line_of top c | sed 's/ c$/ c2/' >> "$root/edit/top"
line_of top dir/ | sed 's| dir/$| dir2/|' >> "$root/edit/top"
line_of top c >> "$root/edit/other"
apply "$root/fs" "$root/edit/top" "$root/fs/other" "$root/edit/other"
expect_tree 'copy via duplicated ID' ./c ./c2 ./dir ./dir/i ./dir2 ./dir2/i ./other ./other/c
expect_content 'copy content' c2 C
expect_content 'copy of directory content' dir2/i inner

fresh
echo C > c
list . top
id=$(line_of top c | cut -d' ' -f1)
printf '%s d\n%s e\n' "$id" "$id" > "$root/edit/top"
apply "$root/fs" "$root/edit/top"
expect_tree 'duplicated ID that is also renamed: first moves, extra copies' ./d ./e

fresh
echo x > file
mkdir full
mkdir full/deeper
echo y > full/deeper/z
echo k > keep
list . top
drop top file
drop top full/
apply "$root/fs" "$root/edit/top"
expect_tree 'delete file and non-empty directory' ./keep

fresh
list . top
add top 'a/b/c/'
apply "$root/fs" "$root/edit/top"
expect_tree 'nested mkdir' ./a ./a/b ./a/b/c

fresh
list . top
add top 'newsub/file.txt'
add top 'newsub/also/'
apply "$root/fs" "$root/edit/top"
expect_tree 'new file in new subdirectory' ./newsub ./newsub/file.txt ./newsub/also
if [ -f "$root/fs/newsub/file.txt" ] && [ ! -s "$root/fs/newsub/file.txt" ]
then
    ok 'new file is empty regular file'
else
    bad 'new file is empty regular file'
fi

fresh
mkdir sub
list . top
list sub sub
add top 'sub/x'
add sub 'y'
apply "$root/fs" "$root/edit/top" "$root/fs/sub" "$root/edit/sub"
expect_tree 'create through a path and in a second buffer' ./sub ./sub/x ./sub/y

fresh
echo a > a
echo b > b
list . top
rename top a b
expect_abort 'collision with existing file aborts' 'already exists' "$root/fs" "$root/edit/top"

fresh
echo a > a
list . top
add top 'a'
expect_abort 'new entry colliding with existing aborts' 'already exists' "$root/fs" "$root/edit/top"

fresh
echo a > a
echo b > b
list . top
rename top a c
rename top b c
expect_abort 'two entries with the same target abort' 'duplicate target' "$root/fs" "$root/edit/top"

fresh
echo a > a
echo b > b
list . top
sed -i 's|^/0*1 |/00x1 |' "$root/edit/top"
expect_abort 'line starting with / but no valid ID aborts' 'not a valid ID' "$root/fs" "$root/edit/top"

fresh
echo a > a
list . top
sed -i 's|^\(/[0-9]*\) |\1|' "$root/edit/top"
expect_abort 'live ID with its space deleted aborts' 'mangled ID' "$root/fs" "$root/edit/top"

fresh
echo a > a
list . top
sed -i 's|^\(/[0-9]*\) .*|\1|' "$root/edit/top"
expect_abort 'live ID with its name deleted aborts' 'mangled ID' "$root/fs" "$root/edit/top"

fresh
echo a > a
list . top
sed -i 's|^/|X/|' "$root/edit/top"
before=$(snapshot)
out=$(run apply --dry-run "$root/fs" "$root/edit/top" 2>&1)
case "$out" in
    *'warning: '*'contains ID /0001'*)
        ok 'text typed before the ID is a warning, not an abort'
        ;;
    *)
        bad 'text typed before the ID is a warning, not an abort' "$out"
        ;;
esac
[ "$(snapshot)" = "$before" ] && ok 'dry run with a warning changes nothing' || bad 'dry run with a warning changes nothing'

fresh
echo a > a
list . top
sed -i 's|^/||' "$root/edit/top"
out=$(run apply --dry-run "$root/fs" "$root/edit/top" 2>&1)
case "$out" in
    *'warning: '*'begins like ID /0001'*)
        ok 'ID with its slash deleted is a warning, not an abort'
        ;;
    *)
        bad 'ID with its slash deleted is a warning, not an abort' "$out"
        ;;
esac

fresh
echo a > a
list . top
add top '/9999 ghost'
expect_abort 'unknown ID aborts' 'unknown ID' "$root/fs" "$root/edit/top"

fresh
echo a > a
list . top
rename top a ../escape
expect_abort 'dot-dot in a name aborts' 'invalid name' "$root/fs" "$root/edit/top"

fresh
echo a > a
list . top
add top 'x//y'
expect_abort 'empty path component aborts' 'invalid name' "$root/fs" "$root/edit/top"

fresh
echo a > a
list . top
rename top a a/
expect_abort 'file renamed with a trailing slash aborts' 'cannot become a directory' "$root/fs" "$root/edit/top"

fresh
mkdir d
list . top
rename top d/ d/inner/d/
expect_abort 'moving a directory into itself aborts' 'into itself' "$root/fs" "$root/edit/top"

fresh
echo a > a
list . top
rename top a 'a/b'
expect_abort 'moving a file below its own name aborts' 'into itself' "$root/fs" "$root/edit/top"

fresh
echo a > a
echo b > b
list . top
add top 'b/x'
expect_abort 'existing file used as a directory aborts' 'not a directory' "$root/fs" "$root/edit/top"

fresh
mkdir sub
list . top
list sub sub
rename top sub/ sub2/
add sub 'stale'
expect_abort 'edit inside a directory that is being renamed aborts' 'being moved or removed' "$root/fs" "$root/edit/top" "$root/fs/sub" "$root/edit/sub"

fresh
echo a > a
echo b > b
list . top
drop top a
rename top b c
add top 'a/b/'
add top 'new'
before=$(snapshot)
out=$(run apply --dry-run "$root/fs" "$root/edit/top" 2>&1)
if [ "$(snapshot)" = "$before" ]
then
    case "$out" in
        *'rm     '*'/a'*)
            ok 'dry run prints the plan and changes nothing'
            ;;
        *)
            bad 'dry run prints the plan and changes nothing' "$out"
            ;;
    esac
else
    bad 'dry run prints the plan and changes nothing' 'filesystem changed'
fi
apply "$root/fs" "$root/edit/top"
expect_tree 'replace a deleted file with a new directory of the same name' ./a ./a/b ./c ./new

fresh
for name in 'with space' '-rf' '--help' 'ünïcødé ✓' '*' '?' '[ab]' "it's" 'back\slash' 'tab	in' ' leading' 'trailing ' '$(echo pwn)' '~tilde'
do
    printf '%s\n' "$name" > "./$name"
done
touch a b
list . top
rename top 'with space' 'still with space' '-rf' '-rf renamed' '*' '**' "it's" "it''s" 'tab	in' 'tab	out'
drop top '[ab]'
drop top '--help'
add top '-n new'
add top '[x] new/*'
apply "$root/fs" "$root/edit/top"
expect_tree 'odd filenames' './still with space' './-rf renamed' './ünïcødé ✓' './**' './?' "./it''s" './back\slash' './tab	out' './ leading' './trailing ' './$(echo pwn)' './~tilde' './-n new' './[x] new' './[x] new/*' ./a ./b
expect_content 'odd filename content' '-rf renamed' '-rf'
expect_content 'glob filename content' '**' '*'

fresh
mkdir d
echo i > d/i
list . top
list d d
rename top d/ e/
line_of d i | sed 's/ i$/ moved-out/' >> "$root/edit/top"
drop d i
apply "$root/fs" "$root/edit/top" "$root/fs/d" "$root/edit/d"
expect_tree 'rename a directory and move a file out of it' ./e ./moved-out

fresh
mkdir d
echo i > d/i
list . top
list d d
drop top d/
line_of d i >> "$root/edit/top"
drop d i
apply "$root/fs" "$root/edit/top" "$root/fs/d" "$root/edit/d"
expect_tree 'move a file out and delete its directory' ./i

fresh
echo h > .hidden
echo v > visible
list . top
drop top visible
apply "$root/fs" "$root/edit/top"
expect_tree 'unlisted hidden files are not deleted' ./.hidden
run list --hidden "$root/fs" > "$root/edit/top"
if grep -q ' \.hidden$' "$root/edit/top"
then
    ok 'list --hidden shows dotfiles'
else
    bad 'list --hidden shows dotfiles' "$(cat "$root/edit/top")"
fi

fresh
echo a > a
list . top
first=$(cat "$root/edit/top")
list . top
if [ "$(cat "$root/edit/top")" = "$first" ]
then
    ok 'IDs are stable across relistings'
else
    bad 'IDs are stable across relistings'
fi
mkdir other
echo z > other/z
list other other
if [ "$(line_of other z | cut -d' ' -f1)" != "$(line_of top a | cut -d' ' -f1)" ]
then
    ok 'IDs are unique across directories'
else
    bad 'IDs are unique across directories'
fi

fresh
mkdir many
i=0
while [ $i -lt 2030 ]
do
    i=$((i + 1))
    : > "many/f$i"
done
list many many
list . top
add top '2024 report'
add top '24 report'
add top '9999 report'
apply "$root/fs" "$root/edit/top"
if [ -f "$root/fs/2024 report" ] && [ -f "$root/fs/24 report" ] && [ -f "$root/fs/9999 report" ]
then
    ok '"2024 report" is created even though ID 2024 exists'
else
    bad '"2024 report" is created even though ID 2024 exists' "$out"
fi
case "$out" in
    *'"2024 report" begins like ID /2024'*)
        ok 'a name that matches a live ID gets a warning'
        ;;
    *)
        bad 'a name that matches a live ID gets a warning' "$out"
        ;;
esac
case "$out" in
    *'"24 report"'* | *'"9999 report"'*)
        bad 'names that do not match a live ID get no warning' "$out"
        ;;
    *)
        ok 'names that do not match a live ID get no warning'
        ;;
esac

fresh
echo a > a
echo b > b
mkdir d
list . top
drop top b
rename top a z
add top 'new/'
add top 'n.txt'
out=$(run apply --dry-run "$root/fs" "$root/edit/top" 2>&1)
if [ "$(printf '%s\n' "$out" | sed -n 2p | cut -c1-3)" = 'rm ' ]
then
    ok 'rm operations are listed first in the plan'
else
    bad 'rm operations are listed first in the plan' "$out"
fi

kak_run()
{
    env kak_session=oiltest kak_client=client0 kak_cursor_line=1 kak_history_id="${hist:-1}" kak_modified=false \
        kak_opt_oil_hidden=false kak_opt_oil_history=1 kak_opt_oil_line_text="${line_text:-}" kak_opt_oil_last="${oil_last:-}" \
        kak_bufname="${bufname:-*scratch*}" kak_buffile="${bufname:-*scratch*}" \
        kak_quoted_buflist="${buflist:-}" kak_opt_oil_dir="${oildir:-}" \
        kak_window_height="${win_h:-}" kak_window_width="${win_w:-}" kak_window_range="${win_range:-}" \
        kak_opt_oil_token="${plan_token:-}" kak_opt_oil_plan_origin= kak_opt_oil_main_dir="${main_dir:-}" \
        sh "$oil" --state-dir "$root/state" -- "$@"
}

prepare_dump()
{
    mkdir -p "$root/state/dump"
    cp "$root/edit/top" "$root/state/dump/1"
    printf '1 1' > "$root/state/dump/1.hist"
    printf '%s' "$root/fs" > "$root/state/dump/1.dir"
}

fresh
for i in 1 2 3
do
    echo $i > "f$i"
done
list . top
drop top f1
drop top f2
prepare_dump
out=$(win_h=40 win_w=200 kak_run apply-plan 1)
case "$out" in
    *'on-key'*)
        ok 'a plan that fits is confirmed in the info box'
        ;;
    *)
        bad 'a plan that fits is confirmed in the info box' "$out"
        ;;
esac
out=$(win_h=5 win_w=200 kak_run apply-plan 1)
case "$out" in
    *"edit -scratch '*oil-plan*'"*'oil-plan-show'*)
        ok 'a plan taller than the window opens the plan buffer'
        ;;
    *)
        bad 'a plan taller than the window opens the plan buffer' "$out"
        ;;
esac
out=$(win_h=40 win_w=20 kak_run apply-plan 1)
case "$out" in
    *'oil-plan-show'*)
        ok 'a plan wider than the window opens the plan buffer'
        ;;
    *)
        bad 'a plan wider than the window opens the plan buffer' "$out"
        ;;
esac
out=$(kak_run apply-plan 1)
case "$out" in
    *'oil-plan-show'*)
        ok 'without window size the plan buffer is used'
        ;;
    *)
        bad 'without window size the plan buffer is used' "$out"
        ;;
esac
fresh
for i in 1 2 3 4 5 6 7
do
    echo $i > "f$i"
done
list . top
for i in 1 2 3 4 5 6
do
    drop top "f$i"
done
prepare_dump
win_h=3 win_w=200 kak_run apply-plan 1 > /dev/null
token=$(cat "$root/state/plan.token")
before=$(snapshot)
expect_page()
{
    name=$1
    want=$2
    line=$3
    out=$(plan_token=$token kak_run plan-key y)
    case "$out" in
        *"execute-keys ${line}g vt"*"$want of 6 deletions not seen yet"*)
            [ "$(snapshot)" = "$before" ] && ok "$name" || bad "$name" 'filesystem changed'
            ;;
        *)
            bad "$name" "$out"
            ;;
    esac
}
expect_page 'y before any deletion was on screen pages to the first one' 6 2
plan_token=$token win_range='0 0 3 200' kak_run plan-seen
expect_page 'y after seeing the first screen pages to the next unseen deletion' 4 4
plan_token=wrong win_range='3 0 3 200' kak_run plan-seen
expect_page 'views reported with a stale token are not counted' 4 4
plan_token=$token win_range='3 0 3 200' kak_run plan-seen
expect_page 'y after seeing the second screen pages to the last unseen deletion' 1 7
plan_token=$token win_range='6 0 3 20' kak_run plan-seen
expect_page 'wrapped lines that may not fit are not counted as seen' 1 7
out=$(plan_token=wrong kak_run plan-key y 2>&1)
case "$out" in
    *'out of date'*)
        [ "$(snapshot)" = "$before" ] && ok 'a stale token is rejected' || bad 'a stale token is rejected' 'filesystem changed'
        ;;
    *)
        bad 'a stale token is rejected' "$out"
        ;;
esac
plan_token=$token win_range='6 0 3 200' kak_run plan-seen
out=$(plan_token=$token kak_run plan-key y)
expect_tree 'y once every deletion has been on screen applies the plan' ./f7
if [ ! -e "$root/state/plan.seen" ]
then
    ok 'seen lines are forgotten after applying'
else
    bad 'seen lines are forgotten after applying'
fi

fresh
echo 1 > f1
list . top
drop top f1
prepare_dump
win_h=3 win_w=200 kak_run apply-plan 1 > /dev/null
token=$(cat "$root/state/plan.token")
plan_token=$token win_range='0 0 3 200' kak_run plan-seen
win_h=3 win_w=200 kak_run apply-plan 1 > /dev/null
token=$(cat "$root/state/plan.token")
out=$(plan_token=$token kak_run plan-key y)
case "$out" in
    *'1 of 1 deletions not seen yet'*)
        ok 'a new plan starts with nothing seen'
        ;;
    *)
        bad 'a new plan starts with nothing seen' "$out"
        ;;
esac

fresh
echo 1 > f1
list . top
drop top f1
prepare_dump
win_h=5 win_w=200 kak_run apply-plan 1 > /dev/null
token=$(cat "$root/state/plan.token")
kak_run plan-key expire > /dev/null
out=$(plan_token=$token win_range='0 0 30 200' kak_run plan-key y 2>&1)
case "$out" in
    *'out of date'*)
        expect_tree 'leaving the plan buffer discards the plan' ./f1
        ;;
    *)
        bad 'leaving the plan buffer discards the plan' "$out"
        ;;
esac

fresh
mkdir a b
out=$(kak_run open "$root/fs/a")
case "$out" in
    "edit '-scratch' '*oil*'${nl}oil-sh 'show' '$root/fs/a' ''${nl}set-option 'global' 'oil_last' '*oil*'")
        ok 'the first oil buffer is a scratch buffer named *oil*'
        ;;
    *)
        bad 'the first oil buffer is a scratch buffer named *oil*' "$out"
        ;;
esac
out=$(buflist="'*oil*'" main_dir=$root/fs/a kak_run open "$root/fs/b")
case "$out" in
    "edit '-scratch' '*oil:$root/fs/b/*'"*)
        ok 'further oil buffers are named *oil:/path/*'
        ;;
    *)
        bad 'further oil buffers are named *oil:/path/*' "$out"
        ;;
esac
out=$(bufname=notes.txt buflist="'*oil*' 'notes.txt'" main_dir=$root/fs/a kak_run open "$root/fs/a")
case "$out" in
    "buffer '*oil*'${nl}oil-sh 'show' '$root/fs/a' ''"*)
        ok '*oil* is reused for the directory it shows'
        ;;
    *)
        bad '*oil* is reused for the directory it shows' "$out"
        ;;
esac
out=$(bufname='*oil*' oildir=$root/fs/a buflist="'*oil*'" main_dir=$root/fs/a kak_run open "$root/fs/b")
case "$out" in
    "oil-sh 'show' '$root/fs/b' ''${nl}set-option 'global' 'oil_last' '*oil*'")
        ok 'navigating in a clean *oil* keeps its name'
        ;;
    *)
        bad 'navigating in a clean *oil* keeps its name' "$out"
        ;;
esac
out=$(bufname="*oil:$root/fs/a/*" oildir=$root/fs/a buflist="'*oil*' '*oil:$root/fs/a/*'" main_dir=$root/fs/x kak_run open "$root/fs/b")
case "$out" in
    "rename-buffer '-scratch' '*oil:$root/fs/b/*'${nl}oil-sh 'show' '$root/fs/b' ''"*)
        ok 'navigating in a clean *oil:/path/* renames it to the new path'
        ;;
    *)
        bad 'navigating in a clean *oil:/path/* renames it to the new path' "$out"
        ;;
esac
out=$(bufname="*oil:$root/fs/a/*" oildir=$root/fs/a buflist="'*oil*' '*oil:$root/fs/a/*'" main_dir=$root/fs/b kak_run open "$root/fs/b")
case "$out" in
    "buffer '*oil*'${nl}delete-buffer '*oil:$root/fs/a/*'${nl}oil-sh 'show' '$root/fs/b' ''"*)
        ok 'navigating in a clean buffer to a directory that has a buffer switches to it'
        ;;
    *)
        bad 'navigating in a clean buffer to a directory that has a buffer switches to it' "$out"
        ;;
esac
out=$(bufname='*oil*' oildir=$root/fs/a hist=5 buflist="'*oil*'" main_dir=$root/fs/a kak_run open "$root/fs/b")
case "$out" in
    "edit '-scratch' '*oil:$root/fs/b/*'"*"kept oil:$root/fs/a/, it has unsaved edits"*)
        ok 'a buffer with unapplied edits is kept and the directory opens in a new one'
        ;;
    *)
        bad 'a buffer with unapplied edits is kept and the directory opens in a new one' "$out"
        ;;
esac
out=$(main_dir=$root/fs/a buflist="'*debug*' '*oil*' '*oil:$root/fs/b/*' '*oil:$root/fs/gone/*' 'notes.txt' '*oil-plan*'" kak_run refresh-list)
want="try %{ evaluate-commands -buffer '*oil*' %{ oil-sh render-bg } }
try %{ evaluate-commands -buffer '*oil:$root/fs/b/*' %{ oil-sh render-bg } }
delete-buffer! '*oil:$root/fs/gone/*'"
[ "$out" = "$want" ] && ok 'refresh finds every oil buffer and its directory' || bad 'refresh finds every oil buffer and its directory' "$out"
out=$(bufname='*oil*' kak_run render-bg "$root/fs/b")
case "$out" in
    *rename-buffer*)
        bad 'a moved directory keeps the *oil* name' "$out"
        ;;
    *"set-option 'global' 'oil_main_dir' '$root/fs/b'"*)
        ok 'a moved directory keeps the *oil* name'
        ;;
    *)
        bad 'a moved directory keeps the *oil* name' "$out"
        ;;
esac

out=$(kak_opt_modelinefmt='%val{bufname} %val{cursor_line}:%val{cursor_char_column} {{context_info}} {{mode_info}} - %val{client}@[%val{session}]' kak_run modeline)
if [ "$out" = "set-option 'window' 'modelinefmt' '%opt{oil_label}%opt{oil_flag} %val{cursor_line}:%val{cursor_char_column} {{context_info}} {{mode_info}} - %val{client}@[%val{session}]'" ]
then
    ok 'the modeline shows the directory label in place of the buffer name'
else
    bad 'the modeline shows the directory label in place of the buffer name' "$out"
fi
out=$(kak_opt_modelinefmt='%val{session}' kak_run modeline)
if [ "$out" = "set-option 'window' 'modelinefmt' '%opt{oil_label}%opt{oil_flag} %val{session} {{context_info}}'" ]
then
    ok 'a custom modeline gets the label and the modified flag added'
else
    bad 'a custom modeline gets the label and the modified flag added' "$out"
fi
out=$(kak_opt_modelinefmt='%opt{oil_label} x' kak_run modeline)
[ -z "$out" ] && ok 'the modeline is not rewritten twice' || bad 'the modeline is not rewritten twice' "$out"
mkdir -p "$root/fs/back\\slash"
out=$(kak_run show "$root/fs/back\\slash" '')
case "$out" in
    *"set-option 'buffer' 'oil_label' 'oil:$root/fs/back\\\\slash/'"*)
        ok 'backslashes in the label are escaped for the modeline markup'
        ;;
    *)
        bad 'backslashes in the label are escaped for the modeline markup' "$out"
        ;;
esac
fresh
mkdir sub
echo f > file.txt
list . top
out=$(bufname='*oil*' oildir=$root/fs main_dir=$root/fs hist=7 buflist="'*oil*' '$root/fs/file.txt'" line_text="$(line_of top file.txt)" kak_run enter)
if [ "$out" = "edit '-existing' '$root/fs/file.txt'" ]
then
    ok '<ret> on a file only opens it, leaving the oil buffer alone'
else
    bad '<ret> on a file only opens it, leaving the oil buffer alone' "$out"
fi
for h in 1 7
do
    out=$(bufname='*oil*' oildir=$root/fs hist=$h kak_run show "$root/fs" 'name:file.txt')
    if [ -z "$out" ]
    then
        ok "an existing oil buffer is not relisted when switched to (history $h)"
    else
        bad "an existing oil buffer is not relisted when switched to (history $h)" "$out"
    fi
done
out=$(bufname=$root/fs/file.txt buflist="'*oil*' '$root/fs/file.txt'" main_dir=$root/fs kak_run parent)
case "$out" in
    "buffer '*oil*'${nl}oil-sh 'show' '$root/fs' 'name:file.txt'${nl}set-option 'global' 'oil_last' '*oil*'")
        ok 'oil-parent switches to the existing buffer for the directory'
        ;;
    *)
        bad 'oil-parent switches to the existing buffer for the directory' "$out"
        ;;
esac
both="'*oil*' '$root/fs/file.txt' '*oil:$root/fs/sub/*'"
out=$(bufname=$root/fs/file.txt buflist=$both oil_last='*oil*' kak_run back)
[ "$out" = "buffer '*oil*'" ] && ok 'oil-back goes to the most recent oil buffer' || bad 'oil-back goes to the most recent oil buffer' "$out"
out=$(bufname=$root/fs/file.txt buflist=$both oil_last='*oil:/gone/*' kak_run back)
[ "$out" = "buffer '*oil:$root/fs/sub/*'" ] && ok 'oil-back falls back to an open oil buffer' || bad 'oil-back falls back to an open oil buffer' "$out"
out=$(bufname=$root/fs/file.txt buflist="'$root/fs/file.txt'" kak_run back 2>&1)
case "$out" in
    *'no oil buffer'*)
        ok 'oil-back fails when no oil buffer is open'
        ;;
    *)
        bad 'oil-back fails when no oil buffer is open' "$out"
        ;;
esac

fresh
mkdir -p "sub dir/deep"
home_dir=$root/home
mkdir -p "$home_dir/proj"
for arg in "$root/fs/sub dir" "$root/fs/sub dir/" 'sub dir' 'sub dir/' 'sub dir/deep/..' 'sub dir/./' "$root/fs/sub dir/deep/../"
do
    out=$(cd "$root/fs" && kak_run edit-dir "$arg")
    case "$out" in
        "edit '-scratch' '*oil*'${nl}oil-sh 'show' '$root/fs/sub dir' ''"*"oil-notice"*)
            ok ":e on a directory opens oil there: $arg"
            ;;
        *)
            bad ":e on a directory opens oil there: $arg" "$out"
            ;;
    esac
done
for arg in '.' '..' '~' '~/' '~/proj/..'
do
    case "$arg" in
        '.')
            want="$root/fs/sub dir"
            ;;
        '..')
            want=$root/fs
            ;;
        *)
            want=$home_dir
            ;;
    esac
    out=$(cd "$root/fs/sub dir" && HOME=$home_dir kak_run edit-dir "$arg")
    case "$out" in
        *"oil-sh 'show' '$want' ''"*)
            ok ":e on a directory opens oil there: $arg"
            ;;
        *)
            bad ":e on a directory opens oil there: $arg" "$out"
            ;;
    esac
done
out=$(cd "$root/fs" && buflist="'*oil:$root/fs/sub dir/*'" kak_run edit-dir 'sub dir')
case "$out" in
    "buffer '*oil:$root/fs/sub dir/*'"*)
        ok ':e on a directory reuses its existing oil buffer'
        ;;
    *)
        bad ':e on a directory reuses its existing oil buffer' "$out"
        ;;
esac
out=$(cd "$root/fs" && kak_run edit-dir 'missing' 2>&1)
case "$out" in
    *'no such directory'*)
        ok ':e on a path that is not a directory fails'
        ;;
    *)
        bad ':e on a path that is not a directory fails' "$out"
        ;;
esac
mkdir -p "$root/state"
cat > "$root/state/startup-debug" <<'DEBUG'
*** This is the debug buffer, where debug info will be written ***
error while opening file 'sub dir':
    sub dir: is a directory
error while opening file 'nope.txt':
    nope.txt: Permission denied
error while opening file '../fs':
    ../fs: is a directory
error while opening file 'sub dir':
    sub dir: is a directory
Error: 1:1: 'e': x: is a directory
DEBUG
out=$(bufname='*scratch*' kak_run startup-dirs '*scratch*')
want="try %{ buffer '*scratch*' }
try %{ oil-sh edit-dir 'sub dir' quiet }
try %{ buffer '*scratch*' }
try %{ oil-sh edit-dir '../fs' quiet }
oil-notice 'oil: opened sub dir ../fs in oil'
try %{ delete-buffer '*scratch*' }"
if [ "$out" = "$want" ]
then
    ok 'kak <dir> at startup opens each directory once and drops the empty *scratch*'
else
    bad 'kak <dir> at startup opens each directory once and drops the empty *scratch*' "$out"
fi
printf 'error while opening file %s:\n    a.txt: is a directory\n' "'a.txt'" > "$root/state/startup-debug"
out=$(bufname=a.txt kak_run startup-dirs a.txt)
case "$out" in
    *"try %{ buffer 'a.txt' }")
        ok 'kak file dir at startup keeps the file in front'
        ;;
    *)
        bad 'kak file dir at startup keeps the file in front' "$out"
        ;;
esac
printf 'error while opening file %s:\n    nope: Permission denied\n' "'nope'" > "$root/state/startup-debug"
out=$(kak_run startup-dirs '*scratch*')
[ -z "$out" ] && ok 'startup errors that are not directories are left alone' || bad 'startup errors that are not directories are left alone' "$out"

mkdir -p /tmp/kak-oil.oil-test-cleanup.$$/view
kak_session=oil-test-cleanup.$$ sh "$oil" -- cleanup
if [ -e /tmp/kak-oil.oil-test-cleanup.$$ ]
then
    rm -rf /tmp/kak-oil.oil-test-cleanup.$$
    bad 'cleanup removes the session state and backing files'
else
    ok 'cleanup removes the session state and backing files'
fi

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" = 0 ]
