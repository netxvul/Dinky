#include <dlfcn.h>
#import "haptics.h"

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

// The open actuators, found on first use and again after one fails, as when a Magic Trackpad comes or goes.
static NSMutableArray *actuators;

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

static bool tapAll(int32_t actuation)
{
    bool any = false;
    for (id actuator in actuators) {
        if (actuate((__bridge CFTypeRef)actuator, actuation, 0, 1.0f, 2.0f) == kIOReturnSuccess) any = true;
    }
    return any;
}

bool dinky_trackpad_tap(int32_t actuation)
{
    if (!load()) return false;
    if (!actuators) openAll();
    if (tapAll(actuation)) return true;
    for (id actuator in actuators) closeActuator((__bridge CFTypeRef)actuator);
    openAll();
    return tapAll(actuation);
}
