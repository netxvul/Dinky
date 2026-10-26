// Wire protocol shared by dinky's Dock payload and dinky's client, and the payload's build.
// Modelled on yabai's src/osax/common.h (MIT, © 2019 Åsmund Vikane); dinky's opcodes are its own.
//
// A message is [int16 length][opcode][payload], length counting the bytes after itself (opcode + payload),
// little-endian, fields packed raw. The daemon replies with one byte so the client knows it was handled.
#ifndef DINKY_SA_COMMON_H
#define DINKY_SA_COMMON_H

#define DINKY_SA_SOCKET_PATH_FMT "/tmp/dinky-sa_%s.socket"
#define DINKY_SA_SOCKET_BUFF_LEN 0x4000
#define DINKY_SA_VERSION "0.4.0"

// Capabilities the payload reports in its handshake, so the client can fall back when one is missing. Attribute 0x04
// and opcode 0x07 went to a move-and-transform message in payloads before 0.3.0, and are left unused.
#define DINKY_SA_ATTRIB_MOVE       0x01
#define DINKY_SA_ATTRIB_TRANSFORM  0x02
#define DINKY_SA_ATTRIB_MOVE_BATCH 0x08
// Since 0.4.0. A payload before it ignores the opcode, its switch having no case for it, and still acks.
#define DINKY_SA_ATTRIB_ORDER      0x10
#define DINKY_SA_ATTRIB_ALL        (DINKY_SA_ATTRIB_MOVE | DINKY_SA_ATTRIB_TRANSFORM | DINKY_SA_ATTRIB_MOVE_BATCH \
                                    | DINKY_SA_ATTRIB_ORDER)

enum dinky_sa_opcode {
    DINKY_SA_OP_HANDSHAKE        = 0x01,
    // Move a window's real position (SLSMoveWindowWithGroup): (uint32 wid, int32 x, int32 y).
    DINKY_SA_OP_WINDOW_MOVE      = 0x02,
    // Set a window's on-screen transform so its top-left shows at (x,y): (uint32 wid, float x, float y).
    DINKY_SA_OP_WINDOW_TRANSFORM = 0x03,
    // Set many windows' transforms at once: (int32 count) then count * (uint32 wid, float x, float y).
    DINKY_SA_OP_TRANSFORM_BATCH  = 0x04,
    // Clear a window's transform back to its real position: (uint32 wid).
    DINKY_SA_OP_TRANSFORM_RESET  = 0x05,
    // Clear many windows' transforms at once: (int32 count) then count * (uint32 wid).
    DINKY_SA_OP_RESET_BATCH      = 0x06,
    // Move many windows' real positions at once: (int32 count) then count * (uint32 wid, float x, float y).
    DINKY_SA_OP_MOVE_BATCH       = 0x08,
    // Order many windows above all others of their level, in turn, so the last ends frontmost; nothing is activated
    // and no key window changes: (int32 count) then count * (uint32 wid).
    DINKY_SA_OP_ORDER_BATCH      = 0x09,
};

#endif
