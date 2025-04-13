FROM php:8.4-fpm AS base

ARG WORKDIR=/var/www/backend
ENV APP_WORKDIR=${WORKDIR}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        libicu-dev \
        libpq-dev \
        libzip-dev \
        unzip \
        zip; \
    rm -rf /var/lib/apt/lists/*

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

RUN docker-php-ext-install -j"$(nproc)" \
        intl \
        opcache \
        pdo_pgsql \
        zip

WORKDIR ${APP_WORKDIR}

RUN mkdir -p ${APP_WORKDIR} \
    && chown -R www-data:www-data ${APP_WORKDIR}

COPY .docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini
COPY .docker/php/entrypoint.sh /var/entrypoint.sh
RUN chmod +x /var/entrypoint.sh

ENTRYPOINT ["/var/entrypoint.sh"]

FROM base AS dev

ARG USERNAME=developer

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        figlet \
        sudo \
        zsh; \
    rm -rf /var/lib/apt/lists/*

RUN echo "su - ${USERNAME}" > /root/.bashrc \
    && useradd -m -s /bin/zsh ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && chown -R ${USERNAME}:${USERNAME} ${APP_WORKDIR}

USER ${USERNAME}

RUN bash -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" "" --unattended

RUN git config --global --add safe.directory ${APP_WORKDIR}

RUN cat <<'EOF' > $HOME/.zshrc
export ZSH="$HOME/.oh-my-zsh"
DISABLE_AUTO_UPDATE="true"
DISABLE_UPDATE_PROMPT="true"
ZSH_THEME="ys"
source "$ZSH/oh-my-zsh.sh"
alias clear="clear; figlet . : Gryf : ."
clear
EOF

FROM base AS prod

COPY --chown=www-data:www-data backend/ ${APP_WORKDIR}/

RUN composer install --no-interaction --no-progress --optimize-autoloader

USER www-data
