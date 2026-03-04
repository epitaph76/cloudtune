# CloudTune Landing

Статический лендинг для домена `https://api-mp3-player.ru`.

## Содержимое

- `index.html` — основная страница проекта.
- `assets/media/desktop-demo.gif` — desktop-демо.
- `assets/media/android-demo.mp4` — android-демо.
- `assets/screens/*.svg` — иллюстрации интерфейса.

## Ссылки на артефакты

В `landing/index.html` используются ссылки на файлы в web-root:

- `/cloudtune_win.zip`
- `/cloudtune_andr.apk`

Файлы должны лежать рядом с `index.html` в директории сайта.

## Локальный просмотр

```bash
cd landing
python -m http.server 8081
```

Открыть: `http://localhost:8081`.

## Обновление на сервере вручную

```bash
scp -r landing/* root@168.222.252.159:/var/www/api-mp3-player.ru/html/
scp cloudtune_win.zip cloudtune_andr.apk root@168.222.252.159:/var/www/api-mp3-player.ru/html/
```

## Проверка после обновления

```bash
curl -I https://api-mp3-player.ru
curl -I https://api-mp3-player.ru/cloudtune_win.zip
curl -I https://api-mp3-player.ru/cloudtune_andr.apk
```

Примечание: автоматический деплой лендинга также выполняется через `backend/scripts/deploy-from-github.sh`.
