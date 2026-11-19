# Спека TUI: вариант A, строго по структуре

## Факты апстрима (менять нельзя)

- `setup.sh` **не читает** существующий `/root/antizapret/setup`: значения по умолчанию вшиты
  в сами команды (`read -rp '… [y/n]: ' -e -i y OPENVPN_UDP_ENABLE`, `-i "$MTU"`, `-i 2`).
- После вопросов файл `setup` **перезаписывается целиком из ответов** (блок `:572-639`); перед
  этим `/root/antizapret` стирается (`:656`), а `config/*.txt`, `custom*.sh`, knot-lua,
  easyrsa3 и wireguard копируются вперёд (`:542-563`). Это поведение сохраняется один-в-один.
- В апстриме 41 вызов `read -rp` → **39 уникальных вопросов**; `MTU` (120/122) и
  `WARP_ENDPOINT` (178/180) спрашиваются повторно в цикле проверки ввода.
- 8 include-списков закомментированы и остаются закомментированными.
- Логика после строки `:359` не меняется ни на байт.

## Принципы

0. **Первым делом — выбор интерфейса.** До любого диалога скрипт спрашивает
   `Interface: 1) whiptail TUI  2) plain prompts [1]: ` **обычным `read -rp`** (whiptail здесь
   использовать нельзя: если бинаря нет, выбрать вариант 2 было бы невозможно). Пустой ввод = 1,
   мусор = сообщение `Invalid choice: <input>` и повтор вопроса; EOF = вариант 1.
   Приоритет источников: `AZ_UI=whiptail|plain` (для тестов/автоматизации, вопрос пропускается) →
   `NO_WHIPTAIL=1` (сразу plain, вопрос пропускается) → **stdin не терминал** (`! -t 0`: вызов из
   pipe/cron/без TTY) → plain без вопроса плюс одна строка `stdin is not a terminal: using plain
   prompts` → интерактивный вопрос.
   Если выбран 1 и режим недоступен — `whiptail not available, falling back to plain prompts`
   и plain (не выход). Селектор **не входит** в счёт 39 `ask_*`.
1. **39 диалогов** — по одному на уникальный вопрос, порядок и текст — как в апстриме.
   Никаких разделов и склейки: это следующие версии проекта.
2. Подписи **на английском** (`LC_ALL=C`), текст вопроса переносится без перевода.
3. **Дефолты диалогов — встроенные значения апстрима.** Никакого чтения старого `setup` и
   никакого `PREFILL_PATH`: логика «спросить и перезаписать» сохраняется.
4. Целевая версия — **whiptail 0.52.25** (`newt`, Debian 13); версия пишется в лог.
5. Режимы: `QUESTIONS_ONLY=1`, `NO_WHIPTAIL=1`, `AZ_UI=whiptail|plain` (перекрывает селектор).

## Bootstrap

```bash
# 1) выбор интерфейса. Приоритет: AZ_UI → NO_WHIPTAIL → нет TTY → вопрос.
#    Вопрос задаётся обычным read -rp: whiptail здесь использовать нельзя.
ui_from_env=0
if [[ -n ${AZ_UI:-} ]]; then
    ui_from_env=1
elif [[ ${NO_WHIPTAIL:-0} == 1 ]]; then
    AZ_UI=plain
elif [[ ! -t 0 ]]; then
    AZ_UI=plain; echo "stdin is not a terminal: using plain prompts"
else
    while :; do
        read -rp 'Interface: 1) whiptail TUI  2) plain prompts [1]: ' ui_choice || ui_choice=1
        case ${ui_choice:-1} in
            1) AZ_UI=whiptail; break ;;
            2) AZ_UI=plain; break ;;
            *) echo "Invalid choice: ${ui_choice}" ;;
        esac
    done
fi
case $AZ_UI in
    whiptail|plain) ;;
    *) echo "AZ_UI must be whiptail or plain"; exit 2 ;;
esac

# 2) режим whiptail: бинарь, TTY, TERM. Пакет ставим только в этой ветке.
if [[ $AZ_UI == whiptail ]]; then
    WHIPTAIL_BIN=$(command -v whiptail || true)
    if [[ -z $WHIPTAIL_BIN && ${QUESTIONS_ONLY:-0} != 1 ]]; then
        apt-get install -y whiptail || true          # один пакет, 61 КБ
        WHIPTAIL_BIN=$(command -v whiptail || true)
    fi
    if [[ $ui_from_env == 1 && -z $WHIPTAIL_BIN ]]; then
        echo "AZ_UI=whiptail but whiptail is not installed"; exit 2
    fi
    if [[ $ui_from_env == 0 && ( -z $WHIPTAIL_BIN || ! -t 0 || -z ${TERM:-} ) ]]; then
        echo "whiptail not available, falling back to plain prompts"; AZ_UI=plain
    fi
    if [[ $AZ_UI == whiptail ]]; then
        whiptail --version 2>&1 | head -1 >> "$LOG"
    fi
fi
```

