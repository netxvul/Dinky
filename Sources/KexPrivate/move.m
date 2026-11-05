#import "move.h"
#import "skylight.h"
#import <objc/runtime.h>

// The asynchronous bridged dispatcher; its argument is the operation object.
typedef int64_t (*SLSPerformAsynchronousBridgedWindowManagementOperationFn)(void *operation);

static SLSPerformAsynchronousBridgedWindowManagementOperationFn kex_dispatcher(void)
{
    static SLSPerformAsynchronousBridgedWindowManagementOperationFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (SLSPerformAsynchronousBridgedWindowManagementOperationFn)kex_skylight_symbol(
            "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation");
    });
    return fn;
}

// Declared so ARC knows init returns +1.
@protocol KexBridgedMoveOperation <NSObject>
- (instancetype)initWithWindows:(id)windows spaceID:(uint64_t)spaceID;
@end

bool kex_move_windows_to_space(const uint32_t *windowIDs, int count, uint64_t spaceID)
{
    SLSPerformAsynchronousBridgedWindowManagementOperationFn perform = kex_dispatcher();
    if (!perform) {
        fputs("move: SLSPerformAsynchronousBridgedWindowManagementOperation not found in SkyLight symtab\n", stderr);
        return false;
    }

    Class cls = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation");
    if (!cls) {
        fputs("move: class SLSBridgedMoveWindowsToManagedSpaceOperation not found\n", stderr);
        return false;
    }

    NSMutableArray *windows = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; ++i) {
        int32_t wid = (int32_t)windowIDs[i];
        [windows addObject:CFBridgingRelease(CFNumberCreate(NULL, kCFNumberSInt32Type, &wid))];
    }

    id<KexBridgedMoveOperation> operation = [(id<KexBridgedMoveOperation>)[cls alloc] initWithWindows:windows spaceID:spaceID];
    if (!operation) {
        fputs("move: initWithWindows:spaceID: returned nil\n", stderr);
        return false;
    }

    perform((__bridge void *)operation);
    return true;
}
