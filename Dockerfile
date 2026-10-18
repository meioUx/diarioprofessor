ARG RUBY_VERSION=2.7.8

# Debian 11 (bullseye) é a única base viável para o Ruby 2.7: não há imagem
# oficial ruby:2.7.x para bookworm e o 2.7 não compila com OpenSSL 3.
# Suporte regular encerrado em 14/08/2024 e LTS em 31/08/2026: a base não recebe
# mais correção de segurança. 2.7.8/bullseye é degrau para o Ruby 3, não destino.
FROM ruby:${RUBY_VERSION}-slim-bullseye AS base

ARG GEM_VERSION=3.3.22
ARG BUNDLER_VERSION=2.4.22

ENV APP_PATH /app
ENV BUNDLE_PATH /box

# Bullseye packages are available from the official Debian archive.
RUN set -e; \
    sed -i 's|http://deb.debian.org|https://archive.debian.org|g' /etc/apt/sources.list; \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get -o Acquire::Retries=3 update --allow-releaseinfo-change; \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
      build-essential \
      git \
      libpq-dev \
      shared-mime-info \
      imagemagick \
      curl \
      ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS via NodeSource (replaces Debian's outdated Node 10.x)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource-setup.sh && \
    bash /tmp/nodesource-setup.sh && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends nodejs && \
    rm -f /tmp/nodesource-setup.sh && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get clean
RUN npm i -g yarn
RUN gem update --system ${GEM_VERSION}
RUN gem install bundler -v ${BUNDLER_VERSION}

RUN mkdir $APP_PATH

WORKDIR $APP_PATH

FROM base AS application

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_FROZEN=true \
    DISABLE_SPRING=1 \
    RAILS_SERVE_STATIC_FILES=1 \
    RAILS_LOG_TO_STDOUT=1

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --production=false
COPY . .
COPY config/database.render.yml config/database.yml
COPY config/secrets.render.yml config/secrets.yml
RUN cp public/404.html.sample public/404.html && \
    cp public/500.html.sample public/500.html && \
    mkdir -p tmp/pids log public/uploads && \
    sed -i 's/\r$//' script/render-start && \
    SECRET_KEY_BASE=build-only-placeholder-not-a-runtime-secret \
    NODE_OPTIONS=--openssl-legacy-provider bundle exec rake assets:precompile

EXPOSE 10000
CMD ["/bin/bash", "script/render-start"]
