# Настройка сервера

В этом гайде будет описана структура файлов на сервере для загрузки.

## Файлы конфигурации

### `remote_versions.cfg`

В этом файле содержатся все доступные на сервере версии игры. Он состоит из нескольких секций, которые выглядят следующим образом:
```ini
[<код версии>]

name="<имя версии>"
engine_version="<версия движка>"
beta=true/false
platforms=["<платформа>", "<платформа>", ...]
```
где:
 - **код версии** - целое число, отвечающее за то, в каком порядке будут показаны версии в лаунчере.
 - **имя версии** - строка с названием версии (например, `2.0.0.22`).
 - **версия движка** - строка с версией движка (например, `4.4.dev4`), которую использует эта версия игры. Это позволяет экономить место на диске - нет необходимости для нескольких версий с одинаковой версией движка скачивать этот движок несколько раз. Эта версия должна присутствовать в `remote_engine_versions.cfg`.
 - **платформа** - строка с именем операционной системы, для которой эта версия предназначена. На данный момент поддерживаются только `Linux` и `Windows`.
 - **beta** - установите `true` если хотите чтобы к названию версии добавился суффикс "(БЕТА)". Иначе оставьте `false`.

### `remote_engine_versions.cfg`

В этом файле содержатся все доступные на сервере версии движка. Он состоит из нескольких секций, которые выглядят следующим образом:
```ini
[<версия движка>]

editions=["<платформа>.<архитектра процессора>", "<платформа>.<архитектра процессора>", ...]
```
где:
 - **архитектра процессора** - строка с архитектурой процессора, для которой был скомпилирован движок. Чаще всего это `x86_64` или `arm64`.
 - **платформа** - строка с именем операционной системы, для которой эта версия предназначена. На данный момент поддерживаются только `Linux` и `Windows`.

## Файлы пакетов (`*.pck`)

Файлы пакетов должны лежать в подкаталоге `packs/` в виде ZIP-архивов.
В этих ZIP-архивах должен быть файл `pack` (без расширения, переименованный `*.pck`), а само имя архива должно быть формата (в нижнем регистре!) `pack.<код версии>.<платформа>.zip`, где:
 - **платформа** - строка с именем операционной системы, для которой эта версия предназначена, одна из ранее указанных в `remote_versions.cfg`. На данный момент поддерживаются только `linux` и `windows`. (ещё раз, в нижнем регистре!)
 - **код версии** - ранее указанный в `remote_versions.cfg`.
Примеры:
```
pack.10.windows.zip
pack.11.linux.zip
```

## Исполняемые файлы движков

Исполняемые файлы движков должны лежать в подкаталоге `engines/` в виде ZIP-архивов.
В этих ZIP-архивах должен быть файл `engine` (без расширения, переименованный исполняемый файл движка), а само имя архива должно быть формата (в нижнем регистре!) `engine.<версия движка>.<издание>.zip`, где:
 - **версия движка** - ранее указанная в `remote_engine_versions.cfg`.
 - **издание** - одна из ранее указанных `editions`, но в нижнем регистре.
Примеры:
```
engine.4.4.dev4.linux.x86_64.zip
engine.4.4.stable.windows.x86_64.zip
engine.4.5.dev3.linux.arm64.zip
```