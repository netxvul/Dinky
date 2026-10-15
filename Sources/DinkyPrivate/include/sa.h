#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// dinky's client for its Dock scripting addition (Sources/DinkyPrivate/osax, injected into Dock). Every call is a
// no-op when the payload is not loaded, so callers fall back to the Accessibility path. Main thread.

// Whether the injected Dock payload answers right now (its socket connects). Cheap; call to choose the glide path.
bool dinky_sa_available(void);

// Place each window's on-screen transform so its top-left shows at the matching point, in global top-left-origin
// coordinates. Purely visual: the window's real Accessibility frame is untouched, and a point may lie off-screen.
void dinky_sa_transform_batch(const uint32_t *wids, const CGPoint *points, int count);

// Clear each window's transform back to its real (Accessibility) position.
void dinky_sa_reset_batch(const uint32_t *wids, int count);
