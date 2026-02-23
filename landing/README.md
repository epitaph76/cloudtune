# CloudTune Landing

Статический лендинг для домена `https://api-mp3-player.ru`.

## Содержимое

- `index.html` - главная страница с описанием проекта.
- `assets/screens/*.svg` - скриншоты интерфейса для секции галереи.

## Быстрое обновление на сервере

```bash
scp -r landing/* root@168.222.252.159:/var/www/api-mp3-player.ru/html/
```

После копирования можно проверить:

```bash
curl -I https://api-mp3-player.ru
```
