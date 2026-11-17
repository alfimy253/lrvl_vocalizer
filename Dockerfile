# Vocalizer publishes Linux x86-64 binaries only; build for linux/amd64.
FROM php:8.4-apache-bookworm

ARG VOCALIZER_COMMIT=002d86b709d29cd56e8f317fd3ee69c8b3895231
ARG VOCALIZER_SHA256=25c2851ef4d62fb96ef0e7e6aa1486c5888affa310228259e263f9017e44ba62
ARG MODEL=vits-piper-en_US-amy-low
# Observed SHA-256 of the upstream archive; changes require review.
ARG MODEL_SHA256=c70f5284a09a7fd4ed203b39b2ff51cac1432b422b852eb647b481dade3cf639
ARG MALE_MODEL=vits-piper-en_US-john-medium
ARG MALE_MODEL_SHA256=d90362cfa48e429d3096f644785184446145b6e38216f2eaf4c0601b8aad5a36

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl bzip2 libgomp1 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://raw.githubusercontent.com/AkramZerarka/vocalizer/${VOCALIZER_COMMIT}/bin/vocalizer-php8.4-nts-linux-x86_64.so" -o /tmp/vocalizer.so \
    && echo "${VOCALIZER_SHA256}  /tmp/vocalizer.so" | sha256sum -c - \
    && mv /tmp/vocalizer.so "$(php-config --extension-dir)/vocalizer.so" \
    && docker-php-ext-enable vocalizer \
    && php -r 'exit(extension_loaded("vocalizer") ? 0 : 1);' \
    && mkdir -p /opt/voices \
    && curl -fL --retry 3 "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${MODEL}.tar.bz2" -o /tmp/model.tar.bz2 \
    && echo "${MODEL_SHA256}  /tmp/model.tar.bz2" | sha256sum -c - \
    && tar -xjf /tmp/model.tar.bz2 -C /opt/voices \
    && test -d "/opt/voices/${MODEL}" \
    && rm /tmp/model.tar.bz2 \
    && curl -fL --retry 3 "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${MALE_MODEL}.tar.bz2" -o /tmp/male-model.tar.bz2 \
    && echo "${MALE_MODEL_SHA256}  /tmp/male-model.tar.bz2" | sha256sum -c - \
    && tar -xjf /tmp/male-model.tar.bz2 -C /opt/voices \
    && test -d "/opt/voices/${MALE_MODEL}" \
    && rm /tmp/male-model.tar.bz2 \
    && a2enmod rewrite \
    && printf 'ServerName localhost\n' > /etc/apache2/conf-available/server-name.conf \
    && a2enconf server-name

ENV TTS_MODEL_DIR=/opt/voices/${MODEL} \
    TTS_MALE_MODEL_DIR=/opt/voices/${MALE_MODEL} \
    PORT=10000
COPY public/ /var/www/html/
COPY apache-tts.conf /etc/apache2/conf-available/tts.conf
COPY start.sh /usr/local/bin/start-tts
RUN a2enconf tts && chmod +x /usr/local/bin/start-tts
EXPOSE 10000
CMD ["/usr/local/bin/start-tts"]
