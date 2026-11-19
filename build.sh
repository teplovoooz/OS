#!/bin/sh

fail()
{
    printf '%s\n' "$2" >&2
    exit "$1"
}

[ "$#" -eq 1 ] || fail 2 "Использование: sh build.sh путь/к/файлу.c"

case "$1" in
    /*) source_file=$1 ;;
    *)  source_file=$PWD/$1 ;;
esac

case "$source_file" in
    *.c) ;;
    *) fail 2 "Ожидается исходный файл с расширением .c." ;;
esac

[ -f "$source_file" ] && [ -r "$source_file" ] ||
    fail 2 "Не удалось открыть исходник: $source_file"

output_name=$(LC_ALL=C awk '
    /^[[:space:]]*\/\/[[:space:]]*Output:/ {
        sub(/^[[:space:]]*\/\/[[:space:]]*Output:/, "")
        name = $0
        count++
    }
    /^[[:space:]]*\/\*[[:space:]]*Output:.*\*\/[[:space:]]*$/ {
        sub(/^[[:space:]]*\/\*[[:space:]]*Output:/, "")
        sub(/\*\/[[:space:]]*$/, "")
        name = $0
        count++
    }
    END {
        sub(/^[[:space:]]+/, "", name)
        sub(/[[:space:]]+$/, "", name)
        if (count != 1 || name == "")
            exit 1
        print name
    }
' < "$source_file") ||
    fail 3 "Укажите один комментарий Output: с именем выходного файла."

case "$output_name" in
    */*|.|..|"${source_file##*/}")
        fail 3 "Некорректное имя выходного файла: $output_name"
        ;;
esac

source_dir=${source_file%/*}
output_file=$source_dir/$output_name
[ ! -d "$output_file" ] || fail 6 "Выходной путь занят каталогом: $output_file"

command -v cc >/dev/null 2>&1 || fail 5 "Компилятор cc не найден."

tmp_dir=
compiler_pid=

cleanup()
{
    status=$?
    trap '' HUP INT QUIT TERM

    if [ -n "$tmp_dir" ] && ! rm -rf "$tmp_dir"; then
        printf 'Не удалось удалить временный каталог: %s\n' "$tmp_dir" >&2
        if [ "$status" -eq 0 ]; then
            status=7
        fi
    fi

    exit "$status"
}

stop()
{
    if [ -n "$compiler_pid" ]; then
        kill -s TERM "$compiler_pid" 2>/dev/null || :
    fi
    fail "$1" "Сборка прервана сигналом $2."
}

trap 'cleanup' 0
trap 'stop 129 HUP' HUP
trap 'stop 130 INT' INT
trap 'stop 131 QUIT' QUIT
trap 'stop 143 TERM' TERM

tmp_dir=$(mktemp -d "$source_dir/.build.XXXXXXXX") ||
    fail 4 "Не удалось создать временный каталог."

(
    cd "$tmp_dir" || exit 4
    TMPDIR=$tmp_dir TMP=$tmp_dir TEMP=$tmp_dir
    export TMPDIR TMP TEMP
    exec cc -std=c17 "$source_file" -o program -lm
) &
compiler_pid=$!

wait "$compiler_pid"
compiler_status=$?
compiler_pid=

[ "$compiler_status" -eq 0 ] ||
    fail 5 "Ошибка сборки: компилятор завершился с кодом $compiler_status."

mv -f "$tmp_dir/program" "$output_file" ||
    fail 6 "Не удалось сохранить результат: $output_file"

printf 'Сборка завершена: %s\n' "$output_file"
