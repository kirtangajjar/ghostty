//! Tmux implements the logic for connecting to a tmux session via control mode.
//! This backend allows Ghostty to act as a tmux client, displaying tmux panes
//! and routing input to the active pane.
//!
//! ## Architecture
//!
//! The tmux backend works by:
//!
//! 1. Spawning a tmux client process in control mode (`tmux -C`)
//! 2. Reading protocol messages from tmux's stdout
//! 3. Parsing control mode notifications using the control.Parser
//! 4. Maintaining viewer state (windows, panes) via viewer.Viewer
//! 5. Routing user input to tmux via stdin using `%key` commands
//!
//! ## Lifecycle
//!
//! 1. `init()` - Allocate state, parse config
//! 2. `initTerminal()` - Set up initial terminal size
//! 3. `threadEnter()` - Spawn tmux process, start read thread
//! 4. (normal operation - reading/writing)
//! 5. `threadExit()` - Stop read thread, clean up process
//! 6. `deinit()` - Free all resources

const Tmux = @This();

const std = @import("std");
const builtin = @import("builtin");
const assert = @import("../quirks.zig").inlineAssert;
const Allocator = std.mem.Allocator;
const posix = std.posix;
const xev = @import("../global.zig").xev;
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const termio = @import("../termio.zig");
const Command = @import("../Command.zig");
const SegmentedPool = @import("../datastruct/main.zig").SegmentedPool;
const internal_os = @import("../os/main.zig");
const tmux_control = @import("../terminal/tmux/control.zig");
const tmux_viewer = @import("../terminal/tmux/viewer.zig");

const log = std.log.scoped(.io_tmux);

/// The tmux subprocess state
subprocess: Subprocess,

/// Initialize the tmux backend. This sets up internal state but does NOT
/// start the tmux connection yet.
pub fn init(
    alloc: Allocator,
    cfg: Config,
) !Tmux {
    var subprocess = try Subprocess.init(alloc, cfg);
    errdefer subprocess.deinit();

    return .{ .subprocess = subprocess };
}

pub fn deinit(self: *Tmux) void {
    self.subprocess.deinit();
}

/// Initialize terminal state. Called before termio begins.
pub fn initTerminal(self: *Tmux, term: *terminal.Terminal) void {
    // Set initial grid/screen size from terminal
    self.resize(.{
        .columns = term.cols,
        .rows = term.rows,
    }, .{
        .width = term.width_px,
        .height = term.height_px,
    }) catch |err| {
        log.warn("failed to resize tmux backend on init: {}", .{err});
    };
}

pub fn threadEnter(
    self: *Tmux,
    alloc: Allocator,
    io: *termio.Termio,
    td: *termio.Termio.ThreadData,
) !void {
    // Start the tmux subprocess
    const fds = try self.subprocess.start(alloc);
    errdefer self.subprocess.stop();

    // Create pipe for signaling read thread to quit
    const pipe = try internal_os.pipe();
    errdefer {
        posix.close(pipe[0]);
        posix.close(pipe[1]);
    }

    // Setup write stream
    var stream = xev.Stream.initFd(fds.write);
    errdefer stream.deinit();

    // Start read thread
    const read_thread = try std.Thread.spawn(
        .{},
        ReadThread.threadMain,
        .{ alloc, fds.read, io, pipe[0] },
    );
    read_thread.setName("io-tmux-reader") catch {};

    // Setup thread data
    td.backend = .{ .tmux = .{
        .start = try std.time.Instant.now(),
        .write_stream = stream,
        .read_thread = read_thread,
        .read_thread_pipe = pipe[1],
        .read_thread_fd = fds.read,
        .viewer = try tmux_viewer.Viewer.init(alloc),
    } };
    errdefer {
        td.backend.tmux.viewer.deinit();
    }
}

pub fn threadExit(self: *Tmux, td: *termio.Termio.ThreadData) void {
    assert(td.backend == .tmux);
    const tmux = &td.backend.tmux;

    // Stop the subprocess
    self.subprocess.stop();

    // Signal read thread to quit
    _ = posix.write(tmux.read_thread_pipe, "x") catch |err| {
        if (err != error.BrokenPipe) {
            log.warn("error writing to read thread quit pipe: {}", .{err});
        }
    };

    // Wait for read thread to finish
    tmux.read_thread.join();

    // Close the quit pipe write end
    posix.close(tmux.read_thread_pipe);
}

pub fn focusGained(
    self: *Tmux,
    td: *termio.Termio.ThreadData,
    focused: bool,
) !void {
    _ = self;
    _ = td;
    _ = focused;
    // TODO: Send focus event to tmux (if needed)
    // Tmux control mode doesn't have a dedicated focus notification,
    // but we could potentially track this for UI purposes.
}

