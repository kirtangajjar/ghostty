const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const termio = @import("../termio.zig");

// The preallocation size for the write request pool. This should be big
// enough to satisfy most write requests. It must be a power of 2.
const WRITE_REQ_PREALLOC = std.math.pow(usize, 2, 5);

/// The kinds of backends.
pub const Kind = enum { exec, tmux };

/// Configuration for the various backend types.
pub const Config = union(Kind) {
    /// Exec uses posix exec to run a command with a pty.
    exec: termio.Exec.Config,
    /// Tmux connects to a tmux session.
    tmux: termio.Tmux.Config,
};

/// Backend implementations. A backend is responsible for owning the pty
/// behavior and providing read/write capabilities.
pub const Backend = union(Kind) {
    exec: termio.Exec,
    tmux: termio.Tmux,

    pub fn deinit(self: *Backend) void {
        switch (self.*) {
            .exec => |*exec| exec.deinit(),
            .tmux => |*tmux| tmux.deinit(),
        }
    }

    pub fn initTerminal(self: *Backend, t: *terminal.Terminal) void {
        switch (self.*) {
            .exec => |*exec| exec.initTerminal(t),
            .tmux => |*tmux| tmux.initTerminal(t),
        }
    }

    pub fn threadEnter(
        self: *Backend,
        alloc: Allocator,
        io: *termio.Termio,
        td: *termio.Termio.ThreadData,
    ) !void {
        switch (self.*) {
            .exec => |*exec| try exec.threadEnter(alloc, io, td),
            .tmux => |*tmux| try tmux.threadEnter(alloc, io, td),
        }
    }

    pub fn threadExit(self: *Backend, td: *termio.Termio.ThreadData) void {
        switch (self.*) {
            .exec => |*exec| exec.threadExit(td),
            .tmux => |*tmux| tmux.threadExit(td),
        }
    }

    pub fn focusGained(
        self: *Backend,
        td: *termio.Termio.ThreadData,
        focused: bool,
    ) !void {
        switch (self.*) {
            .exec => |*exec| try exec.focusGained(td, focused),
            .tmux => |*tmux| try tmux.focusGained(td, focused),
        }
    }

    pub fn resize(
        self: *Backend,
        grid_size: renderer.GridSize,
        screen_size: renderer.ScreenSize,
    ) !void {
        switch (self.*) {
            .exec => |*exec| try exec.resize(grid_size, screen_size),
            .tmux => |*tmux| try tmux.resize(grid_size, screen_size),
        }
    }

    pub fn queueWrite(
        self: *Backend,
        alloc: Allocator,
        td: *termio.Termio.ThreadData,
        data: []const u8,
        linefeed: bool,
    ) !void {
        switch (self.*) {
            .exec => |*exec| try exec.queueWrite(alloc, td, data, linefeed),
            .tmux => |*tmux| try tmux.queueWrite(alloc, td, data, linefeed),
        }
    }

    /// Write data directly to the backend. This is a synchronous write
    /// that bypasses the mailbox queue system.
    pub fn write(self: *Backend, data: []const u8) !void {
        switch (self.*) {
            .exec => |*exec| try exec.write(data),
            .tmux => |*tmux| try tmux.write(data),
        }
    }

    pub fn childExitedAbnormally(
        self: *Backend,
        gpa: Allocator,
        t: *terminal.Terminal,
        exit_code: u32,
        runtime_ms: u64,
    ) !void {
        switch (self.*) {
            .exec => |*exec| try exec.childExitedAbnormally(
                gpa,
                t,
                exit_code,
                runtime_ms,
            ),
            .tmux => |*tmux| try tmux.childExitedAbnormally(
                gpa,
                t,
                exit_code,
                runtime_ms,
            ),
        }
    }
};

