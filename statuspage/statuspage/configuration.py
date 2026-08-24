"""Environment-based configuration for local Docker and ECS deployments."""

import os


def env(name, default=''):
    return os.getenv(name, default)


def env_bool(name, default=False):
    return env(name, str(default)).lower() in {'1', 'true', 'yes', 'on'}


def env_list(name, default=''):
    return [item.strip() for item in env(name, default).split(',') if item.strip()]


ALLOWED_HOSTS = env_list(
    'STATUS_PAGE_ALLOWED_HOSTS',
    'localhost,127.0.0.1,web,nginx',
)

DATABASE = {
    'NAME': env('POSTGRES_DB', 'statuspage'),
    'USER': env('POSTGRES_USER', 'statuspage'),
    'PASSWORD': env('POSTGRES_PASSWORD', 'statuspage-local'),
    'HOST': env('POSTGRES_HOST', 'postgres'),
    'PORT': env('POSTGRES_PORT', '5432'),
    'CONN_MAX_AGE': int(env('POSTGRES_CONN_MAX_AGE', '300')),
}

REDIS = {
    'tasks': {
        'HOST': env('REDIS_HOST', 'redis'),
        'PORT': int(env('REDIS_PORT', '6379')),
        'PASSWORD': env('REDIS_PASSWORD'),
        'DATABASE': int(env('REDIS_TASKS_DATABASE', '0')),
        'SSL': env_bool('REDIS_SSL'),
    },
    'caching': {
        'HOST': env('REDIS_HOST', 'redis'),
        'PORT': int(env('REDIS_PORT', '6379')),
        'PASSWORD': env('REDIS_PASSWORD'),
        'DATABASE': int(env('REDIS_CACHE_DATABASE', '1')),
        'SSL': env_bool('REDIS_SSL'),
    },
}

SITE_URL = env('STATUS_PAGE_SITE_URL', 'http://localhost:8081')
SECRET_KEY = env('STATUS_PAGE_SECRET_KEY', 'local-development-key-change-before-deployment')
DEBUG = env_bool('STATUS_PAGE_DEBUG')
CSRF_TRUSTED_ORIGINS = env_list('STATUS_PAGE_CSRF_TRUSTED_ORIGINS')
MEDIA_ROOT = env('STATUS_PAGE_MEDIA_ROOT', '/srv/status-page/media')
TIME_ZONE = env('STATUS_PAGE_TIME_ZONE', 'UTC')
PLUGINS = []
PLUGINS_CONFIG = {}
