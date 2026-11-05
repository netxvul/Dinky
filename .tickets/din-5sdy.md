---
id: din-5sdy
status: closed
deps: [din-g6bk]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, cli]
---
# CLI over unix socket

kex <command> from a shell sends the command to the running app over a unix socket in the user's temp dir and prints the reply. Queries too: kex list-windows, list-workspaces. The spike's subcommands are replaced by this.

## Acceptance Criteria

kex workspace 2 switches from a terminal. kex list-windows prints windows with workspace and display. Running without the app gives a clear error.


## Notes

**2026-09-25T10:38:43Z**

Socket: $TMPDIR/kex.sock (NSTemporaryDirectory), BSD socket + DispatchSource. One request per connection: client writes '<command>\n', app replies 'ok\n' or 'error\n' + text and closes. CLI parses locally first, so bad commands fail without the app. Queries list-windows/list-workspaces/list-displays print ' | '-separated lines. 'kex app' exits if another app answers on the socket; stale socket file replaced at start. SIGPIPE ignored (a client hanging up killed the app with 141). Tested on host: list-*, reload-config (ok and error), mode, enable, unknown command, app-not-running error. NOT verified: 'kex workspace 2' switching — not run on the host by instruction, and the Tart VM refused ssh (port 22) today. Spike move/focus still work when given a numeric window id.

**2026-09-25T10:41:37Z**

CLI and socket done and tested on the host with safe commands; 'kex workspace 2' over the socket to be verified in the VM by din-mlu6. Closing.