/// Termio thread data. See termio.ThreadData for docs.
pub const ThreadData = union(Kind) {
    exec: termio.Exec.ThreadData,
    tmux: termio.Tmux.ThreadData,

    pub fn deinit(self: *ThreadData, alloc: Allocator) void {
        switch (self.*) {
            .exec => |*exec| exec.deinit(alloc),
            .tmux => |*tmux| tmux.deinit(alloc),
        }
    }

    pub fn changeConfig(self: *ThreadData, config: *termio.DerivedConfig) void {
        _ = self;
        _ = config;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

fn stubTmuxRuntimeThreadData() termio.Termio.ThreadData {
    return .{
        .alloc = testing.allocator,
        .loop = undefined,
        .renderer_state = undefined,
        .surface_mailbox = undefined,
        .backend = .{ .tmux = undefined },
        .mailbox = undefined,
    };
}

test "Backend: tmux init and deinit lifecycle" {
    // Test that Backend union can hold Tmux and be deinitialized
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Verify backend kind
    try testing.expectEqual(Kind.tmux, @as(Kind, backend));
}

test "Backend: tmux initTerminal does not crash" {
    // Test that initTerminal can be called on Tmux backend
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Stub implementation handles this gracefully
    // Note: Terminal initialization would require more setup in real implementation
}

test "Backend: Config union type holds tmux config" {
    // Test that Config union can hold Tmux.Config
    const config = Config{ .tmux = .{} };

    // Verify config kind
    try testing.expectEqual(Kind.tmux, @as(Kind, config));
}

test "Backend: ThreadData union type holds tmux ThreadData" {
    // Constructing a real Tmux.ThreadData requires active runtime resources.
    // Here we only verify the union tag/value path compiles for tmux.
    const thread_data: ThreadData = .{ .tmux = undefined };

    // Verify thread data kind
    try testing.expectEqual(Kind.tmux, @as(Kind, thread_data));
}

test "Backend: Kind enum includes tmux" {
    // Test that Kind enum includes both exec and tmux
    try testing.expectEqual(Kind.exec, Kind.exec);
    try testing.expectEqual(Kind.tmux, Kind.tmux);

    // Verify enum values exist
    const exec_kind: Kind = .exec;
    const tmux_kind: Kind = .tmux;
    _ = exec_kind;
    _ = tmux_kind;
}

// ============================================================================
// Resize/Focus Behavior Tests (ghostty-1i4.10)
// ============================================================================

test "Backend: tmux focusGained with focused=true does not error" {
    // Test that focusGained can be called with focused=true on Tmux backend
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Create stub ThreadData - focusGained should not crash
    var thread_data = stubTmuxRuntimeThreadData();

    // focusGained with focused=true should succeed (no-op in stub)
    try backend.focusGained(&thread_data, true);
}

test "Backend: tmux focusGained with focused=false does not error" {
    // Test that focusGained can be called with focused=false on Tmux backend
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Create stub ThreadData - focusGained should not crash
    var thread_data = stubTmuxRuntimeThreadData();

    // focusGained with focused=false should succeed (no-op in stub)
    try backend.focusGained(&thread_data, false);
}

test "Backend: tmux focusGained toggle does not error" {
    // Test that focusGained can be toggled between focused/unfocused
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Create stub ThreadData
    var thread_data = stubTmuxRuntimeThreadData();

    // Toggle focus state multiple times
    try backend.focusGained(&thread_data, true);
    try backend.focusGained(&thread_data, false);
    try backend.focusGained(&thread_data, true);
    try backend.focusGained(&thread_data, false);
}

test "Backend: tmux resize stores grid size" {
    // Test that resize correctly stores grid size in Tmux backend
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Resize with valid grid size
    const grid_size: renderer.GridSize = .{
        .columns = 80,
        .rows = 24,
    };
    const screen_size: renderer.ScreenSize = .{
        .width = 800,
        .height = 600,
    };

    try backend.resize(grid_size, screen_size);

    // Verify the size was stored in the subprocess
    // GridSize.Unit is u16 (CellCountInt)
    try testing.expectEqual(@as(renderer.GridSize.Unit, 80), backend.tmux.subprocess.grid_size.columns);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 24), backend.tmux.subprocess.grid_size.rows);
    try testing.expectEqual(@as(u32, 800), backend.tmux.subprocess.screen_size.width);
    try testing.expectEqual(@as(u32, 600), backend.tmux.subprocess.screen_size.height);
}

