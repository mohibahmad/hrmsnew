**Source visual truth**

- Path: `/var/folders/l0/450pll6n1wgd9sz7gy9j3kjc0000gn/T/codex-clipboard-524e264d-9b1d-4f65-997e-a2d24c45a6eb.png`
- Pixels: 292 x 406
- State: Documents screen with an uploaded CV preview.

**Implementation evidence**

- Screenshot: unavailable because the user requested that the app not be run.
- Viewport, CSS size, and density normalization: unavailable.
- Primary interactions and console errors: not browser-tested.

**Full-view comparison**

- Blocked without a rendered implementation screenshot.

**Focused-region comparison**

- Blocked without a rendered uploaded-CV state.

**Findings**

- The supplied Flutter log showed that `LayoutBuilder` was nested under `IntrinsicHeight`, which does not support intrinsic sizing. The responsive builder was removed and the existing Documents upload-state 24 px inset was reused.
- The CV now uses an inset white paper frame on the grey canvas and `BoxFit.contain` for image and PDF previews.

**Comparison history**

- Earlier P0: Documents screen crashed while calculating intrinsic height.
- Fix: removed `LayoutBuilder` from the intrinsic-height subtree and retained fixed inset spacing.
- Post-fix visual evidence: unavailable by user request.

**Final result**

final result: blocked
