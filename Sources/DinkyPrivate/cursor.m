#include <dlfcn.h>
#import "cursor.h"
#import "query.h"

typedef CGError (*SetConnectionProperty)(int cid, int target, CFStringRef key, CFTypeRef value);
typedef int32_t (*CurrentCursorSeed)(void);
typedef CGError (*SetWindowTags)(int cid, uint32_t wid, uint64_t *tags, int size);
typedef CGError (*OrderWindow)(int cid, uint32_t wid, int mode, uint32_t relativeTo);

static SetConnectionProperty setConnectionProperty;
static CurrentCursorSeed currentCursorSeed;
static SetWindowTags setWindowTags;
static OrderWindow orderWindow;

// The SLS name, else the CGS one.
static void *lookUp(void *framework, const char *sls, const char *cgs)
{
    void *symbol = framework ? dlsym(framework, sls) : NULL;
    return symbol ? symbol : dlsym(RTLD_DEFAULT, cgs);
}

static void load(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        setConnectionProperty = (SetConnectionProperty)lookUp(framework, "SLSSetConnectionProperty", "CGSSetConnectionProperty");
        currentCursorSeed = (CurrentCursorSeed)lookUp(framework, "SLSCurrentCursorSeed", "CGSCurrentCursorSeed");
        setWindowTags = (SetWindowTags)lookUp(framework, "SLSSetWindowTags", "CGSSetWindowTags");
        orderWindow = (OrderWindow)lookUp(framework, "SLSOrderWindow", "CGSOrderWindow");
    });
}

bool dinky_cursor_in_background(bool on)
{
    load();
    if (!setConnectionProperty) return false;
    int cid = dinky_connection();
    return setConnectionProperty(cid, cid, CFSTR("SetsCursorInBackground"), on ? kCFBooleanTrue : kCFBooleanFalse) == kCGErrorSuccess;
}

int32_t dinky_cursor_seed(void)
{
    load();
    return currentCursorSeed ? currentCursorSeed() : -1;
}

bool dinky_window_cursor_tag(uint32_t wid)
{
    load();
    if (!setWindowTags) return false;
    uint64_t tags[2] = {1ULL << 5, 0};
    return setWindowTags(dinky_connection(), wid, tags, 64) == kCGErrorSuccess;
}

bool dinky_cursor_available(void)
{
    load();
    return setConnectionProperty && orderWindow;
}

bool dinky_window_order_out(uint32_t wid)
{
    load();
    // Mode 0 is out.
    return orderWindow && orderWindow(dinky_connection(), wid, 0, 0) == kCGErrorSuccess;
}
