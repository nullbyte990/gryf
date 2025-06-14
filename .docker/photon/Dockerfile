FROM eclipse-temurin:21-jre-alpine

ARG PHOTON_VERSION=1.2.0

RUN apk add --no-cache bzip2 curl su-exec tar zstd \
    && addgroup -S photon \
    && adduser -S -G photon photon \
    && mkdir -p /opt/photon /photon \
    && curl -fsSL \
        "https://github.com/komoot/photon/releases/download/${PHOTON_VERSION}/photon-${PHOTON_VERSION}.jar" \
        -o /opt/photon/photon.jar \
    && chown -R photon:photon /opt/photon /photon

COPY .docker/photon/entrypoint.sh /usr/local/bin/photon-entrypoint

RUN chmod +x /usr/local/bin/photon-entrypoint

WORKDIR /photon

EXPOSE 2322

ENTRYPOINT ["photon-entrypoint"]
CMD ["java", "-Xmx2G", "-jar", "/opt/photon/photon.jar", "serve", "-listen-ip", "0.0.0.0", "-listen-port", "2322", "-data-dir", "/photon", "-default-language", "pl"]
