#pragma once
#import <Foundation/Foundation.h>

// Touches on every trackpad, the built-in one and Magic Trackpads, and on Magic Mice, through MultitouchSupport's
// private contact frame callback, looked up at run time as the haptics are. Each frame gives the number of fingers
// down and their centre in millimetres from the surface's bottom left, y up, with the frame's time in seconds, the
// device it came from, whether that is a mouse, and the surface's width in millimetres.
// Called on MultitouchSupport's own thread.
typedef void (^DinkyTouchFrame)(int fingers, double x, double y, double time, uintptr_t device, bool mouse, double width);

// Starts every trackpad and mouse, again whenever one comes or goes, handing each frame to `frame`. False where the calls are
// missing.
bool dinky_touches_start(DinkyTouchFrame frame);
// Stops them all.
void dinky_touches_stop(void);