Инварианты:

- `QUESTIONS_ONLY=1` **никогда** не ставит пакеты и не меняет систему.
- В headless-тестах поддельный `whiptail` стоит первым в `PATH`, поэтому `command -v whiptail` его
  находит.
- plain-режим — **исходный код апстрима** (`read -rp`), а не переписанная копия: fallback обязан
  давать тот же результат, что и whiptail-ветка.
- селектор режима **не ставит пакеты и не зависит от whiptail** — он рисуется `read -rp`.
- перед первым диалогом — проба терминала `whiptail --infobox '' 8 40`: если whiptail не может
  отрисовать экран, явный `AZ_UI=whiptail` даёт код 2, а выбранный в диалоге — fallback на plain.
  Без пробы сломанный терминал молча превращал бы все ответы «да/нет» в `n`.
- `QUESTIONS_ONLY=1` не меняет ничего, включая лог: строка версии whiptail в
  `/tmp/antizapret-setup.log` тоже не пишется.

## Хелперы

| хелпер | диалог | возвращает |
|---|---|---|
| `ask_yn VAR "Text" default` | `--yesno` (+ `--defaultno` при `n`) | `y` / `n` |
| `ask_num VAR "Text" min max default` | `--inputbox` | число в диапазоне; иначе `--msgbox` и повтор |
| `ask_menu VAR "Text" default tag item …` | `--menu` | выбранный тег (число) |
| `ask_text VAR "Text" default [regex]` | `--inputbox` | строка; пустая — только где апстрим разрешает |

Ввод читается через `--output-fd 3` (`3>&1 1>&2 2>&3`). `whiptail` возвращает **0** (OK), **1**
(No/Cancel), **255** (ESC) — все вызовы только внутри `if ! …`, иначе `set -e` убьёт установщик.

## Диалоги

Полная таблица — [spec-dialogs.md](spec-dialogs.md) (генерируется `tests/build-inventory.sh` из
`repo/setup.sh`; вручную не править). Сводка: **29** `--yesno`, **5** `--menu` (OPENVPN_PATCH 1-4,
ANTIZAPRET_WARP 1-4, VPN_WARP 1-3, ANTIZAPRET_DNS 1-6, VPN_DNS 1-2), **2** числа (MTU, WARP_MTU),
**3** строки (WARP_ENDPOINT, OPENVPN_HOST, WIREGUARD_HOST). Плюс **один** селектор режима в
начале (см. принцип 0) — он рисуется `read -rp` и в счёт `ask_*` не входит.

Правила отображения:

- Литеральных размеров окон нет ни у одного диалога (тест `check-bootstrap.sh` это
  проверяет): размеры считают `wt_dims()` (вопросы), `wt_msg()` (сообщения об ошибках),
  `wt_textbox()` (сводка настроек).
- Размер терминала берёт `wt_term()`: `COLUMNS`/`LINES` из окружения, если они есть, иначе
  `stty size < /dev/tty`, иначе 24x80. В скрипте `COLUMNS`/`LINES` обычно **не** экспортированы,
  поэтому запасной путь через `stty` обязателен — без него окна считались бы от 80 колонок и
  на телефоне (71 колонка) уезжали за край.
