# Происхождение upstream и политика сопровождения

Этот репозиторий — неофициальный учебный DevOps fork проекта [Status-Page](https://github.com/Status-Page/Status-Page), основанный на upstream release tag [`v2.5.1`](https://github.com/Status-Page/Status-Page/releases/tag/v2.5.1).

Оригинальный проект был архивирован в октябре 2025 года, а объявленный период security support завершился 31 декабря 2025 года. Поэтому проект закрепляет приложение на `v2.5.1`; это не активно сопровождаемый upstream service.

Fork сохраняет upstream history и лицензию. Специфичная для проекта работа намеренно отделена в Docker-файлы, `docker-compose.yml`, `.github/workflows/`, `terraform/` и `docs/`. Изменения приложения ограничены configuration adapter на переменных окружения и endpoint `/healthz`, необходимым load balancer.

Сохраняй remote `upstream` для подтверждения происхождения. Считай upstream code фиксированной базой: перед добавлением будущих security patches их необходимо явно проверить и документировать.