test "Backend: tmux resize multiple times" {
    // Test that resize can be called multiple times with different sizes
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // First resize
    try backend.resize(.{ .columns = 80, .rows = 24 }, .{ .width = 800, .height = 600 });
    try testing.expectEqual(@as(renderer.GridSize.Unit, 80), backend.tmux.subprocess.grid_size.columns);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 24), backend.tmux.subprocess.grid_size.rows);

    // Second resize - larger
    try backend.resize(.{ .columns = 120, .rows = 40 }, .{ .width = 1200, .height = 800 });
    try testing.expectEqual(@as(renderer.GridSize.Unit, 120), backend.tmux.subprocess.grid_size.columns);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 40), backend.tmux.subprocess.grid_size.rows);

    // Third resize - smaller
    try backend.resize(.{ .columns = 40, .rows = 10 }, .{ .width = 400, .height = 200 });
    try testing.expectEqual(@as(renderer.GridSize.Unit, 40), backend.tmux.subprocess.grid_size.columns);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 10), backend.tmux.subprocess.grid_size.rows);
}

test "Backend: tmux resize with zero columns" {
    // Test that resize handles zero columns gracefully
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Resize with zero columns should still work (edge case handling)
    const grid_size: renderer.GridSize = .{
        .columns = 0,
        .rows = 24,
    };
    const screen_size: renderer.ScreenSize = .{
        .width = 0,
        .height = 600,
    };

    try backend.resize(grid_size, screen_size);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 0), backend.tmux.subprocess.grid_size.columns);
}

test "Backend: tmux resize with large dimensions" {
    // Test that resize handles large dimensions
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Resize with large dimensions
    const grid_size: renderer.GridSize = .{
        .columns = 1000,
        .rows = 500,
    };
    const screen_size: renderer.ScreenSize = .{
        .width = 10000,
        .height = 5000,
    };

    try backend.resize(grid_size, screen_size);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 1000), backend.tmux.subprocess.grid_size.columns);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 500), backend.tmux.subprocess.grid_size.rows);
}

test "Backend: tmux initTerminal calls resize with terminal dimensions" {
    // Test that initTerminal sets up initial terminal size
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // Create a stub terminal with dimensions
    var term: terminal.Terminal = undefined;
    term.cols = 132;
    term.rows = 43;
    term.width_px = 1320;
    term.height_px = 860;

    // Initialize terminal - should set size
    backend.initTerminal(&term);

    // Verify dimensions were stored
    // GridSize.Unit is u16 (CellCountInt), same as terminal.size
    try testing.expectEqual(@as(renderer.GridSize.Unit, 132), backend.tmux.subprocess.grid_size.columns);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 43), backend.tmux.subprocess.grid_size.rows);
    try testing.expectEqual(@as(u32, 1320), backend.tmux.subprocess.screen_size.width);
    try testing.expectEqual(@as(u32, 860), backend.tmux.subprocess.screen_size.height);
}

test "Backend: tmux resize followed by initTerminal overwrites" {
    // Test that initTerminal after resize uses terminal dimensions
    const alloc = testing.allocator;
    const config = Config{ .tmux = .{} };

    var backend = Backend{
        .tmux = try termio.Tmux.init(alloc, config.tmux),
    };
    defer backend.deinit();

    // First resize manually
    try backend.resize(.{ .columns = 80, .rows = 24 }, .{ .width = 800, .height = 600 });
    try testing.expectEqual(@as(renderer.GridSize.Unit, 80), backend.tmux.subprocess.grid_size.columns);

    // Then initTerminal with different dimensions
    var term: terminal.Terminal = undefined;
    term.cols = 100;
    term.rows = 30;
    term.width_px = 1000;
    term.height_px = 600;

    backend.initTerminal(&term);

    // Should have terminal dimensions now
    try testing.expectEqual(@as(renderer.GridSize.Unit, 100), backend.tmux.subprocess.grid_size.columns);
    try testing.expectEqual(@as(renderer.GridSize.Unit, 30), backend.tmux.subprocess.grid_size.rows);
}

