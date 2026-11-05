---
id: din-19v3
status: closed
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: task
priority: 0
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, spike]
---
# Spike: create Spaces with SLSBridgedSpaceCreateOperation

Try SLSBridgedSpaceCreateOperation (initWithOptions:values:) through the bridged dispatcher to add a user Space to a display, then verify Mission Control shows it, Dock stays coherent, and it survives a Dock restart. If it fails, document it; the fallback is asking the user to create desktops.

## Acceptance Criteria

A written result in RESULTS.md: works or not, on which build, with the exact call. If it works, a kex function that creates one Space on a given display.


## Notes

**2026-09-25T10:16:38Z**

Works on 26A5416b (VM): SLSBridgedSpaceCreateOperation initWithOptions:0 values:@{type:0, 'Display Identifier':uuid} sent through the non-exported sync dispatcher __ZL54_SLSPerformSynchronousBridgedWindowManagementOperation... returns a SpaceIDResult. Shows in SLSCopyManagedDisplaySpaces and in Mission Control right away, usable with move and switch, and survives killall Dock. Needs AppKit loaded in the process (a bare Foundation process gets nil). Exported SLSSpaceCreate returns 0. Destroy (bridged op or SLSSpaceDestroy) does nothing from a client. Host with SIP on not tested. Full write-up in RESULTS.md 'Space creation spike'. kex_create_space in spaces.m is the real function.
