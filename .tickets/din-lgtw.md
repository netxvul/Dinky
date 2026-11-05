---
id: din-lgtw
status: closed
deps: []
links: []
created: 2026-09-26T20:55:18Z
type: bug
priority: 3
assignee: Mikkel Malmberg
tags: [layout]
---
# auto containers resolve their axis from two different rectangles

Workspace.axisOfContainer and the layout use frames after minimum sizes; resize (KexLayout/Commands.swift) and edgeWindow (Workspace.swift) use root.rect(at:) from ratios alone. An auto container near square with a minimum-size window can read as horizontal in one and vertical in the other. Found by the refactor pass on 26 September.

## Acceptance Criteria

One rectangle source for auto resolution, with a test for the near-square-with-minimum case.

