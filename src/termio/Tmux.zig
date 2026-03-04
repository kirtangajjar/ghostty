//! Tmux implements the logic for connecting to a tmux session.
//! This is a stub implementation for future tmux integration.
const Tmux = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const termio = @import("../termio.zig");

const log = std.log.scoped(.io_tmux);

/// Initialize the tmux state. This will NOT start it, this only sets
/// up the internal state necessary to start it later.
pub fn init(
    alloc: Allocator,
    cfg: Config,
) !Tmux {
    _ = alloc;
    _ = cfg;
    log.debug("Tmux.init called (stub)", .{});
    return .{};
}

pub fn deinit(self: *Tmux) void {
    _ = self;
    log.debug("Tmux.deinit called (stub)", .{});
}

/// Call to initialize the terminal state as necessary for this backend.
/// This is called before any termio begins.
pub fn initTerminal(self: *Tmux, term: *terminal.Terminal) void {
    _ = self;
    _ = term;
    log.debug("Tmux.initTerminal called (stub)", .{});
}

pub fn threadEnter(
    self: *Tmux,
    alloc: Allocator,
    io: *termio.Termio,
    td: *termio.Termio.ThreadData,
) !void {
    _ = self;
    _ = alloc;
    _ = io;
    _ = td;
    log.debug("Tmux.threadEnter called (stub)", .{});
    // TODO: Implement tmux session attachment
}

pub fn threadExit(self: *Tmux, td: *termio.Termio.ThreadData) void {
    _ = self;
    _ = td;
    log.debug("Tmux.threadExit called (stub)", .{});
}

pub fn focusGained(
    self: *Tmux,
    td: *termio.Termio.ThreadData,
    focused: bool,
) !void {
    _ = self;
    _ = td;
    _ = focused;
    log.debug("Tmux.focusGained called (stub)", .{});
}

pub fn resize(
    self: *Tmux,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,
) !void {
    _ = self;
    _ = grid_size;
    _ = screen_size;
    log.debug("Tmux.resize called (stub)", .{});
}

pub fn queueWrite(
    self: *Tmux,
    alloc: Allocator,
    td: *termio.Termio.ThreadData,
    data: []const u8,
    linefeed: bool,
) !void {
    _ = self;
    _ = alloc;
    _ = td;
    _ = data;
    _ = linefeed;
    log.debug("Tmux.queueWrite called (stub)", .{});
}

pub fn childExitedAbnormally(
    self: *Tmux,
    gpa: Allocator,
    t: *terminal.Terminal,
    exit_code: u32,
    runtime_ms: u64,
) !void {
    _ = self;
    _ = gpa;
    _ = t;
    _ = exit_code;
    _ = runtime_ms;
    log.debug("Tmux.childExitedAbnormally called (stub)", .{});
}

/// Configuration for the tmux backend.
pub const Config = struct {
    // TODO: Add tmux-specific configuration options
    // e.g., session_name, socket_path, etc.
};

/// The thread local data for the tmux implementation.
pub const ThreadData = struct {
    // TODO: Add tmux-specific thread data
    // e.g., connection state, buffers, etc.

    pub fn deinit(self: *ThreadData, alloc: Allocator) void {
        _ = self;
        _ = alloc;
        // TODO: Cleanup tmux thread data
    }

    pub fn changeConfig(self: *ThreadData, config: *termio.DerivedConfig) void {
        _ = self;
        _ = config;
        // TODO: Handle configuration changes
    }
};
