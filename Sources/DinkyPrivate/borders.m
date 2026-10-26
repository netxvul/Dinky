#import "borders.h"
#import "query.h"
#import "skylight.h"
#import <math.h>

// Window creation, shape and drawing, as JankyBorders src/misc/extern.h declares them.
extern CGError CGSNewRegionWithRect(CGRect *rect, CFTypeRef *region);
extern CGError SLSNewWindow(int cid, int type, float x, float y, CFTypeRef region, uint32_t *wid);
extern CGError SLSReleaseWindow(int cid, uint32_t wid);
extern CGError SLSSetWindowTags(int cid, uint32_t wid, uint64_t *tags, int tagSize);
extern CGError SLSSetWindowShape(int cid, uint32_t wid, float x, float y, CFTypeRef shape);
extern CGError SLSSetWindowResolution(int cid, uint32_t wid, double resolution);
extern CGError SLSSetWindowOpacity(int cid, uint32_t wid, bool isOpaque);
extern CGError SLSSetWindowAlpha(int cid, uint32_t wid, float alpha);
extern CGError SLSWindowSetShadowProperties(uint32_t wid, CFDictionaryRef properties);
extern CGError SLSGetWindowLevel(int cid, uint32_t wid, int64_t *level);
extern int32_t SLSGetWindowSubLevel(int cid, uint32_t wid) __attribute__((weak_import));
extern CGContextRef SLWindowContextCreate(int cid, uint32_t wid, CFDictionaryRef options);
extern CGError SLSFlushWindowContentRegion(int cid, uint32_t wid, void *dirty);
extern CGError SLSDisableUpdate(int cid);
extern CGError SLSReenableUpdate(int cid);

extern CFTypeRef SLSTransactionCreate(int cid);
extern CGError SLSTransactionMoveWindowWithGroup(CFTypeRef transaction, uint32_t wid, CGPoint point);
extern CGError SLSTransactionSetWindowLevel(CFTypeRef transaction, uint32_t wid, int level);
extern CGError SLSTransactionSetWindowSubLevel(CFTypeRef transaction, uint32_t wid, int level) __attribute__((weak_import));
extern CGError SLSTransactionOrderWindow(CFTypeRef transaction, uint32_t wid, int order, uint32_t relativeTo);
extern CGError SLSTransactionCommit(CFTypeRef transaction, int synchronous);

// SLSTransactionOrderWindow's order-out mode; DinkyBorderOrder holds the other two.
enum { OrderOut = 0 };

// JankyBorders window_create: floating (bit 1) and ignores mouse events (bit 9), so clicks
// anywhere in the border window, ring or interior, go to the window below it.
static const uint64_t border_tags = (1ULL << 1) | (1ULL << 9);

uint32_t dinky_border_create(double scale)
{
    int cid = dinky_connection();
    CGRect frame = CGRectMake(0, 0, 1, 1);
    CFTypeRef region = NULL;
    CGSNewRegionWithRect(&frame, &region);
    if (!region) return 0;

    uint32_t wid = 0;
    SLSNewWindow(cid, kCGBackingStoreBuffered, -9999, -9999, region, &wid);
    CFRelease(region);
    if (!wid) return 0;

    uint64_t tags = border_tags;
    SLSSetWindowResolution(cid, wid, scale);
    SLSSetWindowTags(cid, wid, &tags, 64);
    SLSSetWindowOpacity(cid, wid, false);
    SLSWindowSetShadowProperties(wid, (__bridge CFDictionaryRef)@{@"com.apple.WindowShadowDensity": @0});
    return wid;
}

// The border window covers the target frame plus `width` on every side.
static CGRect outer_frame(CGRect frame, double width)
{
    return CGRectInset(frame, -width, -width);
}

// Moves, copies the target's level and sub-level and orders next to `relative`, the target or
// a window just above it, in one transaction. SLSGetWindowSubLevel needs Screen Recording and
// returns 0 without it (JankyBorders 7ba72e5), which is every normal window's sub-level anyway.
static void place(uint32_t border, uint32_t target, uint32_t relative, CGPoint origin, DinkyBorderOrder order,
                  bool synchronous)
{
    int cid = dinky_connection();
    int64_t level = 0;
    SLSGetWindowLevel(cid, target, &level);

    CFTypeRef transaction = SLSTransactionCreate(cid);
    if (!transaction) return;
    SLSTransactionMoveWindowWithGroup(transaction, border, origin);
    SLSTransactionSetWindowLevel(transaction, border, (int)level);
    if (SLSGetWindowSubLevel && SLSTransactionSetWindowSubLevel) {
        SLSTransactionSetWindowSubLevel(transaction, border, SLSGetWindowSubLevel(cid, target));
    }
    // A window raised past its target leaves `relative` behind until that is placed again, which may come after this:
    // put it back directly above the target first, so this one lands next to both.
    if (relative != target) SLSTransactionOrderWindow(transaction, relative, order, target);
    SLSTransactionOrderWindow(transaction, border, order, relative);
    SLSTransactionCommit(transaction, synchronous);
    CFRelease(transaction);
}

