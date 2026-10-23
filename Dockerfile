FROM alpine:3.24 AS build
RUN apk add --no-cache build-base clang curl curl-dev linux-headers ncurses-dev openssl-dev zlib-dev
ENV CC=clang CXX=clang++
# Alpine's GCC 15.2 crashes compiling rTorrent's command_system.cc.
WORKDIR /build
RUN curl -fL -o libtorrent.tar.gz https://github.com/rakshasa/rtorrent/releases/download/v0.16.26/libtorrent-0.16.26.tar.gz \
    && curl -fL -o rtorrent.tar.gz https://github.com/rakshasa/rtorrent/releases/download/v0.16.26/rtorrent-0.16.26.tar.gz \
    && echo '19da1441ed628117025ff6a5d2035c5e6d81126fc9d442d8b10210df4246420c  libtorrent.tar.gz' | sha256sum -c - \
    && echo 'd10811b0678745e5c7b557c4394d54f7fd564d37cbdeb236d0e2f63a0f72918b  rtorrent.tar.gz' | sha256sum -c - \
    && tar -xzf libtorrent.tar.gz \
    && tar -xzf rtorrent.tar.gz \
    && cd libtorrent-0.16.26 \
    && ./configure \
    && make -j "$(nproc)" \
    && make install-strip \
    && cd ../rtorrent-0.16.26 \
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
