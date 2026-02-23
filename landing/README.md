# CloudTune Landing

Статический лендинг для домена `https://api-mp3-player.ru`.

## Содержимое

- `index.html` - основная страница с описанием проекта и ссылками на загрузку.
- `assets/media/desktop-demo.gif` - GIF-демо desktop версии.
- `assets/media/android-demo.mp4` - видео-демо Android версии.

## Что важно для ссылок скачивания

В `index.html` используются ссылки:

- `/cloudtune_win.zip`
- `/cloudtune_andr.apk`

Эти файлы должны лежать в web-root рядом с `index.html`.

## Быстрое обновление на сервере

```bash
scp -r landing/* root@168.222.252.159:/var/www/api-mp3-player.ru/html/
scp cloudtune_win.zip cloudtune_andr.apk root@168.222.252.159:/var/www/api-mp3-player.ru/html/
```

Проверка:

```bash
curl -I https://api-mp3-player.ru
curl -I https://api-mp3-player.ru/cloudtune_win.zip
curl -I https://api-mp3-player.ru/cloudtune_andr.apk
```