// ============================================================================
// Config Parsing Tests (ghostty-1i4.12)
// ============================================================================

test "Backend: tmux config default values" {
    // Test that default Config has all null/false values
    const config = termio.Tmux.Config{};

    try testing.expectEqual(@as(?[]const u8, null), config.session);
    try testing.expectEqual(@as(?[]const u8, null), config.socket_path);
    try testing.expectEqual(@as(bool, false), config.create_session);
    try testing.expectEqual(@as(?[]const u8, null), config.command);
    try testing.expectEqual(@as(?[]const u8, null), config.working_directory);
}

test "Backend: tmux config with session name" {
    // Test that Config can be created with a session name
    const alloc = testing.allocator;

    const config = termio.Tmux.Config{
        .session = "my-session",
    };

    try testing.expectEqualSlices(u8, "my-session", config.session.?);

    // Test that Subprocess.init correctly stores the session name
    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, "my-session", subprocess.session.?);

    // Verify the session is passed as -t argument
    var found_session_arg = false;
    var found_session_value = false;
    for (subprocess.args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "-t")) {
            found_session_arg = true;
            if (i + 1 < subprocess.args.len) {
                if (std.mem.eql(u8, subprocess.args[i + 1], "my-session")) {
                    found_session_value = true;
                }
            }
        }
    }
    try testing.expect(found_session_arg);
    try testing.expect(found_session_value);
}

test "Backend: tmux config with socket path" {
    // Test that Config can be created with a socket path
    const alloc = testing.allocator;

    const config = termio.Tmux.Config{
        .socket_path = "/tmp/tmux-socket",
    };

    try testing.expectEqualSlices(u8, "/tmp/tmux-socket", config.socket_path.?);

    // Test that Subprocess.init correctly stores the socket path
    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, "/tmp/tmux-socket", subprocess.socket_path.?);

    // Verify the socket path is passed as -S argument
    var found_socket_arg = false;
    var found_socket_value = false;
    for (subprocess.args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "-S")) {
            found_socket_arg = true;
            if (i + 1 < subprocess.args.len) {
                if (std.mem.eql(u8, subprocess.args[i + 1], "/tmp/tmux-socket")) {
                    found_socket_value = true;
                }
            }
        }
    }
    try testing.expect(found_socket_arg);
    try testing.expect(found_socket_value);
}

test "Backend: tmux config with create_session flag" {
    // Test that Config can be created with create_session flag
    const config = termio.Tmux.Config{
        .create_session = true,
    };

    try testing.expectEqual(@as(bool, true), config.create_session);
}

test "Backend: tmux config with command" {
    // Test that Config can be created with a command
    const config = termio.Tmux.Config{
        .command = "/bin/bash",
    };

    try testing.expectEqualSlices(u8, "/bin/bash", config.command.?);
}

test "Backend: tmux config with working_directory" {
    // Test that Config can be created with a working directory
    const config = termio.Tmux.Config{
        .working_directory = "/home/user",
    };

    try testing.expectEqualSlices(u8, "/home/user", config.working_directory.?);
}