pub fn resize(
    self: *Tmux,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,
) !void {
    // Resize the tmux client window
    // This is done via sending a resize command to tmux
    try self.subprocess.resize(grid_size, screen_size);
}

pub fn queueWrite(
    self: *Tmux,
    alloc: Allocator,
    td: *termio.Termio.ThreadData,
    data: []const u8,
    linefeed: bool,
) !void {
    _ = self;
    _ = linefeed; // tmux handles line endings

    const tmux = &td.backend.tmux;

    // If our process is exited then we don't send any more writes.
    if (tmux.exited) return;

    // Queue data to be written to tmux stdin
    // This will send key input to tmux via %key commands
    var i: usize = 0;
    while (i < data.len) {
        const req = try tmux.write_req_pool.getGrow(alloc);
        const buf = try tmux.write_buf_pool.getGrow(alloc);
        const slice = slice: {
            // The maximum end index is either the end of our data or
            // the end of our buffer, whichever is smaller.
            const max = @min(data.len, i + buf.len);
            const len = max - i;
            @memcpy(buf[0..len], data[i..max]);
            i = max;
            break :slice buf[0..len];
        };

        tmux.write_stream.queueWrite(
            td.loop,
            &tmux.write_queue,
            req,
            .{ .slice = slice },
            ThreadData,
            tmux,
            ttyWrite,
        );
    }
}

/// Write data directly to tmux. This is a synchronous write that bypasses
/// the async queue system. Use this for time-sensitive writes.
pub fn write(self: *Tmux, data: []const u8) !void {
    const fd = self.subprocess.stdin_fd orelse return error.ProcessNotStarted;

    // Write all data to tmux
    var remaining = data;
    while (remaining.len > 0) {
        const written = posix.write(fd, remaining) catch |err| {
            log.err("failed to write to tmux: {}", .{err});
            return err;
        };
        if (written == 0) return error.WriteFailed;
        remaining = remaining[written..];
    }
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
    _ = runtime_ms;

    // For tmux backend, this shouldn't normally be called since
    // the tmux client is managed differently than a direct child process.
    // But we implement it for completeness.
    log.warn("tmux client exited abnormally with code {}", .{exit_code});
}

fn ttyWrite(
    td_: ?*ThreadData,
    _: *xev.Loop,
    _: *xev.Completion,
    _: xev.Stream,
    _: xev.WriteBuffer,
    r: xev.WriteError!usize,
) xev.CallbackAction {
    const td = td_.?;
    td.write_req_pool.put();
    td.write_buf_pool.put();

    const d = r catch |err| {
        log.err("tmux write error: {}", .{err});
        return .disarm;
    };
    _ = d;

    return .disarm;
}

/// The thread local data for the tmux implementation.
pub const ThreadData = struct {
    /// The preallocation size for the write request pool.
    const WRITE_REQ_PREALLOC = std.math.pow(usize, 2, 5);

    /// Process start time and whether it has exited.
    start: std.time.Instant,
    exited: bool = false,

    /// The data stream is the main IO for tmux stdin.
    write_stream: xev.Stream,

    /// This is the pool of available (unused) write requests.
    write_req_pool: SegmentedPool(xev.WriteRequest, WRITE_REQ_PREALLOC) = .{},

    /// The pool of available buffers for writing to tmux.
    write_buf_pool: SegmentedPool([64]u8, WRITE_REQ_PREALLOC) = .{},

    /// The write queue for the data stream.
    write_queue: xev.WriteQueue = .{},

    /// Reader thread state
    read_thread: std.Thread,
    read_thread_pipe: posix.fd_t,
    read_thread_fd: posix.fd_t,

    /// The tmux viewer state - tracks windows, panes, etc.
    viewer: tmux_viewer.Viewer,

    pub fn deinit(self: *ThreadData, alloc: Allocator) void {
        posix.close(self.read_thread_pipe);

        // Clear our write pools
        self.write_req_pool.deinit(alloc);
        self.write_buf_pool.deinit(alloc);

        // Stop our write stream
        self.write_stream.deinit();

        // Clean up viewer state
        self.viewer.deinit();
    }

    pub fn changeConfig(self: *ThreadData, config: *termio.DerivedConfig) void {
        _ = self;
        _ = config;
        // TODO: Handle configuration changes for tmux backend
    }
};

/// Configuration for the tmux backend.
pub const Config = struct {
    /// The tmux session name or ID to attach to.
    /// If null, attaches to the most recent session or creates a new one.
    session: ?[]const u8 = null,

    /// The tmux socket path to use. If null, uses the default socket.
    socket_path: ?[]const u8 = null,

    /// Whether to create a new session if one doesn't exist.
    create_session: bool = false,

    /// The command to run in a new session (only used if create_session is true).
    command: ?[]const u8 = null,

    /// The working directory for a new session.
    working_directory: ?[]const u8 = null,
};

