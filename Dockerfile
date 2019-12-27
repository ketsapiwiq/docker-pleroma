FROM alpine:3.10 as bootstrap

ENV GOSU_VERSION 1.11
RUN set -eux; \
    apk add --no-cache ca-certificates dpkg gnupg; \
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
    wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
# verify the signature
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
    command -v gpgconf && gpgconf --kill all || :; \
    rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
# verify that the binary works
    chmod +x /usr/local/bin/gosu; \
    gosu --version; \
    gosu nobody true

FROM elixir:1.9-alpine as build

ARG RELEASE="release/1.1.7"
ARG MIX_ENV=prod

RUN apk add git gcc g++ musl-dev make \
&&  cd /; git clone -b $RELEASE https://git.pleroma.social/pleroma/pleroma.git \
&&  cd pleroma \
&&  sed -i -e '/version: version/s/)//' -e '/version: version/s/version(//' mix.exs \
&&  echo "import Mix.Config" > config/prod.secret.exs \
&&  mix local.hex --force \
&&  mix local.rebar --force \
&&  mix deps.get --only prod \
&&  mkdir -p /release \
&&  mix release --path /release

FROM alpine:3.10

LABEL maintainer="ken@epenguin.com"

ARG UID=1000
ARG GID=1000
ARG HOME=/opt/pleroma
ARG DATA=/var/lib/pleroma

ENV DOMAIN=localhost \
    INSTANCE_NAME="Pleroma" \
    ADMIN_EMAIL="admin@localhost" \
    NOTIFY_EMAIL="info@localhost" \
    DB_HOST="db" \
    DB_NAME="pleroma" \
    DB_USER="pleroma" \
    DB_PASS="pleroma"

RUN apk add --no-cache \
        tini \
	curl \
	ncurses \
	postgresql-client \
&&  addgroup --gid "$GID" pleroma \
&&  adduser --disabled-password --gecos "Pleroma" --home "$HOME" --ingroup pleroma --uid "$UID" pleroma \
&&  mkdir -p ${DATA}/uploads \
&&  mkdir -p ${DATA}/static \
&&  chown -R pleroma:pleroma ${DATA} \
&&  mkdir -p /etc/pleroma \
&&  chown -R pleroma:root /etc/pleroma

COPY --from=bootstrap --chown=0:0 /usr/local/bin/gosu /usr/local/bin
COPY --from=build --chown=pleroma:0 /release ${HOME}

COPY ./config/docker.exs /etc/pleroma/config.exs
COPY ./bin/* /usr/local/bin
COPY ./entrypoint.sh /entrypoint.sh

VOLUME $DATA

EXPOSE 4000

STOPSIGNAL SIGTERM

HEALTHCHECK \
    --start-period=10m \
    --interval=1m \ 
    CMD curl --fail http://localhost:4000/api/v1/instance || exit 1

ENTRYPOINT ["tini", "--", "/entrypoint.sh"]