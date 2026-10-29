FROM alpine:3.24 AS build
RUN apk add --no-cache build-base clang curl curl-dev linux-headers ncurses-dev openssl-dev zlib-dev
ENV CC=clang CXX=clang++
# Alpine's GCC 15.2 crashes compiling rTorrent's command_system.cc.
WORKDIR /build
RUN curl -fL -o libtorrent.tar.gz https://github.com/rakshasa/rtorrent/releases/download/v0.16.27/libtorrent-0.16.27.tar.gz \
    && curl -fL -o rtorrent.tar.gz https://github.com/rakshasa/rtorrent/releases/download/v0.16.27/rtorrent-0.16.27.tar.gz \
    && echo 'b7ee3f637da6d136fb70a4566fbea8e444f7a2e259596e8612adeb0c7c520fd1  libtorrent.tar.gz' | sha256sum -c - \
    && echo '645e5ea863fee2c3a0f745be6235a37e80cf7db6a07bc82ca31d49bf65f2a52a  rtorrent.tar.gz' | sha256sum -c - \
    && tar -xzf libtorrent.tar.gz \
    && tar -xzf rtorrent.tar.gz \
    && cd libtorrent-0.16.27 \
    && ./configure \
    && make -j "$(nproc)" \
    && make install-strip \
    && cd ../rtorrent-0.16.27 \
    && ./configure --with-xmlrpc-tinyxml2 \
    && make -j "$(nproc)" \
    && make install-strip

FROM alpine:3.24
COPY --from=build /usr/local/bin/rtorrent /usr/local/bin/rtorrent
COPY --from=build /usr/local/lib/libtorrent.so* /usr/local/lib/

# Install rtorrent and su-exec
# Create necessary folders
# Forward Info & Error logs to std{out,err} (à la nginx)
RUN apk add --no-cache \
      ca-certificates libcurl libstdc++ ncurses-libs openssl zlib \
      su-exec && \
    mkdir -p \
      /dist \
      /config \
      /session \
      /socket \
      /watch/load \
      /watch/start \
      /downloads && \
    ln -sf /dev/stdout /var/log/rtorrent-info.log && \
    ln -sf /dev/stderr /var/log/rtorrent-error.log

VOLUME ["/config", "/session", "/socket", "/watch", "/downloads"]

# Copy distribution rTorrent config for bootstrapping and entrypoint
COPY ./root /

ENTRYPOINT ["/entrypoint"]

CMD ["rtorrent", "-n", "-o", "import=/config/.rtorrent.rc"]
