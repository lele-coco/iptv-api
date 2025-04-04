FROM python:3.13-alpine AS builder

ARG LITE=False
ARG NGINX_VER=1.27.4
ARG RTMP_VER=1.2.2

WORKDIR /app

COPY Pipfile* ./

RUN apk update && apk add --no-cache gcc musl-dev python3-dev libffi-dev zlib-dev jpeg-dev wget make pcre-dev openssl-dev \
  && pip install pipenv \
  && PIPENV_VENV_IN_PROJECT=1 pipenv install --deploy \
  && if [ "$LITE" = False ]; then pipenv install selenium; fi

RUN wget https://nginx.org/download/nginx-${NGINX_VER}.tar.gz && \
    tar xzf nginx-${NGINX_VER}.tar.gz

RUN wget https://github.com/arut/nginx-rtmp-module/archive/v${RTMP_VER}.tar.gz && \
    tar xzf v${RTMP_VER}.tar.gz

WORKDIR /app/nginx-${NGINX_VER}
RUN ./configure \
    --add-module=/app/nginx-rtmp-module-${RTMP_VER} \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --with-http_ssl_module \
    --with-debug && \
    make && \
    make install

FROM python:3.13-alpine

ARG APP_WORKDIR=/iptv-api
ARG LITE=False

ENV APP_WORKDIR=$APP_WORKDIR
ENV LITE=$LITE
ENV APP_HOST="localhost"
ENV APP_PORT=8000
ENV PATH="/.venv/bin:/usr/local/nginx/sbin:$PATH"
ENV UPDATE_CRON="0 22,10 * * *"

WORKDIR $APP_WORKDIR

COPY . $APP_WORKDIR

COPY --from=builder /app/.venv /.venv
COPY --from=builder /usr/local/nginx /usr/local/nginx

RUN mkdir -p /var/log/nginx && \
  ln -sf /dev/stdout /var/log/nginx/access.log && \
  ln -sf /dev/stderr /var/log/nginx/error.log

RUN apk update && apk add --no-cache dcron ffmpeg pcre \
  && if [ "$LITE" = False ]; then apk add --no-cache chromium chromium-chromedriver; fi

EXPOSE $APP_PORT 8080

COPY entrypoint.sh /iptv-api-entrypoint.sh

COPY config /iptv-api-config

COPY nginx.conf /etc/nginx/nginx.conf

RUN mkdir -p /usr/local/nginx/html

COPY stat.xsl /usr/local/nginx/html/stat.xsl

RUN chmod +x /iptv-api-entrypoint.sh

ENTRYPOINT /iptv-api-entrypoint.sh
