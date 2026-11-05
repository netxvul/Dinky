#pragma once
#import <Foundation/Foundation.h>

// Only the mimi augmented swipe is left; RESULTS.md records the paths the spike tried.
// Swipes from fromIndex to toIndex (1-based) on the display with displayUUID and returns whether
// posting succeeded. Refuses an unknown display. Does not wait for the switch, but warps the cursor to
// that display for the swipe when it is elsewhere and waits about 60 ms to put it back.
bool kex_switch_to_space_index(int fromIndex, int toIndex, CFStringRef displayUUID);
