#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Border windows: plain SkyLight windows owned by dinky, one per decorated window, ordered
// directly below or above their target. Either way a border never covers its content: the
// ring's interior is transparent. The noop glow, a border window too, is drawn over the
// target's edge. Every border window ignores the mouse. The JankyBorders approach,
// reimplemented. Every function takes the border's own window ID. Main thread only.

// As CGSOrderingMode. Below, the target's own shadow falls on the ring and darkens it a
// little, as in JankyBorders; above, the ring is drawn over the shadow and keeps its colour.
typedef NS_ENUM(int, DinkyBorderOrder) {
    DinkyBorderOrderBelow = -1,
    DinkyBorderOrderAbove = 1,
};

typedef struct {
    double red, green, blue, alpha;  // 0...1
} DinkyBorderColor;

// A hidden, click-through, shadowless window at `scale` (1 or 2, the target display's
// backing scale). Returns 0 on failure.
uint32_t dinky_border_create(double scale);

// Reshapes and redraws the border as a `width`-point ring hugging `frame` (the target's
// frame in global top-left coordinates) on the outside, then moves it, copies the target's
// level and sub-level and orders it directly next to `target`, all in one transaction.
void dinky_border_update(uint32_t border, uint32_t target, CGRect frame, int cornerRadius,
                         DinkyBorderColor color, double width, DinkyBorderOrder order);

// The noop glow: a `width`-point ring of the colour hugging the target on the outside, left out at width 0, and inside
// it the colour at `alpha` opacity at the target's edge, fading to nothing `depth` points in.
typedef struct {
    double width;
    double depth;
    double alpha;
} DinkyGlow;

// Reshapes and redraws the border as the noop glow around `frame`, at `opacity` as a whole, then places it as
// dinky_border_update does, at `target`'s level but directly above `above`: the target, or the target's own border
// when that is drawn above it. It covers the target's edge, so it is drawn over the window; the window still takes
// every click.
void dinky_glow_update(uint32_t border, uint32_t target, uint32_t above, CGRect frame, int cornerRadius,
                       DinkyBorderColor color, DinkyGlow glow, double opacity);

// Moves the noop glow and orders it directly above `above` again, without redrawing.
void dinky_glow_move(uint32_t border, uint32_t target, uint32_t above, CGRect frame, double width);

// Sets the noop glow's opacity as a whole, 0...1, where it is: a frame of its fading. Nothing is drawn again.
void dinky_glow_fade(uint32_t border, double opacity);

// Moves and re-orders without redrawing: the cheap path for drags and re-tiles that keep the size.
void dinky_border_move(uint32_t border, uint32_t target, CGRect frame, double width,
                       DinkyBorderOrder order);

// The target's level and sub-level, as dinky_border_update and dinky_border_move copy them to the border: two calls to
// the window server.
void dinky_border_level(uint32_t target, int64_t *level, int32_t *subLevel);

// dinky_border_move with the target's level and sub-level as read before (dinky_border_level), for a border following
// a window that only moves, as on every frame of a glide.
void dinky_border_move_at_level(uint32_t border, uint32_t target, CGRect frame, double width, DinkyBorderOrder order,
                                int64_t level, int32_t subLevel);

// Puts the border on the target's Space. New borders start on the current Space.
void dinky_border_move_to_space(uint32_t border, uint64_t spaceID);

void dinky_border_hide(uint32_t border);
void dinky_border_destroy(uint32_t border);

// The front app's frontmost document window on a visible Space, 0 if none.
// JankyBorders get_front_window.
uint32_t dinky_border_focused_window(void);

NS_ASSUME_NONNULL_END
