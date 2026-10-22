#!/bin/sh
# Run in a disposable container as root; never against production volumes.
set -eu

/entrypoint bootstrap
cp /config/.rtorrent.rc /tmp/original.rc
printf 'keep this session lock\n' > /session/rtorrent.lock
cp /session/rtorrent.lock /tmp/original.lock
/entrypoint bootstrap
cmp /tmp/original.rc /config/.rtorrent.rc
cmp /tmp/original.lock /session/rtorrent.lock

# Bootstrap must preserve a user-supplied config, including when read-only.
printf '# custom configuration\n' > /config/.rtorrent.rc
chmod 444 /config/.rtorrent.rc
su-exec 1000:1000 /entrypoint bootstrap
test "$(cat /config/.rtorrent.rc)" = '# custom configuration'
cmp /tmp/original.lock /session/rtorrent.lock

# A failed copy must not look like successful initialization.
rm /config/.rtorrent.rc
if su-exec 1000:1000 /entrypoint bootstrap; then
    echo 'Bootstrap unexpectedly succeeded in an unwritable config directory' >&2
    exit 1
fi
test ! -e /config/.rtorrent.rc
cmp /tmp/original.lock /session/rtorrent.lock

# A missing source config must also fail before touching session state.
mv /dist/.rtorrent.rc.dist /tmp/default.rc
if /entrypoint bootstrap; then
    echo 'Bootstrap unexpectedly succeeded without a default config' >&2
    exit 1
fi
cmp /tmp/original.lock /session/rtorrent.lock
mv /tmp/default.rc /dist/.rtorrent.rc.dist

if PUID=not-a-uid /entrypoint bootstrap; then
    echo 'Bootstrap accepted an invalid UID' >&2
    exit 1
fi
if PGID=not-a-gid /entrypoint bootstrap; then
    echo 'Bootstrap accepted an invalid GID' >&2
    exit 1
fi

# A fresh config must be readable by the requested runtime user.
PUID=1026 PGID=100 /entrypoint bootstrap
test "$(stat -c '%u:%g' /config/.rtorrent.rc)" = '1026:100'
su-exec 1026:100 test -r /config/.rtorrent.rc
cmp /tmp/original.lock /session/rtorrent.lock
printf 'Startup safety checks passed\n'

# A second startup must not remove the live instance's session lock.
cp /tmp/original.rc /config/.rtorrent.rc
rm /session/rtorrent.lock
/entrypoint rtorrent -n -o import=/config/.rtorrent.rc &
pid=$!
trap 'kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :' EXIT
attempt=0
until [ -S /socket/rtorrent.sock ] && [ -f /session/rtorrent.lock ]; do
    kill -0 "$pid"
    attempt=$((attempt + 1))
    test "$attempt" -lt 100
    sleep 0.1
done
cp /session/rtorrent.lock /tmp/live.lock
status=0
timeout 5 /entrypoint rtorrent -n \
    -o system.daemon.set=true \
    -o session.path.set=/session \
    -o network.scgi.open_local=/socket/second.sock || status=$?
test "$status" -ne 0
test "$status" -ne 124
cmp /tmp/live.lock /session/rtorrent.lock
kill -0 "$pid"
kill "$pid"
wait "$pid"
trap - EXIT
test ! -e /session/rtorrent.lock
printf 'Live session lock and graceful shutdown checks passed\n'
