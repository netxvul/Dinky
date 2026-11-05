#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// kex's client for its Dock scripting addition (Sources/KexPrivate/osax, injected into Dock). Every call is a
// no-op when the payload is not loaded, so callers fall back to the Accessibility path. Main thread.

// Whether the injected Dock payload answers right now (its socket connects). Cheap; call to choose the glide path.
bool kex_sa_available(void);

// Whether the payload answers, as kex_sa_available, and what it can do, as kex_sa_moves_windows and
// kex_sa_orders_windows: one connection and one handshake for the three.
bool kex_sa_probe(bool *moves, bool *orders);

// Whether the payload can also move windows' real positions in batches (`kex_sa_move_batch`), as one installed
// before it could not. Asks it, so call it as seldom as the above.
bool kex_sa_moves_windows(void);

// Place each window's on-screen transform so its top-left shows at the matching point, in global top-left-origin
// coordinates. Purely visual: the window's real Accessibility frame is untouched, and a point may lie off-screen.
void kex_sa_transform_batch(const uint32_t *wids, const CGPoint *points, int count);

// Move each window's real position so its top-left is at the matching point, in global top-left-origin coordinates,
// without its app being told. Only where `kex_sa_moves_windows`.
void kex_sa_move_batch(const uint32_t *wids, const CGPoint *points, int count);

// Whether the payload can order windows (`kex_sa_order_batch`), as one installed before 0.4.0 cannot. Asks it, so
// call it as seldom as `kex_sa_moves_windows`.
bool kex_sa_orders_windows(void);

// Order each window above every other of its level, in turn, so the last ends frontmost, also above the active app's
// windows; nothing is activated and no key window changes. Only where `kex_sa_orders_windows`.
void kex_sa_order_batch(const uint32_t *wids, int count);

// Clear each window's transform back to its real (Accessibility) position.
void kex_sa_reset_batch(const uint32_t *wids, int count);
