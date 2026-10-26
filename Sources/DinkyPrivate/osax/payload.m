// dinky's Dock payload: loaded into Dock.app, it runs from Dock's WindowServer connection, which has
// authority to move and transform windows belonging to other applications. A small unix-socket daemon
// takes dinky's commands. Modelled on yabai's src/osax/payload.m (MIT, © 2019 Åsmund Vikane); trimmed to
// the window-move and transform operations dinky's glides need, plus batched variants, and ordering windows above.
#include <Cocoa/Cocoa.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>
#include "common.h"

extern int SLSMainConnectionID(void);
extern CGError SLSGetWindowBounds(int cid, uint32_t wid, CGRect *frame);
extern CGError SLSGetWindowTransform(int cid, uint32_t wid, CGAffineTransform *t);
extern CGError SLSSetWindowTransform(int cid, uint32_t wid, CGAffineTransform t);
extern OSStatus SLSMoveWindowWithGroup(int cid, uint32_t wid, CGPoint *point);
extern CGError SLSReassociateWindowsSpacesByGeometry(int cid, CFArrayRef window_list);
extern CGError SLSOrderWindow(int cid, uint32_t wid, int mode, uint32_t relative_to);

// SLSOrderWindow's modes, as CGSWindowOrderingMode: above (or, relative to no window, above all of its level).
#define DINKY_SA_ORDER_ABOVE 1

static int daemon_sockfd;
static pthread_t daemon_thread;

#define unpack(t, v) t v; memcpy(&v, message, sizeof(v)); message += sizeof(v)

static void do_window_move(char *message)
{
    unpack(uint32_t, wid);
    unpack(int32_t, x);
    unpack(int32_t, y);
    if (!wid) return;

    CGPoint point = CGPointMake(x, y);
    SLSMoveWindowWithGroup(SLSMainConnectionID(), wid, &point);
    NSArray *list = @[ @(wid) ];
    SLSReassociateWindowsSpacesByGeometry(SLSMainConnectionID(), (__bridge CFArrayRef) list);
}

// Places the window's top-left at screen (x, y): the window-server transform maps content to the screen,
// and its translation component is the negated on-screen origin (so the resting transform is -realOrigin).
static void set_transform(uint32_t wid, float x, float y)
{
    CGAffineTransform t = CGAffineTransformMakeTranslation(-x, -y);
    SLSSetWindowTransform(SLSMainConnectionID(), wid, t);
}

static void reset_transform(uint32_t wid)
{
    CGRect frame = {};
    SLSGetWindowBounds(SLSMainConnectionID(), wid, &frame);
    SLSSetWindowTransform(SLSMainConnectionID(), wid, CGAffineTransformMakeTranslation(-frame.origin.x, -frame.origin.y));
}

static void do_window_transform(char *message)
{
    unpack(uint32_t, wid);
    unpack(float, x);
    unpack(float, y);
    if (wid) set_transform(wid, x, y);
}

static void do_transform_batch(char *message)
{
    unpack(int32_t, count);
    for (int i = 0; i < count; ++i) {
        unpack(uint32_t, wid);
        unpack(float, x);
        unpack(float, y);
        if (wid) set_transform(wid, x, y);
    }
}

static void do_transform_reset(char *message)
{
    unpack(uint32_t, wid);
    if (wid) reset_transform(wid);
}

static void do_reset_batch(char *message)
{
    unpack(int32_t, count);
    for (int i = 0; i < count; ++i) {
        unpack(uint32_t, wid);
        if (wid) reset_transform(wid);
    }
}

// Moves each window's real position, all in one message. Not reassociated with the Spaces by its new place, as the
// window move is: these are a strip's windows, staying on their Space wherever the strip parks them.
static void do_move_batch(char *message)
{
    unpack(int32_t, count);
    int cid = SLSMainConnectionID();
    for (int i = 0; i < count; ++i) {
        unpack(uint32_t, wid);
        unpack(float, x);
        unpack(float, y);
        if (!wid) continue;
        CGPoint point = CGPointMake(x, y);
        SLSMoveWindowWithGroup(cid, wid, &point);
    }
}

// Orders each window in front of every other of its level, the last frontmost: from Dock's connection, which may order
// any app's window, also above the active app's, without activating its own app or changing any key window.
static void do_order_batch(char *message)
{
    unpack(int32_t, count);
    int cid = SLSMainConnectionID();
    for (int i = 0; i < count; ++i) {
        unpack(uint32_t, wid);
        if (wid) SLSOrderWindow(cid, wid, DINKY_SA_ORDER_ABOVE, 0);
    }
}

