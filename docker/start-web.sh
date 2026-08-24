#!/bin/sh
set -eu

python manage.py migrate --noinput
python manage.py collectstatic --noinput

exec gunicorn \
    --bind 0.0.0.0:8001 \
    --workers "${GUNICORN_WORKERS:-2}" \
    --threads "${GUNICORN_THREADS:-2}" \
    --timeout "${GUNICORN_TIMEOUT:-120}" \
    --max-requests "${GUNICORN_MAX_REQUESTS:-5000}" \
    --max-requests-jitter "${GUNICORN_MAX_REQUESTS_JITTER:-500}" \
    statuspage.wsgi
