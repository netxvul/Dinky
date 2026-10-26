#pragma once
#import <Foundation/Foundation.h>

// A tap of every Force Touch trackpad's actuator, the built-in one and Magic Trackpads, through MultitouchSupport's
// private MTActuator calls, looked up at run time as HapticKey does. NSHapticFeedbackManager only reaches the trackpad
// for the active app, which dinky never is. `actuation` is the pattern: 3 weak, 4 medium, 6 strong. False where
// there is no actuator or the calls are missing.
bool dinky_trackpad_tap(int32_t actuation);

// Closes the actuators found, so the next tap finds them afresh: as a trackpad comes or goes, or the Mac wakes. Main
// thread, as the taps are.
void dinky_trackpad_actuators_reset(void);
