# Tmux Integration Review (Clean Branch)

Branch reviewed: `codex/tmux-full-integration-clean`  
Base: `ghostty/main`  
Date: 2026-03-05

## Findings

1. **[P1] `terminal-backend=tmux` is non-functional because backend lifecycle is still stubbed**
   - Files: [`src/termio/Tmux.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/termio/Tmux.zig)
   - `init`, `threadEnter`, `queueWrite`, and `write` are placeholders and do not establish transport or send data.
   - Impact: selecting tmux backend bypasses PTY but does not replace it with a working tmux transport.
   - Improvement: implement full backend transport/lifecycle with proper thread-local state and shutdown semantics.

2. **[P1] Key input path is not wired end-to-end for tmux pane writes**
   - Files: [`src/Surface.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/Surface.zig), [`src/termio/Tmux.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/termio/Tmux.zig), [`src/terminal/tmux/control.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/terminal/tmux/control.zig)
   - Surface writes directly via `backend.write(...)`; `control.write(...)` formatter exists, but tmux backend `write(...)` does nothing.
   - Impact: keystrokes do not reach tmux panes even though formatter/tests exist.
   - Improvement: route `Surface` key data through tmux write implementation that targets the correct pane using `%key`.

3. **[P2] Active pane tracking is missing, so pane-targeted input cannot be correct**
   - File: [`src/terminal/tmux/viewer.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/terminal/tmux/viewer.zig)
   - `%window-pane-changed` is explicitly ignored and TODO notes mention active-pane tracking.
   - Impact: even after write plumbing, input routing can drift from tmux active pane after focus/layout changes.
   - Improvement: track active pane in viewer state and emit dedicated action(s) consumed by termio/backend.

4. **[P2] Window-change notifications currently over-render**
   - Files: [`src/termio/stream_handler.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/termio/stream_handler.zig), [`src/Surface.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/Surface.zig)
   - Every `.windows` action emits `.tmux_windows_changed`, and `Surface` unconditionally queues render.
   - Impact: frequent list-window refreshes can cause avoidable render pressure.
   - Improvement: coalesce/diff window updates before scheduling full redraw.

5. **[P3] Missing integration tests for backend selection + tmux message chain**
   - Files: [`src/Surface.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/Surface.zig), [`src/termio/Tmux.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/termio/Tmux.zig), [`src/termio/stream_handler.zig`](/Users/kirtangajjar/code/opensource/ghostty-tmux-clean/src/termio/stream_handler.zig)
   - Existing tests cover control parser/formatter and many viewer behaviors, but not backend `.tmux` runtime path.
   - Impact: future changes can regress tmux backend bring-up without signal.
   - Improvement: add integration tests covering `terminal-backend=tmux` initialization, writes, and surface render trigger chain.