// CGPathAddRoundedRect needs the radius to fit in the rect.
static void add_rounded_rect(CGMutablePathRef path, CGRect rect, double radius)
{
    radius = MAX(0, MIN(radius, MIN(rect.size.width, rect.size.height) / 2));
    CGPathAddRoundedRect(path, NULL, rect, radius, radius);
}

// A ring filled between the outer edge and the target's own rounded outline, interior left
// transparent. Everything is in points: the context comes scaled to the border's resolution,
// so the same width and radii are right at 1x and 2x. The outer edge grows the target's
// radius by the width.
static void draw(uint32_t border, CGSize size, int cornerRadius, DinkyBorderColor color, double width)
{
    int cid = dinky_connection();
    CGContextRef context = SLWindowContextCreate(cid, border, NULL);
    if (!context) return;

    CGRect bounds = { CGPointZero, size };
    CGMutablePathRef ring = CGPathCreateMutable();
    add_rounded_rect(ring, bounds, cornerRadius + width);
    add_rounded_rect(ring, CGRectInset(bounds, width, width), cornerRadius);

    CGContextClearRect(context, bounds);
    CGContextSetRGBFillColor(context, color.red, color.green, color.blue, color.alpha);
    CGContextAddPath(context, ring);
    CGContextEOFillPath(context);
    CGPathRelease(ring);

    CGContextFlush(context);
    CGContextRelease(context);
    SLSFlushWindowContentRegion(cid, border, NULL);
}

void dinky_border_update(uint32_t border, uint32_t target, CGRect frame, int cornerRadius,
                         DinkyBorderColor color, double width, DinkyBorderOrder order)
{
    int cid = dinky_connection();
    CGRect outer = outer_frame(frame, width);
    CGRect shape = { CGPointZero, outer.size };
    CFTypeRef region = NULL;
    CGSNewRegionWithRect(&shape, &region);
    if (!region) return;

    // Hold screen updates so the reshaped, redrawn and moved border appears at once.
    SLSDisableUpdate(cid);
    SLSSetWindowShape(cid, border, 0, 0, region);
    draw(border, outer.size, cornerRadius, color, width);
    // Finish placement before screen updates resume; an asynchronous commit can expose
    // the reshaped border at its temporary origin for a frame during a focus redraw.
    place(border, target, target, outer.origin, order, true);
    SLSReenableUpdate(cid);
    CFRelease(region);
}

// How round a glow edge `depth` points into a window rounding its corners by `radius` is, negative outside it: outside,
// the ring's outer edge grows the radius by the width as a border's does; inside, the glow rounds more the deeper it
// reaches, as the screen's glow does at its corners.
static double glow_radius(int radius, double depth)
{
    return depth < 0 ? radius - depth : radius + depth / 2;
}

// Fills the band from `from` to `to` points into `frame`, negative outside it, with `color` at `alpha` times its own.
// Copied rather than blended: what was there goes, except where an anti-aliased edge covers a pixel only in part.
static void fill_band(CGContextRef context, CGRect frame, int radius, double from, double to,
                      DinkyBorderColor color, double alpha)
{
    CGRect outer = CGRectInset(frame, from, from), inner = CGRectInset(frame, to, to);
    if (CGRectIsEmpty(outer)) return;
    CGMutablePathRef band = CGPathCreateMutable();
    add_rounded_rect(band, outer, glow_radius(radius, from));
    if (!CGRectIsEmpty(inner)) add_rounded_rect(band, inner, glow_radius(radius, to));
    CGContextSetRGBFillColor(context, color.red, color.green, color.blue, color.alpha * alpha);
    CGContextAddPath(context, band);
    CGContextEOFillPath(context);
    CGPathRelease(band);
}

// How strong the glow is `share` of the way in from the window's edge to as deep as it reaches: falling off as the
// screen's glow does, by e every third of the way, and down to nothing at the end.
static double glow_falloff(double share)
{
    return (exp(-3 * share) - exp(-3)) / (1 - exp(-3));
}

// The glow in a border window of `size`, the target's frame `width` in from its edges: the ring, then the glow inside
// in steps of a point, each at the strength of its middle, too fine for the eye to tell apart. Outermost first, each
// reaching a point past where the next one starts: copied over that point, the next one's anti-aliased edge blends into
// it rather than into nothing, so neighbours meet without a seam.
static void draw_glow(uint32_t border, CGSize size, int cornerRadius, DinkyBorderColor color, DinkyGlow glow)
{
    int cid = dinky_connection();
    CGContextRef context = SLWindowContextCreate(cid, border, NULL);
    if (!context) return;

    CGRect bounds = { CGPointZero, size };
    CGRect frame = CGRectInset(bounds, glow.width, glow.width);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextClearRect(context, bounds);
    if (glow.width > 0) {
        fill_band(context, frame, cornerRadius, -glow.width, glow.depth > 0 ? 1 : 0, color, 1);
    }
    for (double from = 0; from < glow.depth; from += 1) {
        double to = MIN(from + 1, glow.depth);
        fill_band(context, frame, cornerRadius, from, to < glow.depth ? to + 1 : to, color,
                  glow.alpha * glow_falloff((from + to) / 2 / glow.depth));
    }

    CGContextFlush(context);
    CGContextRelease(context);
    SLSFlushWindowContentRegion(cid, border, NULL);
}

