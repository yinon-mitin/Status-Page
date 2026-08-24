#!/bin/sh
set -eu

python - <<'PY'
import os
import socket
import time

targets = [
    (os.getenv('POSTGRES_HOST', 'postgres'), int(os.getenv('POSTGRES_PORT', '5432')), 'PostgreSQL'),
    (os.getenv('REDIS_HOST', 'redis'), int(os.getenv('REDIS_PORT', '6379')), 'Redis'),
]

for host, port, label in targets:
    for attempt in range(60):
        try:
            with socket.create_connection((host, port), timeout=2):
                print(f'{label} is reachable at {host}:{port}')
                break
        except OSError:
            if attempt == 59:
                raise SystemExit(f'{label} did not become reachable at {host}:{port}')
            time.sleep(1)
PY

exec "$@"
