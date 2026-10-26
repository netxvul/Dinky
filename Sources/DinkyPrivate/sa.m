#import "sa.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/time.h>
#import <unistd.h>
#import <pwd.h>
#import "osax/common.h"

// A fresh connection per message, as yabai's scripting-addition client does; at 60-120 a second over a local unix
// socket this is cheap, and it keeps the payload's accept-one-message loop simple. A short timeout bounds the worst
// case so a wedged Dock cannot stall the main thread.

static int sa_connect(void)
{
    // From the uid, not $USER, so the client and the Dock payload agree on the socket name regardless of environment.
    struct passwd *pw = getpwuid(getuid());
    const char *user = pw ? pw->pw_name : NULL;
    if (!user) return -1;

    char path[255];
    snprintf(path, sizeof(path), DINKY_SA_SOCKET_PATH_FMT, user);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    // So a send() after the payload closes returns EPIPE here instead of raising SIGPIPE and killing dinky.
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    struct timeval tv = { .tv_sec = 0, .tv_usec = 100000 };
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);
    if (connect(fd, (struct sockaddr *) &addr, sizeof(addr)) != 0) { close(fd); return -1; }
    return fd;
}

static void sa_finish(int fd, char *bytes, int total)
{
    // bytes starts with a 2-byte length (the count of the bytes that follow it).
    int16_t body = (int16_t)(total - (int)sizeof(int16_t));
    memcpy(bytes, &body, sizeof(int16_t));
    if (send(fd, bytes, total, 0) == total) { char ack; recv(fd, &ack, 1, 0); }
    close(fd);
}

bool dinky_sa_available(void)
{
    int fd = sa_connect();
    if (fd < 0) return false;
    close(fd);
    return true;
}

// The payload's capabilities from its handshake, nothing when it does not answer.
static uint32_t sa_attributes(void)
{
    int fd = sa_connect();
    if (fd < 0) return false;

    char bytes[sizeof(int16_t) + 1];
    int16_t body = 1;
    memcpy(bytes, &body, sizeof(body));
    bytes[sizeof(int16_t)] = DINKY_SA_OP_HANDSHAKE;
    uint32_t attrib = 0;
    if (send(fd, bytes, sizeof(bytes), 0) == (ssize_t) sizeof(bytes)) {
        // The payload's version, a zero, its attributes and a newline, then the ack.
        char reply[64];
        int got = 0;
        while (got < (int) sizeof(reply)) {
            ssize_t n = recv(fd, reply + got, sizeof(reply) - got, 0);
            if (n <= 0) break;
            got += (int) n;
            char *zero = memchr(reply, '\0', got);
            if (zero && reply + got >= zero + 1 + sizeof(uint32_t)) {
                memcpy(&attrib, zero + 1, sizeof(uint32_t));
                break;
            }
        }
    }
    close(fd);
    return attrib;
}

bool dinky_sa_moves_windows(void)
{
    return (sa_attributes() & DINKY_SA_ATTRIB_MOVE_BATCH) != 0;
}

bool dinky_sa_orders_windows(void)
{
    return (sa_attributes() & DINKY_SA_ATTRIB_ORDER) != 0;
}

void dinky_sa_order_batch(const uint32_t *wids, int count)
{
    if (count <= 0) return;
    int fd = sa_connect();
    if (fd < 0) return;

    char bytes[DINKY_SA_SOCKET_BUFF_LEN];
    int pos = sizeof(int16_t);
    bytes[pos++] = DINKY_SA_OP_ORDER_BATCH;
    int count_at = pos; pos += sizeof(int32_t);
    int32_t n = 0;
    for (int i = 0; i < count; ++i) {
        if (pos + (int)sizeof(uint32_t) > DINKY_SA_SOCKET_BUFF_LEN) break;
        uint32_t wid = wids[i];
        memcpy(bytes + pos, &wid, sizeof(wid)); pos += sizeof(wid);
        ++n;
    }
    memcpy(bytes + count_at, &n, sizeof(n));
    sa_finish(fd, bytes, pos);
}

void dinky_sa_transform_batch(const uint32_t *wids, const CGPoint *points, int count)
{
    if (count <= 0) return;
    int fd = sa_connect();
    if (fd < 0) return;

    char bytes[DINKY_SA_SOCKET_BUFF_LEN];
    int pos = sizeof(int16_t);
    bytes[pos++] = DINKY_SA_OP_TRANSFORM_BATCH;
    int count_at = pos; pos += sizeof(int32_t);
    int32_t n = 0;
    for (int i = 0; i < count; ++i) {
        if (pos + (int)(sizeof(uint32_t) + 2 * sizeof(float)) > DINKY_SA_SOCKET_BUFF_LEN) break;
        uint32_t wid = wids[i];
        float x = (float) points[i].x, y = (float) points[i].y;
        memcpy(bytes + pos, &wid, sizeof(wid)); pos += sizeof(wid);
        memcpy(bytes + pos, &x, sizeof(x)); pos += sizeof(x);
        memcpy(bytes + pos, &y, sizeof(y)); pos += sizeof(y);
        ++n;
    }
    memcpy(bytes + count_at, &n, sizeof(n));
    sa_finish(fd, bytes, pos);
}

void dinky_sa_move_batch(const uint32_t *wids, const CGPoint *points, int count)
{
    if (count <= 0) return;
    int fd = sa_connect();
    if (fd < 0) return;

    char bytes[DINKY_SA_SOCKET_BUFF_LEN];
    int pos = sizeof(int16_t);
    bytes[pos++] = DINKY_SA_OP_MOVE_BATCH;
    int count_at = pos; pos += sizeof(int32_t);
    int32_t n = 0;
    for (int i = 0; i < count; ++i) {
        if (pos + (int)(sizeof(uint32_t) + 2 * sizeof(float)) > DINKY_SA_SOCKET_BUFF_LEN) break;
        uint32_t wid = wids[i];
        float x = (float) points[i].x, y = (float) points[i].y;
        memcpy(bytes + pos, &wid, sizeof(wid)); pos += sizeof(wid);
        memcpy(bytes + pos, &x, sizeof(x)); pos += sizeof(x);
        memcpy(bytes + pos, &y, sizeof(y)); pos += sizeof(y);
        ++n;
    }
    memcpy(bytes + count_at, &n, sizeof(n));
    sa_finish(fd, bytes, pos);
}

void dinky_sa_reset_batch(const uint32_t *wids, int count)
{
    if (count <= 0) return;
    int fd = sa_connect();
    if (fd < 0) return;

    char bytes[DINKY_SA_SOCKET_BUFF_LEN];
    int pos = sizeof(int16_t);
    bytes[pos++] = DINKY_SA_OP_RESET_BATCH;
    int count_at = pos; pos += sizeof(int32_t);
    int32_t n = 0;
    for (int i = 0; i < count; ++i) {
        if (pos + (int)sizeof(uint32_t) > DINKY_SA_SOCKET_BUFF_LEN) break;
        uint32_t wid = wids[i];
        memcpy(bytes + pos, &wid, sizeof(wid)); pos += sizeof(wid);
        ++n;
    }
    memcpy(bytes + count_at, &n, sizeof(n));
    sa_finish(fd, bytes, pos);
}