- `--title "AntiZapret VPN setup"`, без `--backtitle`; размер окна считает `wt_dims()` по
  фактическому тексту: ширина — по самой длинной строке (clamp 40..120 и не больше
  `COLUMNS-2`), высота — по числу строк после переноса при внутренней ширине `ширина-4` плюс
  строки списка; если не влезает в `LINES-2` — окно ужимается и добавляется `--scrolltext`
  (подсчёт как в `dietpi-globals:524-560`).
- Повторный диалог: `MTU`, `WARP_MTU`, `WARP_ENDPOINT` при невалидном вводе — сначала `--msgbox`
  с текстом ошибки апстрима, затем **тот же** диалог, дефолт = последнее введённое значение.
  Двух отдельных экранов для этих полей нет — это один диалог (см. факты апстрима).
- Меню: теги — числа `1..N`, в `setup` попадает тег; `--default-item` = встроенный дефолт апстрима.
- ANSI-разметка апстрима (`SOH … ESC[1;32m … STX`) в тексты диалогов не попадает: `wt_clean()`
  вырезает маркеры и SGR-последовательности перед вызовом whiptail (whiptail inline-ANSI не
  разбирает). В plain-ветке остаются апстримные `echo -e` — оно и рисует зелёный цвет.
- Пункты меню newt **не переносит** (пункт — одна строка, хвост обрезается), поэтому все 5 меню
  помечаются `--names`: полная авторская строка («1 MSK-IX+NSDI - …») уходит в текст сообщения
  (там перенос по словам), а в списке под номером стоит короткое имя — часть описания до
  разделителя ` - ` («1  MSK-IX+NSDI»). Номер виден дважды: в тексте (как у автора) и в списке
  (столбец списка — обязательный виджет whiptail); `wt_dims()` учитывает ширину списка.
  Легенда меню DNS воспроизводится целиком, включая строку про `**` (GeoHide) и «Use only if
  this server is geolocated in Russia…».
- `WARP_ENDPOINT`: дефолт `162.159.192.$((RANDOM % 254 + 1)):500` вычисляется **один раз** до
  диалога (иначе повтор диалога подставит другой адрес).
- `OPENVPN_HOST`, `WIREGUARD_HOST`: пустой ввод допустим (апстрим спрашивает «press Enter to skip»).
- Сообщения об ошибках (`Invalid value`, `Invalid domain name`, диапазон числа) — `wt_msg()`:
  размер по тексту, минимум 10 строк, при нехватке места `--scrolltext`.
- Сводка настроек перед установкой — `wt_textbox()`: ширина `COLUMNS-4` (clamp 40..120), высота
  `LINES-4` (минимум 12), `--scrolltext` включён всегда (68 строк в экран не влезают).
  Замерено на dietpi, pty 71x42: окно 38x67, все строки прокручиваются стрелками/PageDown
  (без `--scrolltext` прокрутки нет вовсе — проверено). Побочный эффект newt: в прокручиваемом
  `--textbox` строки текста рисуются без правого бордюра (край остаётся только у рамки и пустых
  строк) — принято сознательно, прокрутка важнее косметики.
- `Proceed with installation?` — `ask_yn PROCEED 'Proceed with installation?' y`; ответ `n` или
  отмена (код 1/255) дают `exit 1`, как и апстримное «нет».

## Валидация

| поле | правило (как в апстриме) | поведение |
|---|---|---|
| `MTU`, `WARP_MTU` | `^[0-9]+$`, 1280..1420 | `--msgbox` с ошибкой, повтор диалога |
| `WARP_ENDPOINT` | пусто или `^[^:]+:[0-9]+$` | то же |
| `OPENVPN_HOST`, `WIREGUARD_HOST` | валидный домен или пусто | то же |
| да/нет, выбор | `^(y|n)$` / `^[1-N]$` | гарантируется типом диалога |