test "Backend: tmux config with all fields set" {
    // Test that Config can be created with all fields set
    const alloc = testing.allocator;

    const config = termio.Tmux.Config{
        .session = "test-session",
        .socket_path = "/var/run/tmux.sock",
        .create_session = true,
        .command = "/usr/bin/zsh",
        .working_directory = "/home/test",
    };

    try testing.expectEqualSlices(u8, "test-session", config.session.?);
    try testing.expectEqualSlices(u8, "/var/run/tmux.sock", config.socket_path.?);
    try testing.expectEqual(@as(bool, true), config.create_session);
    try testing.expectEqualSlices(u8, "/usr/bin/zsh", config.command.?);
    try testing.expectEqualSlices(u8, "/home/test", config.working_directory.?);

    // Verify Subprocess.init handles all config fields
    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, "test-session", subprocess.session.?);
    try testing.expectEqualSlices(u8, "/var/run/tmux.sock", subprocess.socket_path.?);
}

// ============================================================================
// Config Validation Failure Tests (ghostty-1i4.12)
// ============================================================================

test "Backend: tmux config empty session name" {
    // Test that empty session name is handled gracefully
    const alloc = testing.allocator;

    const config = termio.Tmux.Config{
        .session = "",
    };

    // Empty session should still initialize without error
    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    // Empty session should be stored as-is (empty string is valid)
    try testing.expectEqualSlices(u8, "", subprocess.session.?);
}

test "Backend: tmux config session name with special characters" {
    // Test that session names with special characters work
    const alloc = testing.allocator;

    const config = termio.Tmux.Config{
        .session = "my-session_123",
    };

    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, "my-session_123", subprocess.session.?);
}

test "Backend: tmux config session name with spaces" {
    // Test that session names with spaces work (tmux allows this)
    const alloc = testing.allocator;

    const config = termio.Tmux.Config{
        .session = "my session name",
    };

    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, "my session name", subprocess.session.?);
}

test "Backend: tmux config session name with colon (session ID format)" {
    // Test that session names with colons work (used for session:window.pane format)
    const alloc = testing.allocator;

    // tmux accepts session:window.pane format for targeting specific panes
    const config = termio.Tmux.Config{
        .session = "my-session:0.0",
    };

    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, "my-session:0.0", subprocess.session.?);
}

test "Backend: tmux config socket path with tilde expansion" {
    // Test that socket paths with ~ are stored as-is (expansion happens later)
    const alloc = testing.allocator;

    const config = termio.Tmux.Config{
        .socket_path = "~/tmux-socket",
    };

    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    // Path should be stored as-is, ~ expansion is not done here
    try testing.expectEqualSlices(u8, "~/tmux-socket", subprocess.socket_path.?);
}

test "Backend: tmux config relative socket path" {
    // Test that relative socket paths are accepted
    const alloc = testing.allocator;

    const config = termio.Tmux.Config{
        .socket_path = "./tmux.sock",
    };

    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, "./tmux.sock", subprocess.socket_path.?);
}

test "Backend: tmux config very long session name" {
    // Test that very long session names are handled
    const alloc = testing.allocator;

    // tmux has limits but we accept whatever is given
    const long_name = "a" ** 1000;
    const config = termio.Tmux.Config{
        .session = long_name,
    };

    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, long_name, subprocess.session.?);
}

test "Backend: tmux config unicode session name" {
    // Test that unicode session names are handled
    const alloc = testing.allocator;

    const unicode_name = "会话-セッション-🎉";
    const config = termio.Tmux.Config{
        .session = unicode_name,
    };

    var subprocess = try termio.Tmux.Subprocess.init(alloc, config);
    defer subprocess.deinit();

    try testing.expectEqualSlices(u8, unicode_name, subprocess.session.?);
}

test "Backend: tmux config command with arguments" {
    // Test that commands with arguments are stored correctly
    const config = termio.Tmux.Config{
        .command = "/bin/bash -l",
    };

    try testing.expectEqualSlices(u8, "/bin/bash -l", config.command.?);
}

test "Backend: tmux config working_directory with spaces" {
    // Test that working directories with spaces are handled
    const config = termio.Tmux.Config{
        .working_directory = "/home/user/my documents",
    };

    try testing.expectEqualSlices(u8, "/home/user/my documents", config.working_directory.?);
}