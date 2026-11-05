#pragma once
#import <Foundation/Foundation.h>

// The pointer's shape set by kex over another app's window: AppKit sets the cursor only for the active app, which
// kex never is, so SkyLight's private calls are looked up at run time (SLS, else the older CGS names). Each fails
// soft: where a call is missing or refused, the pointer stays the app's.

// Lets kex's connection set the cursor while another app is active (connection property "SetsCursorInBackground").
// False where the call is missing or refused.
bool kex_cursor_in_background(bool on);

// The cursor seed, which changes each time any app sets the cursor: one kex set and read the seed of, the seed
// since another, was replaced. -1 where the call is missing.
int32_t kex_cursor_seed(void);

// Tags kex's own window `wid` (bit 5) so the window server takes its cursor rects while kex is in the background.
// False where the call is missing or refused.
bool kex_window_cursor_tag(uint32_t wid);

// Whether the calls the hand needs are there: the background setting and the order-out. Without them it never shows.
bool kex_cursor_available(void);

// Orders kex's own window `wid` out through the window server at once, not on AppKit's next turn: an event let
// through after this returns reaches the window under it. False where the call is missing or refused.
bool kex_window_order_out(uint32_t wid);
