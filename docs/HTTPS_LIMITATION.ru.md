# Ограничение HTTPS и восстановление ACM

## Текущий статус

`http://status.yifilter.uk/` намеренно остаётся **HTTP-only demonstration endpoint**. Это живой ECS/ALB deployment, но он **не готов к HTTPS production**. На ALB существует только HTTP listener; redirect HTTP→HTTPS не настроен.

Причина — не дефект приложения или Terraform. У AWS identity, доступной проекту, нет ACM permissions, нужных для запроса и DNS validation public certificate. Зафиксированный отказ включает `acm-pca:ListCertificateAuthorities`; запрос сертификата также требует соответствующих ACM permissions для public certificate. Граница доступа не обходится, а certificate/private key не попадает в GitHub или Terraform state.

Пока ACM выполняет DNS validation, Cloudflare должен оставаться в режиме **DNS only**. Proxy record может скрыть или изменить validation path и не входит в поддерживаемую процедуру восстановления.

## Нужный AWS-доступ

AWS administrator должен выдать оператору least-privilege policy, достаточную для:

- запроса public ACM certificate для `status.yifilter.uk` в `il-central-1`;
- чтения статуса certificate и validation records до `ISSUED`;
- прикрепления выданного certificate к существующему production ALB HTTPS listener;
- создания или обновления ALB listener и HTTP-to-HTTPS redirect через reviewed Terraform change.

Нужен минимальный scope, который поддерживает AWS, для hostname и существующего ALB. Нельзя выдавать `AdministratorAccess`, импортировать private key или помещать certificate material в repository Variables/Secrets.

## Процедура восстановления

1. Оставить Cloudflare DNS record `status.yifilter.uk` в режиме **DNS only**.
2. Попросить administrator выдать человеку-оператору ACM/ELBv2 permissions выше. IAM roles остаются manually managed bootstrap boundary: Terraform не управляет IAM roles и policies.
3. В protected branch сделать reviewed Terraform change: ACM certificate, HTTPS listener на 443 и redirect с 80. Не менять ECS, RDS, Redis и legacy `statuspage-dev-*` resources.
4. Выполнить `terraform fmt -check -recursive`, `terraform validate`, TFLint при наличии и явный production plan. Убедиться, что план затрагивает только нужные `yinon-status-page-*` ingress/certificate resources.
5. Применить одобренный план. Точно перенести ACM DNS validation CNAME в Cloudflare DNS; proxy record не включать.
6. Дождаться статуса ACM `ISSUED`, затем проверить, что certificate прикреплён к ALB HTTPS listener, а HTTP listener делает redirect на HTTPS.
7. Проверить снаружи: `https://status.yifilter.uk/`, `https://status.yifilter.uk/healthz`, hostname/chain certificate и HTTP redirect. Зафиксировать evidence в `docs/DELIVERY_EVIDENCE.md`.

Пока все семь шагов не завершены, документация и release checks обязаны описывать public endpoint только как HTTP-only.