/// Subprocess management for tmux client.
const Subprocess = struct {
    const c = @cImport({
        @cInclude("errno.h");
        @cInclude("signal.h");
        @cInclude("unistd.h");
    });

    arena: std.heap.ArenaAllocator,
    args: []const [:0]const u8,
    socket_path: ?[:0]const u8,
    session: ?[:0]const u8,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,

    /// Process state
    process: ?Process = null,
    stdin_fd: ?posix.fd_t = null,
    stdout_fd: ?posix.fd_t = null,

    const Process = struct {
        /// The child process PID
        pid: posix.pid_t,

        /// Whether we've detached from the process
        detached: bool = false,
    };

    /// Initialize the subprocess state. Does NOT start tmux yet.
    pub fn init(gpa: Allocator, cfg: Config) !Subprocess {
        var arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        const alloc = arena.allocator();

        // Build the tmux command line arguments
        var args: std.ArrayList([:0]const u8) = try .initCapacity(alloc, 8);
        errdefer args.deinit(alloc);

        // Always use control mode
        try args.append(alloc, "tmux");
        try args.append(alloc, "-C"); // Control mode

        // Add socket path if specified
        var socket_path: ?[:0]u8 = null;
        if (cfg.socket_path) |sp| {
            try args.append(alloc, "-S");
            const sp_dup = try alloc.dupeZ(u8, sp);
            socket_path = sp_dup;
            try args.append(alloc, sp_dup);
        }

        // Build attach command
        try args.append(alloc, "attach");

        // Add session if specified
        var session: ?[:0]u8 = null;
        if (cfg.session) |s| {
            const s_dup = try alloc.dupeZ(u8, s);
            session = s_dup;
            try args.append(alloc, "-t");
            try args.append(alloc, s_dup);
        }

        const args_slice = try args.toOwnedSlice(alloc);

        return .{
            .arena = arena,
            .args = args_slice,
            .socket_path = socket_path,
            .session = session,
            .grid_size = .{},
            .screen_size = .{ .width = 1, .height = 1 },
        };
    }

    pub fn deinit(self: *Subprocess) void {
        self.stop();
        self.arena.deinit();
    }

    /// Start the tmux client process.
    pub fn start(self: *Subprocess, alloc: Allocator) !struct {
        read: posix.fd_t,
        write: posix.fd_t,
    } {
        assert(self.process == null);

        // Create pipes for stdin/stdout
        const stdin_pipe = try internal_os.pipe();
        errdefer {
            posix.close(stdin_pipe[0]);
            posix.close(stdin_pipe[1]);
        }

        const stdout_pipe = try internal_os.pipe();
        errdefer {
            posix.close(stdout_pipe[0]);
            posix.close(stdout_pipe[1]);
        }

        // Fork and exec
        const pid = try posix.fork();
        if (pid == 0) {
            // Child process
            posix.close(stdin_pipe[1]); // Close write end
            posix.close(stdout_pipe[0]); // Close read end

            // Redirect stdin/stdout
            try posix.dup2(stdin_pipe[0], posix.STDIN_FILENO);
            try posix.dup2(stdout_pipe[1], posix.STDOUT_FILENO);

            // Close the original fds
            posix.close(stdin_pipe[0]);
            posix.close(stdout_pipe[1]);

            // Execute tmux
            const argv = blk: {
                var list = try alloc.allocSentinel(?[*:0]const u8, self.args.len, null);
                for (self.args, 0..) |arg, i| list[i] = arg.ptr;
                break :blk list;
            };

            const err = posix.execvpeZ(argv[0].?, argv.ptr, @ptrCast(std.os.environ.ptr));
            _ = err catch {};
            posix.exit(1);
        }

        // Parent process
        posix.close(stdin_pipe[0]); // Close read end
        posix.close(stdout_pipe[1]); // Close write end

        self.stdin_fd = stdin_pipe[1];
        self.stdout_fd = stdout_pipe[0];
        self.process = .{ .pid = pid };

        log.info("started tmux client pid={}", .{pid});

        return .{
            .read = stdout_pipe[0],
            .write = stdin_pipe[1],
        };
    }

    /// Stop the tmux client process.
    pub fn stop(self: *Subprocess) void {
        if (self.process) |*proc| {
            // Send SIGHUP to detach from tmux session gracefully
            _ = posix.kill(proc.pid, posix.SIG.HUP) catch |err| {
                log.warn("failed to send SIGHUP to tmux: {}", .{err});
            };

            // Wait for process to exit
            _ = posix.waitpid(proc.pid, 0);
            self.process = null;
        }

        // Close file descriptors
        if (self.stdin_fd) |fd| {
            posix.close(fd);
            self.stdin_fd = null;
        }
        if (self.stdout_fd) |fd| {
            posix.close(fd);
            self.stdout_fd = null;
        }
    }

    /// Resize the tmux client window.
    pub fn resize(
        self: *Subprocess,
        grid_size: renderer.GridSize,
        screen_size: renderer.ScreenSize,
    ) !void {
        self.grid_size = grid_size;
        self.screen_size = screen_size;

        // Send resize command to tmux via stdin
        // This would be: refresh-client -C {width}x{height},{width_px}x{height_px}
        // For now, we just store the size and send it on start
        // TODO: Implement dynamic resize by sending commands to tmux
    }

    /// Called when the process exits externally.
    pub fn externalExit(self: *Subprocess) void {
        self.process = null;
    }
};

