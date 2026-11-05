#!/usr/bin/env python3
"""Fuzzes a running kex app with random window, app and workspace actions and checks layout invariants.

Runs inside the VM guest (see `just fuzz`), next to a running `kex app`. Each step runs one random action, waits
for kex's animations to finish (at least 0.8 s) and reads `kex debug-state`, waits 1.5 s more and reads it again.
An animation still running after 3 s is a violation. Invariants are checked on the second
state (what was only late is noted as "settled late"), and anything that moved between the two, with nothing
happening, is a "spontaneous shift". Violations are printed as they are found and the run goes on.

    python3 fuzz.py --seed 1 --steps 150 --kex ~/kex-fuzz
    python3 fuzz.py --seed 1 --steps 150 --switching   # quits, closes, activations and Space switches dominate

The idle wait also polls the current Space: a display that changes Space three or more times while nothing
happens is a "loop", the follower and macOS chasing each other's activations.
"""
import argparse, json, os, random, subprocess, sys, time

APPS = {"com.apple.TextEdit", "com.apple.finder", "com.apple.Safari"}
MIN_WINDOWS, MAX_WINDOWS = 3, 8
DOCS = "/tmp/kex-fuzz"
KEYS = os.path.expanduser("~/kex-fuzz-keys")
MOUSE = os.path.expanduser("~/kex-fuzz-mouse")
# mouse <x> <y> [steps]: mouseMoved events ending at x,y, for focus-follows-mouse. No arguments: print the position.
MOUSE_SOURCE = """
import CoreGraphics
import Foundation
if CommandLine.arguments.count < 3 {
    let p = CGEvent(source: nil)!.location
    print(Int(p.x), Int(p.y))
    exit(0)
}
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let steps = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 1
let from = CGEvent(source: nil)!.location
for i in 1...steps {
    let t = Double(i) / Double(steps)
    let p = CGPoint(x: from.x + (x - from.x) * t, y: from.y + (y - from.y) * t)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(10_000)
}
"""
# drag <x1> <y1> <x2> <y2>: press, drag in steps and release, as a hand moving a window by its title bar.
DRAG = os.path.expanduser("~/kex-fuzz-drag")
DRAG_SOURCE = """
import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().compactMap { Double($0) }
let (from, to) = (CGPoint(x: a[0], y: a[1]), CGPoint(x: a[2], y: a[3]))
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
}
post(.mouseMoved, from); usleep(100_000)
post(.leftMouseDown, from); usleep(100_000)
for i in 1...20 {
    let t = Double(i) / 20
    post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)); usleep(16_000)
}
usleep(200_000)
post(.leftMouseUp, to)
"""
# Control-Arrow with the secondary-fn flag, as Mission Control expects, <count> times. The fuzzer posts it in
# kex's `service` mode, which does not bind ctrl-left/right, so the switch is the native one.
KEYS_SOURCE = """
import CoreGraphics
import Foundation
let key: CGKeyCode = CommandLine.arguments[1] == "left" ? 123 : 124
for _ in 0..<(Int(CommandLine.arguments[2]) ?? 1) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
        event.flags = [.maskControl, .maskSecondaryFn]
        event.post(tap: .cghidEventTap)
        usleep(50_000)
    }
}
"""


