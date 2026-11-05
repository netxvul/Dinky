#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// WindowServer notification types, the numbers SLSRegisterNotifyProc takes.
// From JankyBorders src/events.h; SpaceCreated/Destroyed from yabai src/yabai.c.
typedef NS_ENUM(uint32_t, KexEventKind) {
    KexEventWindowUpdate = 723,
    KexEventWindowClose = 804,
    KexEventWindowMove = 806,
    KexEventWindowResize = 807,
    KexEventWindowReorder = 808,
    KexEventWindowLevel = 811,
    KexEventWindowUnhide = 815,
    KexEventWindowHide = 816,
    KexEventWindowTitle = 1322,
    KexEventWindowCreate = 1325,
    KexEventWindowDestroy = 1326,
    KexEventSpaceCreated = 1327,
    KexEventSpaceDestroyed = 1328,
    KexEventSpaceChange = 1401,
    KexEventFrontApp = 1508,
};

typedef struct {
    KexEventKind kind;
    uint32_t windowID;  // 0 for Space and front app events
    pid_t pid;          // window owner, or the front app for KexEventFrontApp; 0 if gone, and always 0 for
                        // KexEventWindowMove and KexEventWindowResize, whose owner is not looked up
    uint64_t spaceID;   // create/destroy and Space created/destroyed only, else 0
} KexEvent;

typedef void (*KexEventCallback)(KexEvent event, void *_Nullable context);

// Registers for every KexEventKind on the main connection. Callbacks run on the main
// thread, from inside the AppKit event loop: SkyLight dispatches notify procs while it
// drains the connection's event port, which [NSApp run] does. Without a running
// NSApplication nothing is delivered. Returns false if registration failed.
bool kex_events_start(KexEventCallback callback, void *_Nullable context);

// The per-window events (close, move, resize, reorder, level, hide, unhide) only arrive
// for windows named here. Each call replaces the previous list.
void kex_events_watch_windows(const uint32_t *windowIDs, int count);

typedef struct {
    bool exists;
    uint32_t windowID;
    pid_t pid;
    CGRect frame;          // global display coordinates, top-left origin
    int level;
    uint32_t parentID;
    uint64_t tags;
    uint64_t attributes;
    bool isOrderedIn;
    bool isDocument;       // JankyBorders window_suitable, kind only: a real document or modal window
    bool isVisible;        // the visible attribute or tag; clear while minimized
    bool isMinimized;      // yabai space_window_list minimized test
    int cornerRadius;      // 0 if SkyLight does not report one
} KexWindowInfo;

KexWindowInfo kex_window_info(uint32_t windowID);

// Only the window's frame, as the window server has it: for a window known to be moving where it is, nothing else
// about it changing. False when it is gone.
bool kex_window_bounds(uint32_t windowID, CGRect *frame);

// Every window on every Space, minimized included, filtered like kex_space_window_ids.
NSArray<NSNumber *> *kex_all_window_ids(void);

NS_ASSUME_NONNULL_END
