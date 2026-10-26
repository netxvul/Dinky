#include <dlfcn.h>
#import "haptics.h"
#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#import "touches.h"

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

// One finger in a contact frame, as MultitouchSupport lays it out.
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTVector normalized;
    float size;
    int unknown1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int unknown2;
    int unknown3;
    float density;
} MTTouch;

// Touch states: a finger making contact and one resting on the surface; hovering and lifting ones are not down.
enum { MTStateMakeTouch = 3, MTStateTouching = 4 };

typedef CFTypeRef MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef device, MTTouch *touches, int count, double time, int frame);

typedef CFArrayRef (*DeviceCreateList)(void);
typedef void (*RegisterCallback)(MTDeviceRef device, MTContactCallback callback);
typedef void (*DeviceStart)(MTDeviceRef device, int mode);
typedef void (*DeviceStop)(MTDeviceRef device);
typedef int (*SurfaceDimensions)(MTDeviceRef device, int *width, int *height);

static DeviceCreateList createList;
static RegisterCallback registerCallback;
static RegisterCallback unregisterCallback;
static DeviceStart startDevice;
static DeviceStop stopDevice;
static SurfaceDimensions surfaceDimensions;

// Read on MultitouchSupport's thread while the main thread may replace it, so every handler is kept for good.
static DinkyTouchFrame handler;
static NSMutableArray *handlers;
// The trackpads and mice started, retained.
static NSArray *devices;
static IONotificationPortRef port;
static id wakeObserver;
// A restart waiting for the trackpads to settle, so a burst of arrivals restarts once.
static bool restartPending;

static bool load(void)
{
    static bool loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
        if (!framework) return;
        createList = (DeviceCreateList)dlsym(framework, "MTDeviceCreateList");
        registerCallback = (RegisterCallback)dlsym(framework, "MTRegisterContactFrameCallback");
        unregisterCallback = (RegisterCallback)dlsym(framework, "MTUnregisterContactFrameCallback");
        startDevice = (DeviceStart)dlsym(framework, "MTDeviceStart");
        stopDevice = (DeviceStop)dlsym(framework, "MTDeviceStop");
        surfaceDimensions = (SurfaceDimensions)dlsym(framework, "MTDeviceGetSensorSurfaceDimensions");
        loaded = createList && registerCallback && unregisterCallback && startDevice && stopDevice;
    });
    return loaded;
}

static int contactFrame(MTDeviceRef device, MTTouch *touches, int count, double time, int frame)
{
    DinkyTouchFrame frameHandler = handler;
    if (!frameHandler) return 0;
    // Hundredths of a millimetre; a 16:10 trackpad about 130 mm wide where the call is missing.
    int width = 0, height = 0;
    if (!surfaceDimensions || surfaceDimensions(device, &width, &height) != 0 || width <= 0 || height <= 0) {
        width = 13000;
        height = 8100;
    }
    // A Magic Mouse's surface is about 52 mm across, the narrowest trackpad's over 100.
    bool mouse = width < 7000;
    int down = 0;
    double x = 0, y = 0;
    for (int i = 0; i < count; i++) {
        if (touches[i].state != MTStateMakeTouch && touches[i].state != MTStateTouching) continue;
        down++;
        x += touches[i].normalized.position.x;
        y += touches[i].normalized.position.y;
    }
    if (down > 0) {
        x = x / down * width / 100.0;
        y = y / down * height / 100.0;
    }
    frameHandler(down, x, y, time, (uintptr_t)device, mouse, width / 100.0);
    return 0;
}

static void startAll(void)
{
    devices = CFBridgingRelease(createList());
    for (id device in devices) {
        registerCallback((__bridge MTDeviceRef)device, contactFrame);
        startDevice((__bridge MTDeviceRef)device, 0);
    }
}

static void stopAll(void)
{
    for (id device in devices) {
        unregisterCallback((__bridge MTDeviceRef)device, contactFrame);
        stopDevice((__bridge MTDeviceRef)device);
    }
    devices = nil;
}

static void restartSoon(void)
{
    if (restartPending) return;
    restartPending = true;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        restartPending = false;
        // The taps' actuators too: a Magic Trackpad come or reconnected after sleep is one to tap.
        dinky_trackpad_actuators_reset();
        if (!handler) return;
        stopAll();
        startAll();
    });
}

static void devicesChanged(void *refcon, io_iterator_t iterator)
{
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) IOObjectRelease(service);
    restartSoon();
}

static void watchDevices(void)
{
    port = IONotificationPortCreate(kIOMainPortDefault);
    IONotificationPortSetDispatchQueue(port, dispatch_get_main_queue());
    const char *types[] = { kIOFirstMatchNotification, kIOTerminatedNotification };
    for (int i = 0; i < 2; i++) {
        io_iterator_t iterator = 0;
        if (IOServiceAddMatchingNotification(port, types[i], IOServiceMatching("AppleMultitouchDevice"),
                                             devicesChanged, NULL, &iterator) == KERN_SUCCESS) {
            // Draining arms the notification; the trackpads there now are started already.
            io_object_t service;
            while ((service = IOIteratorNext(iterator))) IOObjectRelease(service);
        }
    }
    wakeObserver = [NSWorkspace.sharedWorkspace.notificationCenter
        addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) { restartSoon(); }];
}

bool dinky_touches_start(DinkyTouchFrame frame)
{
    if (!load()) return false;
    if (handler) stopAll();
    if (!handlers) handlers = [NSMutableArray array];
    DinkyTouchFrame copied = [frame copy];
    [handlers addObject:copied];
    handler = copied;
    startAll();
    dinky_devices_watch();
    return true;
}

void dinky_devices_watch(void)
{
    if (port) return;
    watchDevices();
}

void dinky_touches_stop(void)
{
    if (!handler) return;
    stopAll();
    handler = nil;
}
