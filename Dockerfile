FROM python:3.10-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    STATUS_PAGE_CONFIGURATION=statuspage.configuration

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        build-essential \
        libffi-dev \
        libjpeg62-turbo-dev \
        libpq-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/status-page

COPY requirements.txt ./
RUN pip install --upgrade pip wheel \
    && pip install -r requirements.txt

COPY . .

RUN mkdir -p /srv/status-page/static /srv/status-page/media \
    && chmod +x docker/entrypoint.sh docker/start-web.sh

WORKDIR /opt/status-page/statuspage

EXPOSE 8001

ENTRYPOINT ["/opt/status-page/docker/entrypoint.sh"]
CMD ["/opt/status-page/docker/start-web.sh"]
