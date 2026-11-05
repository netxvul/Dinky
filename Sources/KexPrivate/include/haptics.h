#pragma once
#import <Foundation/Foundation.h>

// A tap of every Force Touch trackpad's actuator, the built-in one and Magic Trackpads, through MultitouchSupport's
// private MTActuator calls, looked up at run time as HapticKey does. NSHapticFeedbackManager only reaches the trackpad
// for the active app, which kex never is. `actuation` is the pattern: 3 weak, 4 medium, 6 strong. Taps off the main
// thread, on a queue of their own; `done` then runs on the main thread, false where there is no actuator or the calls
// are missing.
void kex_trackpad_tap(int32_t actuation, void (^done)(bool tapped));

// Closes the actuators found, so the next tap finds them afresh: as a trackpad comes or goes, or the Mac wakes.
void kex_trackpad_actuators_reset(void);
