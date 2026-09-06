# Политика безопасности

[English version](SECURITY.md)

## Область действия

Security reports для этого репозитория должны относиться к проектным Docker, Terraform, automation, configuration и application changes. Встроенное приложение Status-Page закреплено на архивированном upstream release `v2.5.1`; проблемы исходного приложения сначала следует сверять с оригинальным репозиторием.

## Поддерживаемый код

Поддерживается только актуальная ветка `main`. Исторические branches, демонстрационные deployments и архивированное upstream-приложение не сопровождаются как отдельные release lines.

## Как сообщить об уязвимости

Используй private vulnerability reporting этого GitHub-репозитория. Укажи:

- затронутый файл или компонент;
- шаги воспроизведения;
- ожидаемое влияние;
- возможное исправление, если оно известно.

Не создавай public issue с credentials, tokens, private infrastructure values или деталями эксплуатации. Production secrets не должны попадать в source, examples, issues или logs.

## Ответственность при deployment

Оператор deployment отвечает за проверку dependencies, rotation credentials, security updates и access policies целевого account. Автоматизация в репозитории даёт воспроизводимые controls, но не является managed security service.
