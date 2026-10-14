#pragma once
#import <Foundation/Foundation.h>

// Touches on every trackpad, the built-in one and Magic Trackpads, through MultitouchSupport's private contact frame
// callback, looked up at run time as the haptics are. Each frame gives the number of fingers down and their centre in
// millimetres from the trackpad's bottom left, y up, with the frame's time in seconds and the trackpad it came from.
// Called on MultitouchSupport's own thread.
typedef void (^DinkyTouchFrame)(int fingers, double x, double y, double time, uintptr_t device);

// Starts every trackpad, again whenever one comes or goes, handing each frame to `frame`. False where the calls are
// missing.
bool dinky_touches_start(DinkyTouchFrame frame);
// Stops them all.
void dinky_touches_stop(void);
