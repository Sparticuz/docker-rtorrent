FROM alpine:3.24 AS build
RUN apk add --no-cache build-base clang curl curl-dev linux-headers ncurses-dev openssl-dev zlib-dev
ENV CC=clang CXX=clang++
# Alpine's GCC 15.2 crashes compiling rTorrent's command_system.cc.
WORKDIR /build
RUN curl -fL -o libtorrent.tar.gz https://github.com/rakshasa/rtorrent/releases/download/v0.16.25/libtorrent-0.16.25.tar.gz \
    && curl -fL -o rtorrent.tar.gz https://github.com/rakshasa/rtorrent/releases/download/v0.16.25/rtorrent-0.16.25.tar.gz \
    && echo '6266db1d5575d3b99846a4caad98e4c2a8aa6ad034d8b09e566d610123deb569  libtorrent.tar.gz' | sha256sum -c - \
    && echo 'd9c17e0fae59f0cb7533966f3ed778e9df701ad84d5dd50e9bae2aefe0f00a2a  rtorrent.tar.gz' | sha256sum -c - \
    && tar -xzf libtorrent.tar.gz \
    && tar -xzf rtorrent.tar.gz \
    && cd libtorrent-0.16.25 \
    && ./configure \
    && make -j "$(nproc)" \
    && make install-strip \
    && cd ../rtorrent-0.16.25 \
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
