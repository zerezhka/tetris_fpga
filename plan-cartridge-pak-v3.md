# План: v3 «картридж-pak» — ROM + звук + лицо в одном файле (1-click load)

Статус: **код+тесты готовы, коммит `6d68b3f`; DORMANT до пересборки ПЛИС**
(2026-07-06). Шаги 1–4 сделаны (формат v3, тулинг, RTL-лоадер, HT943-микс,
регрессия all-PASS). Остался шаг 5 — `quartus_sh` пересборка + деплой rbf и
v3-паков на железо (под «go» пользователя). Цель: `.pak` — самодостаточный
картридж, пользователь выбирает ОДИН файл, грузится всё (программа, звук,
лицо, профиль). Убирает нужду в mgl и в загрузке 3 файлов.

## Что сейчас (v2)

Три отдельных потока через ioctl:
- **ROM** (`FC1`, .bin, idx 1) → `core_rom` (12-bit addr, **4096 B**) + CRC32
  автодетект профиля (`HT943.sv` ROM/SROM DOWNLOAD).
- **Звук** (`FC2`, .sro, idx 2) → `core_srom` (10-bit addr, **640 B** факт.).
- **Pak** (`FC3`, .pak, idx 3) → `ht943_pak_loader` → лицо (pixmap/segtab/
  geotab/inkmask) + config (клоки/таймеры/wakeup/jmap/spd/fx/frame).

Источники данных (в репе): ROM = `mask_options.rom_path` (.bin, 4096B);
звук = `mask_options.sound_rom_path` (.srom, 640B; E88 делит srom с E23).

## Что делаем (v3)

Дописываем в pak две секции — **rom (4096B)** и **sound (1024B**, .srom
640B + zero-pad до 10-bit пространства**)** — и учим `ht943_pak_loader`
маршрутизировать их в `core_rom`/`core_srom`. Профиль уже приходит из
config-секции пака (`pak_loaded` override), CRC-автодетект остаётся только
для «голого .bin».

Размер: PACK_SIZE 110416 → **115536** (+5120). VERSION 2 → **3**.
Смещения rom/sound — хардкодом-localparam в генераторе И в лоадере
(как уже сделано для inkmask; без новых полей заголовка). `done`
переезжает с последнего байта inkmask на последний байт sound.

Совместимость: v3-пак длиннее, но секции config..pixmap..inkmask на тех же
смещениях. Старый (v2) битстрим дочитает до своей границы и проигнорирует
rom/sound-хвост (лицо загрузит, но ROM/звук — нет; для них на v2-железе
всё ещё нужны FC1/FC2). Полный 1-click — только на v3-битстриме.

## Шаги (атомарные коммиты)

1. **Формат + тулинг + тесты** (без железа, полностью проверяемо):
   - `tools/gen_device_pack.py`: VERSION=3, PACK_SIZE, `ROM_OFF`/`SOUND_OFF`,
     `ROM_SIZE=4096`, `SOUND_SIZE=1024`; `build_rom_bytes()` (из
     `mask.rom_path`), `build_sound_bytes()` (из `mask.sound_rom_path`,
     zero-pad 640→1024); дописать в `build_pack`; `parse_pack` → `rom`,
     `sound`.
   - `sim/tb_ht943_pak_loader.cpp` + `sim/test_pak_loader.py`: захватывать
     rom/srom-записи, сверять с `parse_pack`.
   - `sim/test_device_pack.py` roundtrip.
   - Прогнать `sim/regression.py` → всё PASS.
2. **RTL `ht943_pak_loader.sv`**: секции rom/sound → выходы
   `rom_wr/rom_addr[11:0]/rom_data[7:0]`, `srom_wr/srom_addr[9:0]/
   srom_data[7:0]`; `PACK_SIZE`; `done` на последний байт sound.
   Verilator smoke.
3. **`HT943.sv`**: OR-микс pak-loader rom/srom в `core_rom`/`core_srom`
   (F1/F2-путь остаётся для homebrew); pak addr-bound 110416→115536;
   комментарий, что FC3 теперь грузит всё. (CONF_STR менять не обязательно —
   FC3 в одиночку = картридж.)
4. **Регенерация**: собрать все 6 v3-паков; roundtrip; `test_lcd_assets`.
5. **Пересборка + деплой (под «go» пользователя)**: `quartus_sh --flow
   compile HT943` (~15 мин), проверить slack в `.sta.rpt`, `scp` rbf +
   v3-паки на `root@192.168.1.235`, проверить 1-click на железе.

## НЕ в этом инкременте

- **HT943_2P** — строится ПОВЕРХ картриджа (вставил один картридж → оба
  играют), отдельный инкремент. См. `brickgame-fpga-roadmap.md` §8.

## Проверка

- `sim/regression.py` all-PASS (вкл. rom/sound в pak-loader тесте).
- На железе (v3-битстрим): выбрал один `.pak` из `_Console`/браузера →
  играбельно со звуком, без FC1/FC2 и без mgl.
