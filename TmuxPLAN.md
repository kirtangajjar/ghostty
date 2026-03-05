# Full Tmux Integration Plan

## Scope
Deliver a production-ready tmux backend for Ghostty (`terminal-backend=tmux`) with complete lifecycle, input/output, state sync, and test coverage.

## Current State (as of 2026-03-05)
- Backend selection is wired in [`src/Surface.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/Surface.zig).
- `tmux` viewer/action plumbing exists in [`src/termio/stream_handler.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/termio/stream_handler.zig), [`src/apprt/surface.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/apprt/surface.zig), and [`src/terminal/tmux/viewer.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/terminal/tmux/viewer.zig).
- Control key formatter exists in [`src/terminal/tmux/control.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/terminal/tmux/control.zig).
- `Tmux` backend implementation is still a stub in [`src/termio/Tmux.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/termio/Tmux.zig).

## Modular Chunks

### Chunk 1: Tmux Transport + Lifecycle Core
- Implement `Tmux.init/threadEnter/threadExit/deinit` to establish and tear down tmux control-mode transport.
- Store transport handles in `Tmux.ThreadData` (read/write stream, process/socket state, watcher completions).
- Ensure clean shutdown semantics match `Exec` backend quality (no orphan read loops, no fd leaks).
- Acceptance:
  - `terminal-backend=tmux` opens a live session and receives control output.
  - Exit/stop path is deterministic and leak-free.

### Chunk 2: Output Ingestion and Viewer Drive
- Feed tmux control bytes into parser/viewer pipeline and map viewer actions to terminal/surface updates.
- Make session attach/startup flow robust for startup ordering races (`%begin/%end` vs `%session-changed` timing).
- Acceptance:
  - Initial window/pane graph appears without manual refresh.
  - Pane output continuously updates terminal state.

### Chunk 3: Input Path End-to-End
- Implement `Tmux.write` and `Tmux.queueWrite` so keyboard data is converted to tmux `%key` writes.
- Track current target pane and route input deterministically.
- Use `terminal.tmux.control.write(...)` as the canonical formatter.
- Acceptance:
  - Typing in Ghostty reaches the active tmux pane.
  - Input still works after window/pane switches.

### Chunk 4: Active Pane/Window Semantics
- Extend viewer state to track active pane changes from `%window-pane-changed`.
- Emit precise actions for active-pane transitions, and consume them in termio/surface.
- Acceptance:
  - Focused tmux pane in Ghostty always matches tmux server active pane.
  - No stale pane routing after layout/session changes.

### Chunk 5: Resize, Focus, and Terminal Behavior Parity
- Implement backend-specific handling for `resize` and `focusGained`.
- Validate terminal mode interactions (focus events, synchronized output expectations, cursor behavior) under tmux backend.
- Acceptance:
  - Resizes correctly propagate to tmux and redraw without corruption.
  - Focus gain/loss behavior matches user-visible behavior of exec backend where applicable.

### Chunk 6: Config Surface for Tmux Backend
- Expand `Tmux.Config` with explicit options (session target, socket/path, attach/create policy, startup command).
- Add config validation and docs in `Config.zig` and user-facing config docs.
- Acceptance:
  - Misconfigurations fail fast with actionable errors.
  - Supported tmux backend options are documented and testable.

### Chunk 7: Render/Event Coalescing
- Avoid unconditional full renders for every `.windows` event.
- Add semantic diffing/coalescing for `tmux_windows_changed` and pane-dirty bursts.
- Acceptance:
  - Window metadata churn does not cause unnecessary redraw storms.
  - UI remains responsive under high tmux event rates.

### Chunk 8: Test Matrix and Regression Harness
- Add integration tests for:
  - backend lifecycle (start/stop/reconnect),
  - key write path (`Surface -> backend.write -> tmux control write`),
  - viewer event chain (`windows/pane_dirty` -> surface messages -> render queue),
  - active pane transitions.
- Acceptance:
  - Failing any link in the tmux chain is caught by tests.
  - CI has deterministic tmux integration coverage for new paths.

## Proposed Execution Order
1. Chunk 1
2. Chunk 2
3. Chunk 3
4. Chunk 4
5. Chunk 5
6. Chunk 6
7. Chunk 7
8. Chunk 8

## Definition of Done
- `terminal-backend=tmux` is usable for interactive daily work.
- Key input/output, pane focus, and resize all behave correctly.
- No stub code remains in `src/termio/Tmux.zig`.
- Integration tests guard all new behavior and pass in CI.