class Fuzzer:
    def __init__(self, seed, kex, switching=False):
        self.rng, self.seed, self.kex = random.Random(seed), seed, kex
        self.switching = switching
        self.history, self.docs = [], 0
        self.seen, self.found = set(), {}  # violations reported last step; count per class
        self.landing, self.landings = None, []  # a step's trip to an empty workspace; all of them
        self.animated = 0  # steps during which kex was seen animating

    def run(self, *cmd):
        self.history.append(" ".join(str(c) for c in cmd))
        return subprocess.run([str(c) for c in cmd], capture_output=True, text=True, timeout=20).returncode == 0

    def cli(self, *args):
        return self.run(self.kex, *args)

    def state(self):
        """`kex debug-state`, with each display's workspaces (their Spaces, by number) listed on it. The VM has one
        display, so a workspace's place in that list plus one is its number."""
        out = subprocess.run([self.kex, "debug-state"], capture_output=True, text=True, timeout=10)
        if out.returncode != 0: return None
        s = json.loads(out.stdout)
        numbered = sorted(s["workspaces"].items(), key=lambda item: int(item[0]))
        for d in s["displays"]: d["workspaces"] = [space for _, space in numbered if space in d["spaces"]]
        return s

    def windows(self, s, where=lambda w: True):
        return [w for w in s["windows"] if w["bundle-id"] in APPS and where(w)]

    def count(self, s):
        return len(self.windows(s, lambda w: w["normal"] or w["minimized"] or w["hidden"]))

    def visible(self, s):
        return self.windows(s, lambda w: w["normal"] and w["live-space"] == s["displays"][0]["current-space"])

    # Actions. Each returns False when it does not apply now, and another is drawn.

    def open_doc(self, s):
        if self.count(s) >= MAX_WINDOWS: return False
        self.docs += 1
        with open(f"{DOCS}/doc-{self.docs}.txt", "w") as f: f.write(f"document {self.docs}\n")
        return self.run("open", "-a", "TextEdit", f"{DOCS}/doc-{self.docs}.txt")

    def reopen_doc(self, s):  # brings an open document forward, or opens a closed one again
        if not self.docs or self.count(s) >= MAX_WINDOWS: return False
        return self.run("open", "-a", "TextEdit", f"{DOCS}/doc-{self.rng.randint(1, self.docs)}.txt")

    def open_finder(self, s):
        if self.count(s) >= MAX_WINDOWS: return False
        return self.run("open", os.path.expanduser(self.rng.choice(["~", "~/Documents", "~/Downloads", "/Applications"])))

    def open_safari(self, s):
        return self.count(s) < MAX_WINDOWS and self.run("open", "-a", "Safari")

    def close(self, s):
        ws = self.visible(s)
        return self.count(s) > MIN_WINDOWS and bool(ws) and self.cli("debug", "ax-close", self.rng.choice(ws)["id"])

    def quit(self, s):  # TextEdit or Safari, as Cmd-Q would
        apps = sorted({w["app"] for w in self.windows(s) if w["app"] != "Finder"})
        return bool(apps) and self.run("pkill", "-x", self.rng.choice(apps))

    def minimize(self, s):
        ws = self.visible(s)
        return bool(ws) and self.cli("debug", "ax-minimize", self.rng.choice(ws)["id"])

    def unminimize(self, s):
        ws = self.windows(s, lambda w: w["minimized"])
        return bool(ws) and self.cli("debug", "ax-unminimize", self.rng.choice(ws)["id"])

    def hide(self, s):
        pids = sorted({w["pid"] for w in self.visible(s) if not w["hidden"]})
        if not pids: return False
        return self.cli("debug", "hide-app", self.rng.choice(pids))

    def unhide(self, s):
        pids = sorted({w["pid"] for w in self.windows(s, lambda w: w["hidden"])})
        if not pids: return False
        return self.cli("debug", "unhide-app", self.rng.choice(pids))

    def activate(self, s):  # the Cmd-Tab path: activate an app that has windows somewhere
        apps = sorted({w["app"] for w in self.windows(s, lambda w: w["normal"] or w["hidden"])})
        if not apps: return False
        return self.run("open", "-a", self.rng.choice(apps))

    def workspace(self, s):
        n = len(s["displays"][0]["workspaces"])
        return self.cli(*self.rng.choice([["workspace", self.rng.randint(1, n)], ["workspace", "next"],
                                          ["workspace", "prev"], ["workspace-back-and-forth"]]))

    def move_to_workspace(self, s):
        n = len(s["displays"][0]["workspaces"])
        return self.cli("move-window-to-workspace", self.rng.randint(1, n), *(["--follow"] if self.rng.random() < 0.4 else []))

    def native_switch(self, s, direction=None, times=1):
        self.tool(KEYS, KEYS_SOURCE)
        self.cli("mode", "service")
        ok = self.run(KEYS, direction or self.rng.choice(["left", "right"]), times)
        time.sleep(0.6 * times)  # each keystroke plays the slide
        self.cli("mode", "main")
        return ok

    def tool(self, path, source):
        if not os.path.exists(path) or open(path + ".swift").read() != source:
            with open(path + ".swift", "w") as f: f.write(source)
            subprocess.run(["swiftc", "-O", path + ".swift", "-o", path], check=True)
        return path

    def mouse(self, s):
        """Moves the pointer onto a visible window, or a few points within the current one, as a hand on a mouse does."""
        self.tool(MOUSE, MOUSE_SOURCE)
        ws = [w for w in self.visible(s) if w["live-frame"]]
        if ws and self.rng.random() < 0.5:
            f = self.rng.choice(ws)["live-frame"]
            x, y = int(f[0] + f[2] * self.rng.uniform(0.2, 0.8)), int(f[1] + f[3] * self.rng.uniform(0.2, 0.8))
            return self.run(MOUSE, x, y, self.rng.choice([1, 5, 20]))
        out = subprocess.run([MOUSE], capture_output=True, text=True).stdout.split()
        x, y = (int(out[0]), int(out[1])) if len(out) == 2 else (500, 400)
        return self.run(MOUSE, x + self.rng.randint(-4, 4), y + self.rng.randint(-4, 4))

    def native_fullscreen(self, s):
        """Toggles native full screen on a visible window with ctrl-cmd-f, giving it its own Space, or back."""
        ws = self.visible(s)
        if not ws: return False
        w = self.rng.choice(ws)
        self.run("open", "-a", w["app"])
        time.sleep(0.5)
        self.history.append(f"ctrl-cmd-f on {w['id']} ({w['app']})")
        ok = subprocess.run(["osascript", "-e", 'tell application "System Events" to keystroke "f" using {control down, command down}'],
                            capture_output=True, text=True).returncode == 0
        time.sleep(1.5)  # the full-screen slide
        return ok

    def go_empty(self, s):
        """To an empty workspace, by kex or by the native keystroke, sometimes then activating an app from there."""
        d = s["displays"][0]
        occupied = {w["live-space"] for w in s["windows"] if w["normal"] and not w["minimized"]}
        empty = [i for i, sp in enumerate(d["workspaces"]) if sp not in occupied and sp != d["current-space"]]
        if not empty or d["current-space"] not in d["workspaces"]: return False
        i, here = self.rng.choice(empty), d["workspaces"].index(d["current-space"])
        how = self.rng.choice(["kex", "native"])
        if how == "kex": self.cli("workspace", i + 1)
        else: self.native_switch(s, "right" if i > here else "left", abs(i - here))
        if self.rng.random() < 0.4:  # 0.5 or 1.5 s later: past the arrival activation, so this one is followed
            delay = self.rng.choice([0.5, 1.5])
            time.sleep(delay)
            how += f" + activate after {delay} s"
            self.activate(s)
        self.landing = (how, i + 1, d["workspaces"][i])
        return True

    def twin(self, s):
        """A window shown at exactly the frame of another tile of its app, as Ghostty opens every new window."""
        pairs = [(a, b) for a in self.visible(s) for b in self.visible(s) if a["id"] != b["id"] and a["pid"] == b["pid"]]
        if not pairs: return False
        tile, twin = self.rng.choice(pairs)
        self.cli("debug", "ax-minimize", twin["id"])
        time.sleep(1)
        frame = next((w["live-frame"] for w in self.state()["windows"] if w["id"] == tile["id"]), None)
        if frame: self.cli("debug", "ax-frame", twin["id"], *[int(v) for v in frame])
        return self.cli("debug", "ax-unminimize", twin["id"])

    def command(self, s):
        d = self.rng.choice(["left", "right", "up", "down"])
        return self.cli(*self.rng.choice([
            ["focus", d], ["focus", d, "--wrap-around"], ["move", d], ["join-with", d], ["layout", "accordion"],
            ["layout", "tiles"], ["layout", "floating", "tiling"], ["fullscreen"], ["balance-sizes"],
            ["resize", "smart", self.rng.choice(["+50", "-50", "+120", "-120"])], ["flatten-workspace-tree"], ["retile"],
        ]))

    def burst(self, s):
        """Several commands back to back, each landing while the last one's animation is still under way,
        as when flipping between windows: animations retarget, and final writes race steps."""
        cmds = [["focus", "left"], ["focus", "right"], ["layout", "accordion"], ["layout", "tiles"], ["move", "left"],
                ["move", "right"], ["resize", "smart", "+80"], ["resize", "smart", "-80"]]
        for _ in range(self.rng.randint(3, 8)):
            self.cli(*self.rng.choice(cmds))
            time.sleep(self.rng.choice([0, 0.02, 0.05]))
        return True

    def drag(self, s):
        """Drags a TextEdit window by its title bar onto another tile, or a little way and back to its own."""
        self.tool(DRAG, DRAG_SOURCE)
        ws = [w for w in self.visible(s) if w["live-frame"] and w["app"] == "TextEdit"]
        others = [w for w in self.visible(s) if w["live-frame"]]
        if not ws or len(others) < 2: return False
        f = self.rng.choice(ws)["live-frame"]
        x, y = f[0] + f[2] / 2, f[1] + 12
        if self.rng.random() < 0.7:
            t = self.rng.choice([w for w in others if w["live-frame"] != f])["live-frame"]
            tx, ty = t[0] + t[2] / 2, t[1] + t[3] / 2
        else:
            tx, ty = x + self.rng.randint(-60, 60), y + self.rng.randint(20, 80)
        return self.run(DRAG, int(x), int(y), int(tx), int(ty))

    def idle(self, s):
        self.history.append("idle 2s")
        time.sleep(2)
        return True

    ACTIONS = [  # (weight, action); TextEdit documents and moves dominate, so one app often spans two Spaces
        (6, open_doc), (4, reopen_doc), (2, open_finder), (1, open_safari), (4, close), (1, quit), (2, minimize),
        (2, unminimize), (1, hide), (2, unhide), (4, activate), (5, workspace), (7, move_to_workspace),
        (2, native_switch), (5, go_empty), (3, twin), (10, command), (2, idle), (5, burst), (3, drag),
    ]
    SWITCHING_ACTIONS = [  # apps come and go and focus falls back, on and across Spaces, with a hand on the mouse
        (5, open_doc), (3, reopen_doc), (2, open_finder), (3, open_safari), (8, close), (5, quit), (2, minimize),
        (2, unminimize), (3, hide), (3, unhide), (8, activate), (5, workspace), (6, move_to_workspace),
        (3, native_switch), (5, go_empty), (2, command), (1, idle), (8, mouse), (2, native_fullscreen), (2, burst),
    ]
    # Actions after which the display should still be on the same Space.
    STAYS = {close, quit, minimize, unminimize, hide, twin, command, idle, burst, drag}

    # Invariants

    def check(self, s):
        """Violations in one state, as {(class, subject): message}. Frames are checked for the fuzzed apps only:
        Terminal, left open in the VM, snaps to its character grid below the requested size."""
        v, owner = {}, {}
        current = {d["current-space"] for d in s["displays"]}
        numbered = {sp for d in s["displays"] for sp in d["workspaces"]}
        windows = {w["id"]: w for w in s["windows"]}
        placements = {p["id"]: p for p in s["placements"]}
        minimums = {int(k) for k in s["minimum-sizes"]}
        for t in s["trees"]:
            for id in t["windows"]:
                if id in owner: v[("c-two-trees", id)] = f"window {id} is in the trees of Spaces {owner[id]} and {t['space']}"
                owner[id], w, expected = t["space"], windows.get(id), t["expected"][str(id)]
                if not w or not w["live-frame"]:
                    v[("c-gone", id)] = f"window {id} is in the tree of Space {t['space']} but does not exist"
                elif w["live-space"] != t["space"]:
                    v[("c-wrong-space", id)] = f"window {id} ({w['app']}) is in the tree of Space {t['space']} but on {w['live-space']}"
                elif t["space"] in current and id not in minimums and w["bundle-id"] in APPS and not close(w["live-frame"], expected):
                    v[("a-frame", id)] = f"window {id} ({w['app']}) is at {w['live-frame']}, expected {expected}"
            if t["space"] not in current: continue
            ids = [i for i in t["windows"] if windows.get(i, {}).get("live-frame") and i not in minimums]
            for i, a in enumerate(ids):
                for b in ids[i + 1:]:
                    if not overlap(t["expected"][str(a)], t["expected"][str(b)]) and overlap(windows[a]["live-frame"], windows[b]["live-frame"]):
                        v[("b-overlap", (a, b))] = f"tiles {a} and {b} overlap on Space {t['space']}"
        for w in s["windows"]:
            p = placements.get(w["id"])
            if w["normal"] and not w["minimized"] and w["live-space"] in current & numbered and \
                    (not p or not p["floating"] and p["space"] != w["live-space"]):
                v[("d-untracked", w["id"])] = f"window {w['id']} ({w['app']}) is shown on Space {w['live-space']} but placed {p}"
        p = placements.get(s["focused"])
        if p and not p["floating"] and p["space"] and p["space"] not in current:
            v[("e-focus-hidden", s["focused"])] = f"focused window {s['focused']} is tiled on hidden Space {p['space']}"
        area = s["displays"][0]["visible-area"]
        for id, size in s["minimum-sizes"].items():
            # A window that cannot shrink below nearly the whole display is a lagging readback, not a minimum.
            if size[0] > 0.85 * area[2] or size[1] > 0.85 * area[3]:
                v[("j-minimum", int(id))] = f"window {id} has minimum size {size}, nearly the display ({area[2]}x{area[3]})"
        if s["dragging"]:
            v[("k-dragging", s["dragging"])] = f"kex still thinks window {s['dragging']} is being dragged"
        out = subprocess.run([self.kex, "list-workspaces", "--focused"], capture_output=True, text=True).stdout.strip()
        d = s["displays"][0]
        if out.isdigit() and d["workspaces"][int(out) - 1] != d["current-space"]:
            v[("f-focused-workspace", 0)] = f"list-workspaces --focused says {out}, the display is on Space {d['current-space']}"
        return v

    def shifts(self, a, b):
        """What changed between two states with nothing happening in between. A window shown or hidden late explains
        any change, and a tile still settling towards its expected frame is not a shift."""
        shown = lambda s: {w["id"] for w in s["windows"] if w["normal"] and not w["minimized"]}
        if shown(a) != shown(b): return {}
        v, sa, sb = {}, summary(a), summary(b)
        if sa["current"] != sb["current"]:
            v[("shift-space", 0)] = f"the current Space changed while idle: {sa['current']} -> {sb['current']}"
        if sa["trees"] != sb["trees"]:
            v[("shift-tree", 0)] = "a tree changed while idle"
        for id in sa["frames"].keys() & sb["frames"].keys():
            if close(sa["frames"][id], sa["expected"][id]) and not close(sa["frames"][id], sb["frames"][id]):
                v[("shift-frame", id)] = f"tiled window {id} moved while idle: {sa['frames'][id]} -> {sb['frames'][id]}"
        return v

    # The run

    def report(self, step, violations, before, after):
        new = {k: m for k, m in violations.items() if k not in self.seen}
        self.seen = set(violations)
        for kind, _ in new: self.found[kind] = self.found.get(kind, 0) + 1
        if not new: return
        print(f"\n=== VIOLATION seed {self.seed} step {step}")
        for message in new.values(): print("  " + message)
        print("  last actions:\n    " + "\n    ".join(self.history[-10:]))
        print("  diff:\n    " + "\n    ".join(diff(before, after) or ["(none)"]))

    def setup(self):
        """No TextEdit windows (nothing restored), no Finder or Safari windows on any workspace, on workspace 1."""
        subprocess.run(["pkill", "-x", "TextEdit"])
        subprocess.run(["defaults", "write", "com.apple.TextEdit", "NSQuitAlwaysKeepsWindows", "-bool", "false"])
        subprocess.run(["defaults", "write", "com.apple.TextEdit", "ApplePersistenceIgnoreState", "-bool", "true"])
        subprocess.run(["rm", "-rf", DOCS])
        os.makedirs(DOCS)
        for n in range(1, len(self.state()["displays"][0]["workspaces"]) + 1):
            self.cli("workspace", n)
            time.sleep(0.5)
            for w in self.visible(self.state()): self.cli("debug", "ax-close", w["id"])
        self.cli("workspace", 1)
        time.sleep(1)
        for _ in range(MIN_WINDOWS): self.open_doc(self.state()); time.sleep(1.5)
        time.sleep(1)

    def settle(self):
        """Waits 1.5 s for the state to settle, polling the display's Space; the state after, and the Spaces seen."""
        seen = []
        for _ in range(6):
            time.sleep(0.25)
            s = self.state()
            if s is None: return None, seen
            space = s["displays"][0]["current-space"]
            if not seen or seen[-1] != space: seen.append(space)
        return s, seen

    def fuzz(self, steps):
        self.setup()
        s = self.state()
        weights, actions = zip(*(self.SWITCHING_ACTIONS if self.switching else self.ACTIONS))
        for step in range(1, steps + 1):
            start = len(self.history)
            action = self.rng.choices(actions, weights)[0]
            while not action(self, s):
                start, action = len(self.history), self.rng.choices(actions, weights)[0]
            print(f"{step:4} " + "; ".join(self.history[start:]), flush=True)
            stuck = self.wait_for_animations()
            after = self.state()
            idle, spaces = self.settle()
            if after is None or idle is None:
                self.found["app-died"] = 1
                print(f"\n=== VIOLATION seed {self.seed} step {step}: the app is gone (no socket)")
                print("  last actions:\n    " + "\n    ".join(self.history[-10:]))
                break
            checked = self.check(idle)
            late = self.check(after).keys() - checked.keys()
            if late: print("       settled late: " + ", ".join(f"{k} {i}" for k, i in sorted(late, key=str)))
            checked.update(self.shifts(after, idle))
            if stuck: checked[("i-animating", 0)] = f"windows {stuck} were still animating 3 s after the action"
            if len(spaces) >= 3:
                checked[("h-loop", 0)] = f"the display kept changing Space while idle: {' -> '.join(map(str, spaces))}"
            if action in self.STAYS and after["displays"][0]["current-space"] != s["displays"][0]["current-space"]:
                checked[("g-bounce", action.__name__)] = f"{action.__name__} moved the display to Space {after['displays'][0]['current-space']}"
            if self.landing: self.note_landing(idle)
            self.report(step, checked, s, idle)
            s = idle
        for how in sorted({l[0] for l in self.landings}):
            ls = [l for l in self.landings if l[0] == how]
            print(f"empty workspace by {how}: {len(ls)}, stayed {sum(w == f'workspace {n}' for _, n, w in ls)}")
        print(f"animations seen in {self.animated} of {step} steps")
        print(f"\nseed {self.seed}: {step} steps, " + (", ".join(f"{k} x{n}" for k, n in sorted(self.found.items())) or "no violations"))
        return 1 if self.found else 0

    def wait_for_animations(self):
        """Waits at least 0.8 s, and until kex animates nothing, polling. The windows still animating after 3 s."""
        start, seen = time.time(), False
        while time.time() - start < 3:
            s = self.state()
            animating = s["animating"] if s else []
            seen = seen or bool(animating)
            if not animating and time.time() - start >= 0.8:
                self.animated += seen
                return []
            time.sleep(0.05)
        self.animated += 1
        return animating

    def note_landing(self, s):
        how, n, space = self.landing
        d, self.landing = s["displays"][0], None
        where = f"workspace {d['workspaces'].index(d['current-space']) + 1}" if d["current-space"] in d["workspaces"] else "a full-screen Space"
        self.landings.append((how, n, where))
        print(f"       empty workspace {n} by {how}: " + ("stayed" if d["current-space"] == space else f"now on {where}"))