static void do_handshake(int sockfd)
{
    uint32_t attrib = DINKY_SA_ATTRIB_ALL;
    char bytes[BUFSIZ] = {};
    int version_length = strlen(DINKY_SA_VERSION);
    memcpy(bytes, DINKY_SA_VERSION, version_length);
    bytes[version_length] = '\0';
    memcpy(bytes + version_length + 1, &attrib, sizeof(uint32_t));
    int total = version_length + 1 + sizeof(uint32_t);
    bytes[total] = '\n';
    send(sockfd, bytes, total + 1, MSG_NOSIGNAL);
}

static void handle_message(int sockfd, char *message)
{
    enum dinky_sa_opcode op = *message++;
    switch (op) {
    case DINKY_SA_OP_HANDSHAKE:        do_handshake(sockfd);        break;
    case DINKY_SA_OP_WINDOW_MOVE:      do_window_move(message);     break;
    case DINKY_SA_OP_WINDOW_TRANSFORM: do_window_transform(message);break;
    case DINKY_SA_OP_TRANSFORM_BATCH:  do_transform_batch(message); break;
    case DINKY_SA_OP_TRANSFORM_RESET:  do_transform_reset(message); break;
    case DINKY_SA_OP_RESET_BATCH:      do_reset_batch(message);     break;
    case DINKY_SA_OP_MOVE_BATCH:       do_move_batch(message);      break;
    case DINKY_SA_OP_ORDER_BATCH:      do_order_batch(message);     break;
    }
}

static bool read_message(int sockfd, char *message)
{
    int16_t to_read = 0;
    if (read(sockfd, &to_read, sizeof(int16_t)) != sizeof(int16_t)) return false;
    if (to_read <= 0 || to_read >= DINKY_SA_SOCKET_BUFF_LEN) return false;

    int got = 0;
    do {
        int n = read(sockfd, message + got, to_read - got);
        if (n <= 0) break;
        got += n;
    } while (got < to_read);
    return got == to_read;
}

static void *handle_connection(void *unused)
{
    (void) unused;
    for (;;) {
        int sockfd = accept(daemon_sockfd, NULL, 0);
        if (sockfd == -1) continue;
        // Critical: a send() to a client that already closed raises SIGPIPE, whose default action terminates the
        // process — and this process is Dock. The accepted socket inherits SO_NOSIGPIPE from the listening one (set
        // here too it fails with EINVAL once the client has closed, as dinky's probe does at once), and every send
        // passes MSG_NOSIGNAL as well, so such a send returns EPIPE instead. Nothing read, nothing answered.
        char message[DINKY_SA_SOCKET_BUFF_LEN];
        if (read_message(sockfd, message)) {
            handle_message(sockfd, message);
            char ack = 1;
            send(sockfd, &ack, 1, MSG_NOSIGNAL);
        }
        shutdown(sockfd, SHUT_RDWR);
        close(sockfd);
    }
    return NULL;
}

static bool start_daemon(const char *socket_path)
{
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", socket_path);
    unlink(socket_path);

    if ((daemon_sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) return false;
    // Inherited by every accepted socket, even one whose client closed before it was accepted (see handle_connection).
    int one = 1;
    setsockopt(daemon_sockfd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    if (bind(daemon_sockfd, (struct sockaddr *) &addr, sizeof(addr)) == -1) return false;
    if (chmod(socket_path, 0600) != 0) return false;
    if (listen(daemon_sockfd, SOMAXCONN) == -1) return false;
    pthread_create(&daemon_thread, NULL, &handle_connection, NULL);
    return true;
}

__attribute__((constructor))
void dinky_sa_load(void)
{
    NSLog(@"[dinky-sa] payload %s loaded", DINKY_SA_VERSION);
    // From the uid, not $USER: Dock's environment may not carry USER, but the socket name must match the client's.
    struct passwd *pw = getpwuid(getuid());
    const char *user = pw ? pw->pw_name : NULL;
    if (!user) { NSLog(@"[dinky-sa] no user for uid, abort"); return; }
    char socket_file[255];
    snprintf(socket_file, sizeof(socket_file), DINKY_SA_SOCKET_PATH_FMT, user);
    if (start_daemon(socket_file)) NSLog(@"[dinky-sa] listening on %s", socket_file);
    else NSLog(@"[dinky-sa] failed to start daemon");
}