## Сводка перед установкой

После 39-го ответа — `write_setup_file > временный файл` (`mktemp`, удаляется по `EXIT`) и
`--textbox 24 78` с этим блоком и один `--yesno "Proceed with installation?"`. Отказ — код 1, ничего не изменено.
В `QUESTIONS_ONLY` сводка печатается в stdout, подтверждения нет.

## Коды выхода

| код | смысл |
|---|---|
| 0 | успех (в `QUESTIONS_ONLY` — блок напечатан) |
| 1 | отмена пользователем (Cancel/ESC на любом экране), ничего не записано |
| 2-10 | существующие проверки апстрима — не трогаем |

## Приёмка

1. `bash tests/run-headless.sh` → `mode=patched exit=0 keys=68 include=11`, `OK 47 keys matched`, `bootstrap_exit=0`.
2. Диалогов 39: `grep -cE '(ask_yn|ask_num|ask_menu|ask_text) '` в `repo/setup.sh`.
3. В `repo/setup.sh` нет ни одного чтения старого `setup` (проверяется `tests/check-bootstrap.sh`).
4. Отмена на каждом экране → код 1, `/root/antizapret` не тронут.
5. `NO_WHIPTAIL=1` и `AZ_UI=plain` дают результат, идентичный `logs/generated-baseline.txt`.
   `AZ_UI=whiptail` в headless — `OK 47 keys matched` (из 68 строк сравниваются 47, пропуск — `fixtures/skip-keys.txt`).
5a. Селектор: `1`/пусто → whiptail-ветка, `2` → plain, мусор → `Invalid choice` + повтор,
   `AZ_UI=whiptail` без бинаря → код 2 (явный режим молча не подменяется), `AZ_UI=bogus` → код 2;
   stdin не TTY (запуск из pipe, cron, `ssh host 'bash …'` без `-t`) → plain **без вопроса**
   и одна строка `stdin is not a terminal`;
   `AZ_UI=plain AZ_UI-override` не задаёт вопрос; выбор `1` без бинаря → сообщение и plain.
6. `QUESTIONS_ONLY=1` не вызывает `apt-get` (подменный `apt-get` в `tests/check-bootstrap.sh`).
7. `shellcheck -S warning` по `setup.sh` — не больше 2 замечаний (SC2144, SC1010 — baseline).
8. `diff` апстрима: 116-358 (диалоги), бутстрап и 4 хелпера (21-160), 5 строк MTU для `QUESTIONS_ONLY` (254-261), единый writer `write_setup_file` (581-651) и его вызовы (655 — `QUESTIONS_ONLY`, 662 — `--textbox`, 879 — запись файла вместо апстримного `echo`).
9. **Единый writer.** В `repo/setup.sh` список ключей файла настроек встречается ровно один раз (`grep -cE '^SETUP_DATE='` = 1). Writer печатает 68 строк = `SETUP_DATE` + 67 ключей в апстримном порядке и составе; список ключей сверен с `git show main:setup.sh` (блок «Сохраняем настройки») — совпадение построчное.
10. Сверка с фикстурой двусторонняя: `DIFF` (значения), `MISSING` (есть в фикстуре, нет в генерате), `EXTRA` (есть в генерате, нет в фикстуре). Пропускаются только ключи из `fixtures/skip-keys.txt` (21): `SETUP_DATE`, 12 `WARP_*` и 8 сетевых (`DEFAULT_*`, `OUT_*`, `CLIENT_IP`, `FAKE_IP`).
11. `tests/check-bootstrap.sh` — три независимых прогона со своей копией ответов: явный `AZ_UI=whiptail` через подменный whiptail, запуск без `AZ_UI`/`NO_WHIPTAIL` и без TTY (обязан быть plain, подменный whiptail вызываться не должен), `NO_WHIPTAIL=1`. В каждом: `SETUP_DATE`, ровно 11 `INCLUDE`-ключей, отсутствие `apt-get`, сверка с фикстурой.