/// Read thread implementation for tmux control mode.
const ReadThread = struct {
    fn threadMain(alloc: Allocator, fd: posix.fd_t, io: *termio.Termio, quit: posix.fd_t) void {
        // Always close our end of the pipe when we exit.
        defer posix.close(quit);

        // Setup crash metadata
        const crash_mod = @import("../crash/main.zig");
        crash_mod.sentry.thread_state = .{
            .type = .io,
            .surface = io.surface_mailbox.surface,
        };
        defer crash_mod.sentry.thread_state = null;

        // Set fd to non-blocking
        if (posix.fcntl(fd, posix.F.GETFL, 0)) |flags| {
            _ = posix.fcntl(
                fd,
                posix.F.SETFL,
                flags | @as(u32, @bitCast(posix.O{ .NONBLOCK = true })),
            ) catch |err| {
                log.warn("failed to set tmux fd non-blocking: {}", .{err});
            };
        } else |err| {
            log.warn("failed to get tmux fd flags: {}", .{err});
        }

        // Setup poll fds
        var pollfds: [2]posix.pollfd = .{
            .{ .fd = fd, .events = posix.POLL.IN, .revents = undefined },
            .{ .fd = quit, .events = posix.POLL.IN, .revents = undefined },
        };

        // Create a parser for tmux control mode output
        var parser: tmux_control.Parser = .{ .buffer = .init(alloc) };
        defer parser.deinit();

        var buf: [4096]u8 = undefined;
        while (true) {
            // Try to read as much as possible first
            while (true) {
                const n = posix.read(fd, &buf) catch |err| {
                    switch (err) {
                        error.NotOpenForReading,
                        error.InputOutput,
                        => {
                            log.info("tmux reader exiting", .{});
                            return;
                        },
                        error.WouldBlock => break,
                        else => {
                            log.err("tmux reader error: {}", .{err});
                            return;
                        },
                    }
                };

                if (n == 0) break;

                // Process the buffer through the parser
                for (buf[0..n]) |byte| {
                    if (parser.put(byte) catch null) |notification| {
                        // Handle the notification
                        handleNotification(io, &notification);
                    }
                }
            }

            // Wait for data
            _ = posix.poll(&pollfds, -1) catch |err| {
                log.warn("poll failed on tmux read thread: {}", .{err});
                return;
            };

            // Check for quit signal
            if (pollfds[1].revents & posix.POLL.IN != 0) {
                log.info("tmux read thread got quit signal", .{});
                return;
            }

            // Check for HUP (tmux closed)
            if (pollfds[0].revents & posix.POLL.HUP != 0) {
                log.info("tmux fd closed, read thread exiting", .{});
                return;
            }
        }
    }

    fn handleNotification(io: *termio.Termio, notification: *const tmux_control.Notification) void {
        switch (notification.*) {
            .output => |out| {
                // Output from a tmux pane - process it
                // The output is already parsed and contains pane ID and data
                log.debug("tmux output pane={} len={}", .{ out.pane_id, out.data.len });
                // TODO: Route to the correct pane's terminal
                termio.Termio.processOutput(io, out.data);
            },
            .block_end => |data| {
                // A command response block ended
                log.debug("tmux block end: {s}", .{data});
            },
            .block_err => |data| {
                // An error response from tmux
                log.warn("tmux error: {s}", .{data});
            },
            .exit => {
                // tmux is exiting
                log.info("tmux control mode exiting", .{});
                // TODO: Signal the surface that tmux has exited
            },
            else => {
                // Other notifications (session-changed, window-add, etc.)
                log.debug("tmux notification: {s}", .{@tagName(notification.*)});
            },
        }
    }
};