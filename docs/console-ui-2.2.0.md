# Макет консольного интерфейса v2.2.0

Рабочий образец сообщений для issue #5. Это только текстовый макет: запуск команд, скачивание и установка здесь не выполняются. Цвета добавляются позже; каждое состояние всегда читается текстом. Числа, адреса и имена ниже — пример, не результат текущей онлайн-проверки.

## Русский

### Инвентаризация

```text
Intel Driver Manager — Инвентаризация
Компьютер: Example Laptop | Windows 11 x64
Режим: только просмотр. Загрузки и установки нет.

УСТРОЙСТВА
Wi-Fi       Intel Wi-Fi 6 AX201       Установлено: 24.70.0.3
Bluetooth   Intel Wireless Bluetooth Установлено: 24.80.0.2
Графика     Intel UHD Graphics       Установлено: 31.0.101.2145

ИТОГ: обнаружено 3 устройства Intel. Наличие обновлений здесь не проверялось.
Журнал: <путь к файлу>
```

### Проверка кандидата и CAB

```text
Этап 1/4 — Проверка устройства
Intel Wireless Bluetooth | ID: USB\VID_8087&PID_0026...
Установлено: 24.80.0.2

Этап 2/4 — Источник
Закреплённый CAB с download.windowsupdate.com; дата проверки: <дата запуска>.
Размер: около 2,5 МБ. Загрузка только после вашего согласия.
Отказ: обычная проверка версий продолжится без данных этого CAB.

ВЫБОР
[1] Скачать и проверить CAB
[2] Пропустить (по умолчанию)
Введите 1 или 2:

Этап 3/4 — Проверка файла
[ПРОЙДЕНО] Хеш CAB совпадает с закреплённым значением.
[ПРОЙДЕНО] INF соответствует байтам из CAB.
[ПРОЙДЕНО] Подпись CAT действительна.
[НУЖНА ПРОВЕРКА] Связь INF с этим CAT не проверена: SignTool отсутствует.

Этап 4/4 — Результат
NO_NEWER_VERSION: в проверенном CAB версия совпадает с установленной.
Новые выпуски после даты этого пакета здесь не обнаруживаются.
Драйвер не устанавливался. Журнал: <путь к файлу>
```

### Вспомогательный инструмент

```text
Дополнительный инструмент — Microsoft SignTool
Зачем: подтвердить, что извлечённый INF входит именно в извлечённый CAT.
Источник: Microsoft Windows SDK BuildTools (NuGet), около 21 МБ.
Проверки: SHA-512 пакета и цифровая подпись signtool.exe.
Хранение: локальная папка IntelWiFiBTManager\Tools; системный SDK не устанавливается.
Отказ: проверка продолжится, связь INF/CAT останется UNVERIFIED.
[1] Скачать и проверить SignTool
[2] Пропустить (по умолчанию)
Введите 1 или 2:
```

### Установка (граница ответственности)

```text
Следующий этап — передача управления установщику Intel / утилите FirstEverTech
Источник, версия и предполагаемое действие: <конкретные данные>.
Менеджер завершит свои проверки; далее сообщения показывает внешняя программа.
Возможен временный разрыв Wi-Fi/Bluetooth или перезапуск графического драйвера.
[1] Запустить внешнюю программу
[2] Отменить (по умолчанию)
Введите 1 или 2:
```

## English

```text
Intel Driver Manager — Inventory
Mode: read-only. No download or installation.
Wi-Fi       Intel Wi-Fi 6 AX201       Installed: 24.70.0.3
Bluetooth   Intel Wireless Bluetooth Installed: 24.80.0.2
Graphics    Intel UHD Graphics       Installed: 31.0.101.2145
RESULT: 3 Intel devices found. This inventory did not check for updates.

Step 1/4 — Device
Intel Wireless Bluetooth | installed: 24.80.0.2

Step 2/4 — Source
Pinned CAB from download.windowsupdate.com; reviewed: <run date>.
About 2.5 MB. Download requires consent.
Declining keeps the ordinary version report.
[1] Download and verify CAB
[2] Skip (default)

Step 3/4 — Evidence
[PASS] CAB hash matches the pinned value.
[PASS] INF bytes match the CAB entry.
[PASS] CAT signature is valid.
[REVIEW] Exact INF/CAT membership needs SignTool.

Optional tool — Microsoft SignTool
Purpose: prove this extracted INF belongs to this extracted CAT.
Source: Microsoft Windows SDK BuildTools (NuGet), about 21 MB.
Package SHA-512 and executable signature are checked.
Declining leaves INF/CAT membership UNVERIFIED.
[1] Download and verify SignTool
[2] Skip (default)

Step 4/4 — Result
NO_NEWER_VERSION: this CAB has the same version as the installed driver.
This check does not search all later releases. No driver was installed.

Before installation — external program
The Intel installer or FirstEverTech utility will show its own screens.
[1] Start the external program
[2] Cancel (default)
```

## Правила реализации

- Не показывать процент без измеряемых байтов и известного размера; для проверки подписи показывать текущий шаг.
- В журнал записывать текстовый итог каждого этапа, выбор пользователя и причину ошибки; цвет и анимация не несут единственную информацию.
- При узком окне сведения об устройстве и версии переносить на отдельные строки, не обрезать путь к журналу.
- Не называть совпадение с одним пакетом полным поиском обновлений.
