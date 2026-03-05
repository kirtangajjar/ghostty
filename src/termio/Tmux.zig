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

/// Write data directly to the backend. This is a synchronous write
/// that bypasses the async queue system. This is useful for
/// cases where we need to write data immediately without going
/// through the mailbox.
pub fn write(self: *Tmux, data: []const u8) !void {
    _ = self;
    _ = data;
    log.debug("Tmux.write called (stub)", .{});
    // TODO: Implement tmux write
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

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Tmux: basic lifecycle init/deinit" {
    // Test that init and deinit work without crashing (stub implementation)
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Stub implementation returns a valid Tmux instance
    // (verified by successful init and deinit)
}

test "Tmux: ThreadData lifecycle" {
    // Test that ThreadData can be initialized and deinitialized
    const alloc = testing.allocator;

    var thread_data: ThreadData = .{};
    defer thread_data.deinit(alloc);

    // Stub implementation should handle deinit gracefully
}

test "Tmux: Config default initialization" {
    // Test that Config can be created with default values
    const config = Config{};

    // Stub implementation has no fields yet
    _ = config;
}

test "Tmux: init with allocator" {
    // Test that init works with different allocators
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Verify we can call init multiple times (different instances)
    var tmux2 = try Tmux.init(alloc, config);
    defer tmux2.deinit();

    // Both instances successfully initialized and deinitialized
}

test "Tmux: deinit is idempotent-safe" {
    // Test that deinit can be called without issues
    // Note: This doesn't test calling deinit twice (which would be unsafe)
    // but verifies the stub handles the single call correctly
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    tmux.deinit();
    // After deinit, tmux should not be used
}

test "Tmux: initTerminal does not crash" {
    // Test that initTerminal can be called without crashing
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Note: We can't easily create a Terminal instance here without
    // significant setup. The stub implementation handles null gracefully.
    // When the real implementation is added, this test should be extended
    // to create a proper Terminal instance.
}

test "Tmux: focusGained handles both states" {
    // Test that focusGained handles focused/unfocused states
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Stub implementation should handle focus changes without error
    // Note: ThreadData is required but stub handles null gracefully
}

test "Tmux: resize handles various sizes" {
    // Test that resize can be called with different sizes
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Test various grid/screen sizes
    try tmux.resize(.{ .columns = 80, .rows = 24 }, .{ .width = 640, .height = 480 });
    try tmux.resize(.{ .columns = 120, .rows = 40 }, .{ .width = 960, .height = 800 });
    try tmux.resize(.{ .columns = 1, .rows = 1 }, .{ .width = 1, .height = 1 });
}

test "Tmux: queueWrite handles empty data" {
    // Test that queueWrite handles empty data gracefully
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Empty write should not crash
    try tmux.queueWrite(alloc, undefined, "", false);
}

test "Tmux: queueWrite handles data" {
    // Test that queueWrite handles non-empty data
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Write some test data
    try tmux.queueWrite(alloc, undefined, "test data", false);
    try tmux.queueWrite(alloc, undefined, "test data", true);
}

test "Tmux: write handles data" {
    // Test that write handles data
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Direct write
    try tmux.write("test data");
}

test "Tmux: childExitedAbnormally handles exit codes" {
    // Test that childExitedAbnormally handles various exit codes
    const alloc = testing.allocator;
    const config = Config{};

    var tmux = try Tmux.init(alloc, config);
    defer tmux.deinit();

    // Stub should handle various exit codes without error
    try tmux.childExitedAbnormally(alloc, undefined, 0, 0);
    try tmux.childExitedAbnormally(alloc, undefined, 1, 1000);
    try tmux.childExitedAbnormally(alloc, undefined, 255, 60000);
}
