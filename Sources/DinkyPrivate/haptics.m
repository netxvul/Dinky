#include <dlfcn.h>
#import "haptics.h"
#import "touches.h"
#include <time.h>

typedef CFArrayRef (*DeviceCreateList)(void);
typedef OSStatus (*DeviceGetDeviceID)(CFTypeRef device, uint64_t *deviceID);
typedef CFTypeRef (*ActuatorCreateFromDeviceID)(uint64_t deviceID);
typedef IOReturn (*ActuatorOpen)(CFTypeRef actuator);
typedef IOReturn (*ActuatorActuate)(CFTypeRef actuator, SInt32 actuationID, UInt32 unknown1, Float32 unknown2, Float32 unknown3);
typedef IOReturn (*ActuatorClose)(CFTypeRef actuator);

static DeviceCreateList createList;
static DeviceGetDeviceID getDeviceID;
static ActuatorCreateFromDeviceID createActuator;
static ActuatorOpen openActuator;
static ActuatorActuate actuate;
static ActuatorClose closeActuator;

// The open actuators: found on first use, and again once one fails or a trackpad comes, goes or the Mac wakes
// (`dinky_trackpad_actuators_reset`), so a Magic Trackpad that connects later gets the taps too. Main thread.
static NSMutableArray *actuators;
// When none was found, so a Mac without one is not searched on every tap: again only after a reset or a while.
static double noneFoundAt;

static bool load(void)
{
    static bool loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
        if (!framework) return;
        createList = (DeviceCreateList)dlsym(framework, "MTDeviceCreateList");
        getDeviceID = (DeviceGetDeviceID)dlsym(framework, "MTDeviceGetDeviceID");
        createActuator = (ActuatorCreateFromDeviceID)dlsym(framework, "MTActuatorCreateFromDeviceID");
        openActuator = (ActuatorOpen)dlsym(framework, "MTActuatorOpen");
        actuate = (ActuatorActuate)dlsym(framework, "MTActuatorActuate");
        closeActuator = (ActuatorClose)dlsym(framework, "MTActuatorClose");
        loaded = createList && getDeviceID && createActuator && openActuator && actuate && closeActuator;
    });
    return loaded;
}

static void openAll(void)
{
    actuators = [NSMutableArray array];
    NSArray *devices = CFBridgingRelease(createList());
    for (id device in devices) {
        uint64_t deviceID = 0;
        if (getDeviceID((__bridge CFTypeRef)device, &deviceID) != noErr || deviceID == 0) continue;
        CFTypeRef actuator = createActuator(deviceID);
        if (!actuator) continue;
        if (openActuator(actuator) == kIOReturnSuccess) {
            [actuators addObject:CFBridgingRelease(actuator)];
        } else {
            CFRelease(actuator);
        }
    }
}

// Now, on a clock that only goes forward, in seconds.
static double now(void)
{
    return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9;
}

// When the actuators were last found afresh because none took a tap.
static double lastRescanAt;

void dinky_trackpad_actuators_reset(void)
{
    for (id actuator in actuators) closeActuator((__bridge CFTypeRef)actuator);
    actuators = nil;
    noneFoundAt = 0;
}

// Finds the actuators; none found is remembered (`noneFoundAt`), the array left nil. True when there is one.
static bool find(void)
{
    openAll();
    if (actuators.count) return true;
    actuators = nil;
    noneFoundAt = now();
    return false;
}

// Taps every actuator; those that fail are closed and dropped. True when at least one took it.
static bool tapAll(int32_t actuation)
{
    bool any = false;
    NSMutableArray *failed = [NSMutableArray array];
    for (id actuator in actuators) {
        if (actuate((__bridge CFTypeRef)actuator, actuation, 0, 1.0f, 2.0f) == kIOReturnSuccess) any = true;
        else [failed addObject:actuator];
    }
    for (id actuator in failed) {
        closeActuator((__bridge CFTypeRef)actuator);
        [actuators removeObject:actuator];
    }
    return any;
}

bool dinky_trackpad_tap(int32_t actuation)
{
    if (!load()) return false;
    // So a trackpad coming or going, or a wake, finds them afresh, whether or not a gesture reads touches.
    dinky_devices_watch();
    if (!actuators) {
        if (noneFoundAt != 0 && now() - noneFoundAt < 5) return false;
        if (!find()) return false;
    }
    if (tapAll(actuation)) return true;
    // None took it, as after sleep: found afresh and tried once more, not more than every few seconds.
    if (now() - lastRescanAt < 3) return false;
    lastRescanAt = now();
    dinky_trackpad_actuators_reset();
    if (!find()) return false;
    return tapAll(actuation);
}
