#import "borders.h"
#import "query.h"
#import "skylight.h"

// Window creation, shape and drawing, as JankyBorders src/misc/extern.h declares them.
extern CGError CGSNewRegionWithRect(CGRect *rect, CFTypeRef *region);
extern CGError SLSNewWindow(int cid, int type, float x, float y, CFTypeRef region, uint32_t *wid);
extern CGError SLSReleaseWindow(int cid, uint32_t wid);
extern CGError SLSSetWindowTags(int cid, uint32_t wid, uint64_t *tags, int tagSize);
extern CGError SLSSetWindowShape(int cid, uint32_t wid, float x, float y, CFTypeRef shape);
extern CGError SLSSetWindowResolution(int cid, uint32_t wid, double resolution);
extern CGError SLSSetWindowOpacity(int cid, uint32_t wid, bool isOpaque);
extern CGError SLSWindowSetShadowProperties(uint32_t wid, CFDictionaryRef properties);
extern CGError SLSSetWindowAlpha(int cid, uint32_t wid, float alpha);
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

// Moves, copies the level and sub-level and orders next to the target, in one transaction.
// SLSGetWindowSubLevel needs Screen Recording and returns 0 without it (JankyBorders
// 7ba72e5), which is every normal window's sub-level anyway.
static void place(uint32_t border, uint32_t target, CGPoint origin, DinkyBorderOrder order, bool synchronous)
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
    SLSTransactionOrderWindow(transaction, border, order, target);
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
    place(border, target, outer.origin, order, true);
    SLSReenableUpdate(cid);
    CFRelease(region);
}

// The glow: bands half a point wide from `spread` outside the target's edge to half that inside, each `color` at the
// strength (1 - t)^1.5, t the band's distance from the edge over the distance to that side's end. Drawn outermost first,
// each band copied over the inner half of the one before, so neighbours meet without a seam and their colours never
// stack.
static void draw_glow(uint32_t border, CGSize size, int cornerRadius, DinkyBorderColor color, double spread)
{
    int cid = dinky_connection();
    CGContextRef context = SLWindowContextCreate(cid, border, NULL);
    if (!context) return;

    static const double step = 0.5;
    CGRect bounds = { CGPointZero, size };
    CGRect edge = CGRectInset(bounds, spread, spread);
    double inside = spread / 2;

    CGContextClearRect(context, bounds);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    // `d` is how far the band's outer edge is outside the target's edge, negative inside it.
    for (double d = spread; d > -inside; d -= step) {
        CGRect outer = CGRectInset(edge, -d, -d), inner = CGRectInset(edge, -(d - 2 * step), -(d - 2 * step));
        if (CGRectIsEmpty(inner)) break;
        double middle = d - step / 2;
        double t = MIN(middle > 0 ? middle / spread : -middle / inside, 1);
        CGMutablePathRef band = CGPathCreateMutable();
        add_rounded_rect(band, outer, cornerRadius + d);
        add_rounded_rect(band, inner, cornerRadius + d - 2 * step);
        CGContextSetRGBFillColor(context, color.red, color.green, color.blue, color.alpha * pow(1 - t, 1.5));
        CGContextAddPath(context, band);
        CGContextEOFillPath(context);
        CGPathRelease(band);
    }

    CGContextFlush(context);
    CGContextRelease(context);
    SLSFlushWindowContentRegion(cid, border, NULL);
}

void dinky_glow_update(uint32_t border, uint32_t target, CGRect frame, int cornerRadius,
                       DinkyBorderColor color, double spread)
{
    int cid = dinky_connection();
    CGRect outer = outer_frame(frame, spread);
    CGRect shape = { CGPointZero, outer.size };
    CFTypeRef region = NULL;
    CGSNewRegionWithRect(&shape, &region);
    if (!region) return;

    SLSDisableUpdate(cid);
    SLSSetWindowShape(cid, border, 0, 0, region);
    draw_glow(border, outer.size, cornerRadius, color, spread);
    place(border, target, outer.origin, DinkyBorderOrderAbove, true);
    SLSReenableUpdate(cid);
    CFRelease(region);
}

void dinky_border_set_alpha(uint32_t border, double alpha)
{
    SLSSetWindowAlpha(dinky_connection(), border, (float)alpha);
}

void dinky_border_move(uint32_t border, uint32_t target, CGRect frame, double width, DinkyBorderOrder order)
{
    place(border, target, outer_frame(frame, width).origin, order, false);
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
        // frontmost. JankyBorders get_front_window relies on the same.
        while (iterator && SLSWindowIteratorAdvance(iterator)) {
            uint32_t wid = SLSWindowIteratorGetWindowID(iterator);
            uint32_t parent = SLSWindowIteratorGetParentID(iterator);
            uint64_t tags = SLSWindowIteratorGetTags(iterator);
            uint64_t attributes = SLSWindowIteratorGetAttributes(iterator);
            if (dinky_is_document_kind(parent, tags) && dinky_is_visible(attributes, tags)) {
                focused = wid;
                break;
            }
        }

        if (iterator) CFRelease(iterator);
        if (query) CFRelease(query);
    }
    CFRelease(windows);
    return focused;
}
