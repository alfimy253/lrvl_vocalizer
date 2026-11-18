# Vocalizer publishes Linux x86-64 binaries only; build for linux/amd64.
FROM php:8.4-apache-bookworm

ARG VOCALIZER_COMMIT=002d86b709d29cd56e8f317fd3ee69c8b3895231
ARG VOCALIZER_SHA256=25c2851ef4d62fb96ef0e7e6aa1486c5888affa310228259e263f9017e44ba62

# Voice models: 2 female (Amy, LJSpeech) + 2 male (Ryan, Joe)
ARG AMY_MODEL=vits-piper-en_US-amy-low
ARG AMY_SHA256=c70f5284a09a7fd4ed203b39b2ff51cac1432b422b852eb647b481dade3cf639
ARG LJSPEECH_MODEL=vits-piper-en_US-ljspeech-medium
ARG RYAN_MODEL=vits-piper-en_US-ryan-high
ARG JOE_MODEL=vits-piper-en_US-joe-medium

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl bzip2 libgomp1 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://raw.githubusercontent.com/AkramZerarka/vocalizer/${VOCALIZER_COMMIT}/bin/vocalizer-php8.4-nts-linux-x86_64.so" -o /tmp/vocalizer.so \
    && echo "${VOCALIZER_SHA256}  /tmp/vocalizer.so" | sha256sum -c - \
    && mv /tmp/vocalizer.so "$(php-config --extension-dir)/vocalizer.so" \
    && docker-php-ext-enable vocalizer \
    && php -r 'exit(extension_loaded("vocalizer") ? 0 : 1);' \
    && mkdir -p /opt/voices \
    # --- Amy (female, low quality, ~25 MB) --- \
    && curl -fL --retry 3 "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${AMY_MODEL}.tar.bz2" -o /tmp/amy.tar.bz2 \
    && echo "${AMY_SHA256}  /tmp/amy.tar.bz2" | sha256sum -c - \
    && tar -xjf /tmp/amy.tar.bz2 -C /opt/voices \
    && test -d "/opt/voices/${AMY_MODEL}" \
    && rm /tmp/amy.tar.bz2 \
    # --- LJSpeech (female, medium quality, ~64 MB) --- \
    && curl -fL --retry 3 "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${LJSPEECH_MODEL}.tar.bz2" -o /tmp/ljspeech.tar.bz2 \
    && tar -xjf /tmp/ljspeech.tar.bz2 -C /opt/voices \
    && test -d "/opt/voices/${LJSPEECH_MODEL}" \
    && rm /tmp/ljspeech.tar.bz2 \
    # --- Ryan (male, high quality, ~110 MB) --- \
    && curl -fL --retry 3 "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${RYAN_MODEL}.tar.bz2" -o /tmp/ryan.tar.bz2 \
    && tar -xjf /tmp/ryan.tar.bz2 -C /opt/voices \
    && test -d "/opt/voices/${RYAN_MODEL}" \
    && rm /tmp/ryan.tar.bz2 \
    # --- Joe (male, medium quality, ~64 MB) --- \
    && curl -fL --retry 3 "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${JOE_MODEL}.tar.bz2" -o /tmp/joe.tar.bz2 \
    && tar -xjf /tmp/joe.tar.bz2 -C /opt/voices \
    && test -d "/opt/voices/${JOE_MODEL}" \
    && rm /tmp/joe.tar.bz2 \
    && a2enmod rewrite \
    && printf 'ServerName localhost\n' > /etc/apache2/conf-available/server-name.conf \
    && a2enconf server-name

ENV TTS_AMY_MODEL_DIR=/opt/voices/${AMY_MODEL} \
    TTS_LJSPEECH_MODEL_DIR=/opt/voices/${LJSPEECH_MODEL} \
    TTS_RYAN_MODEL_DIR=/opt/voices/${RYAN_MODEL} \
    TTS_JOE_MODEL_DIR=/opt/voices/${JOE_MODEL} \
    PORT=10000
COPY public/ /var/www/html/
COPY apache-tts.conf /etc/apache2/conf-available/tts.conf
COPY start.sh /usr/local/bin/start-tts
RUN a2enconf tts && chmod +x /usr/local/bin/start-tts
EXPOSE 10000
CMD ["/usr/local/bin/start-tts"]
