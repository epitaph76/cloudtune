# Resume Landing

Статический лендинг-резюме для домена `https://resume.api-mp3-player.ru`.

## Содержимое

- `index.html` - основная страница резюме.

## Быстрое обновление на сервере

```bash
scp -r landing/resume/* root@168.222.252.159:/var/www/resume.api-mp3-player.ru/html/
```

Проверка:

```bash
curl -I https://resume.api-mp3-player.ru
```