void dinky_glow_update(uint32_t border, uint32_t target, uint32_t above, CGRect frame, int cornerRadius,
                       DinkyBorderColor color, DinkyGlow glow, double opacity)
{
    int cid = dinky_connection();
    CGRect outer = outer_frame(frame, glow.width);
    CGRect shape = { CGPointZero, outer.size };
    CFTypeRef region = NULL;
    CGSNewRegionWithRect(&shape, &region);
    if (!region) return;

    SLSDisableUpdate(cid);
    SLSSetWindowShape(cid, border, 0, 0, region);
    draw_glow(border, outer.size, cornerRadius, color, glow);
    dinky_glow_fade(border, opacity);
    place(border, target, above, outer.origin, DinkyBorderOrderAbove, true);
    SLSReenableUpdate(cid);
    CFRelease(region);
}

void dinky_glow_fade(uint32_t border, double opacity)
{
    SLSSetWindowAlpha(dinky_connection(), border, (float)opacity);
}

void dinky_glow_move(uint32_t border, uint32_t target, uint32_t above, CGRect frame, double width)
{
    place(border, target, above, outer_frame(frame, width).origin, DinkyBorderOrderAbove, false);
}

void dinky_border_move(uint32_t border, uint32_t target, CGRect frame, double width, DinkyBorderOrder order)
{
    place(border, target, target, outer_frame(frame, width).origin, order, false);
}

void dinky_border_move_to_space(uint32_t border, uint64_t spaceID)
{
    SLSMoveWindowsToManagedSpace(dinky_connection(), (__bridge CFArrayRef)@[@(border)], spaceID);
}

void dinky_border_hide(uint32_t border)
{
    CFTypeRef transaction = SLSTransactionCreate(dinky_connection());
    if (!transaction) return;
    SLSTransactionOrderWindow(transaction, border, OrderOut, 0);
    SLSTransactionCommit(transaction, 0);
    CFRelease(transaction);
}

void dinky_border_destroy(uint32_t border)
{
    SLSReleaseWindow(dinky_connection(), border);
}

// JankyBorders get_front_window: the front app's first suitable window on a current Space.
uint32_t dinky_border_focused_window(void)
{
    int owner = dinky_front_connection();
    if (!owner) return 0;

    // Document-tagged windows of the front app, front to back. A minimized one is never focused.
    int cid = dinky_connection();
    uint64_t set_tags = 1;
    uint64_t clear_tags = 0;
    NSArray *spaces = dinky_current_space_ids();
    CFArrayRef windows = SLSCopyWindowsWithOptionsAndTags(cid, owner, (__bridge CFArrayRef)spaces, 0x2, &set_tags, &clear_tags);
    if (!windows) return 0;

    uint32_t focused = 0;
    int count = (int)CFArrayGetCount(windows);
    if (count) {
        CFTypeRef query = SLSWindowQueryWindows(cid, windows, count);
        CFTypeRef iterator = query ? SLSWindowQueryResultCopyWindows(query) : NULL;

        // The iterator yields windows in the input array's order, so the first match is the
        // frontmost. JankyBorders get_front_window relies on the same. A window floating above the normal
        // level, as a picture in picture video does in front of every window of its app, is never the one
        // its app has focused: the frontmost at the normal level is, and the floating one only when the
        // app has no other.
        uint32_t floating = 0;
        while (iterator && SLSWindowIteratorAdvance(iterator)) {
            uint32_t wid = SLSWindowIteratorGetWindowID(iterator);
            uint32_t parent = SLSWindowIteratorGetParentID(iterator);
            uint64_t tags = SLSWindowIteratorGetTags(iterator);
            uint64_t attributes = SLSWindowIteratorGetAttributes(iterator);
            if (dinky_is_document_kind(parent, tags) && dinky_is_visible(attributes, tags)) {
                int64_t level = 0;
                SLSGetWindowLevel(cid, wid, &level);
                if (level > kCGNormalWindowLevel) {
                    if (!floating) floating = wid;
                    continue;
                }
                focused = wid;
                break;
            }
        }
        if (!focused) focused = floating;

        if (iterator) CFRelease(iterator);
        if (query) CFRelease(query);
    }
    CFRelease(windows);
    return focused;
}
