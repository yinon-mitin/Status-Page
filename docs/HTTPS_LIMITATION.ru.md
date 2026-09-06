# Область HTTPS

[English version](HTTPS_LIMITATION.md)

AWS-демонстрация использует HTTP на load balancer. HTTPS намеренно не входит в реализованный scope: учебный AWS account не предоставлял нужных ACM permissions.

Это граница deployment, а не изменение архитектуры приложения. Сеть и Terraform сохраняют работу с сертификатом отдельным шагом, поэтому HTTPS можно включить в account с доступом к ACM.

## Включение HTTPS в другом account

1. Запросить ACM certificate в том же AWS Region, где работает ALB.
2. Добавить ACM DNS validation record в authoritative DNS zone.
3. Дождаться статуса сертификата `ISSUED`.
4. Передать ARN сертификата в Terraform.
5. Создать HTTPS listener и перенаправление HTTP на HTTPS.
6. Обновить application URL, trusted origins и secure-cookie settings.
7. Проверить certificate chain, hostname, redirect, health check и login flow.

Нельзя направлять DNS на HTTPS listener до выпуска и подключения сертификата. Демонстрационный endpoint нельзя называть HTTPS-enabled, пока не проверен весь путь через browser.
