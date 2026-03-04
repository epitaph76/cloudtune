# Resume Landing

Статический resume-лендинг для домена `https://resume.api-mp3-player.ru`.

## Содержимое

- `index.html` — основная страница резюме.
- `cases.html` — страница с ответами на кейсы.
- `case-answers.txt` — исходный текст ответов, который используется на `cases.html`.

## Локальный просмотр

```bash
cd landing/resume
python -m http.server 8082
```

Открыть: `http://localhost:8082`.

## Обновление на сервере вручную

```bash
scp -r landing/resume/* root@168.222.252.159:/var/www/resume.api-mp3-player.ru/html/
```

## Проверка после обновления

```bash
curl -I https://resume.api-mp3-player.ru
```

Примечание: автоматический деплой resume-лендинга также выполняется через `backend/scripts/deploy-from-github.sh`.