def close(a, b, within=2):
    return all(abs(x - y) <= within for x, y in zip([a[0], a[1], a[0] + a[2], a[1] + a[3]], [b[0], b[1], b[0] + b[2], b[1] + b[3]]))


def overlap(a, b, by=2):
    return min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]) > by and min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]) > by


def summary(s):
    """The current Spaces, focus, trees by Space, and the live and expected frames of tiled windows on screen."""
    current = {d["current-space"] for d in s["displays"]}
    live = {w["id"]: w["live-frame"] for w in s["windows"]}
    shown = [t for t in s["trees"] if t["space"] in current]
    return {"current": [d["current-space"] for d in s["displays"]], "focused": s["focused"],
            "trees": {t["space"]: (t["mode"], t["windows"], t["fullscreen"]) for t in s["trees"] if t["windows"]},
            "frames": {i: live[i] for t in shown for i in t["windows"] if live.get(i)},
            "expected": {i: t["expected"][str(i)] for t in shown for i in t["windows"]}}


def diff(a, b):
    sa, sb = summary(a), summary(b)
    lines = [f"{k}: {sa[k]} -> {sb[k]}" for k in ("current", "focused") if sa[k] != sb[k]]
    for space in sorted(sa["trees"].keys() | sb["trees"].keys()):
        if sa["trees"].get(space) != sb["trees"].get(space):
            lines.append(f"tree {space}: {sa['trees'].get(space)} -> {sb['trees'].get(space)}")
    for id in sorted(sa["frames"].keys() | sb["frames"].keys()):
        fa, fb = sa["frames"].get(id), sb["frames"].get(id)
        if fa is None or fb is None or not close(fa, fb): lines.append(f"frame {id}: {fa} -> {fb}")
    return lines


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--steps", type=int, default=150)
    parser.add_argument("--kex", default=os.path.expanduser("~/kex-fuzz"))
    parser.add_argument("--switching", action="store_true", help="quits, closes, activations and Space switches dominate")
    args = parser.parse_args()
    sys.exit(Fuzzer(args.seed, args.kex, args.switching).fuzz(args.steps))
