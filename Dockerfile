FROM alpine:3.24 AS build
RUN apk add --no-cache build-base clang curl curl-dev linux-headers ncurses-dev openssl-dev zlib-dev
ENV CC=clang CXX=clang++
# Alpine's GCC 15.2 crashes compiling rTorrent's command_system.cc.
WORKDIR /build
RUN curl -fL -o libtorrent.tar.gz https://github.com/rakshasa/rtorrent/releases/download/v0.16.28/libtorrent-0.16.28.tar.gz \
    && curl -fL -o rtorrent.tar.gz https://github.com/rakshasa/rtorrent/releases/download/v0.16.28/rtorrent-0.16.28.tar.gz \
    && echo '569650d86cf757bd921f72c105f289128f7d918c19c2aaae5a350ffa74c4913e  libtorrent.tar.gz' | sha256sum -c - \
    && echo '5b668c625c45fb452018c27480e1a01ccbc33d850cb109209966651dabec207a  rtorrent.tar.gz' | sha256sum -c - \
    && tar -xzf libtorrent.tar.gz \
    && tar -xzf rtorrent.tar.gz \
    && cd libtorrent-0.16.28 \
    && ./configure \
    && make -j "$(nproc)" \
    && make install-strip \
    && cd ../rtorrent-0.16.28 \
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
