//! Simple logging library as a first project.
const std = @import("std");
const strfz = @import("strfz");

/// Error severity levels.
const Levels = enum {
    Info,
    Warn,
    Error,
    Critical,
};

/// Colors used for stderr output.
pub const Colors = struct {
    const Red: []const u8 = "\x1b[38;2;255;96;96m";
    const Orange: []const u8 = "\x1b[38;2;255;192;96m";
    const Yellow: []const u8 = "\x1b[38;2;255;255;128m";
    const Gray: []const u8 = "\x1b[38;2;128;128;192m";
    const Green: []const u8 = "\x1b[38;2;96;192;96m";
    const Purple: []const u8 = "\x1b[38;2;192;128;255m";
    const Blue: []const u8 = "\x1b[38;2;96;96;255m";
    const Clear: []const u8 = "\x1b[0m";

    fn level(l: Levels) []const u8 {
        return switch (l) {
            .Info => Colors.Clear,
            .Warn => Colors.Yellow,
            .Error => Colors.Orange,
            .Critical => Colors.Red,
        };
    }
};

/// Main Logger struct.
pub const Logger = struct {
    var io: std.Io = undefined;
    var app: []const u8 = undefined;
    var file_buffer: [64]u8 = undefined;
    var file: []const u8 = undefined;
    var log_to_file: u4 = undefined;
    var log_to_stderr: u4 = undefined;

/// Initiate function, required before use. Can fail.
/// _io, _env: The main application's io, and EnvMap.
/// _app: The application's name for logging purposes.
/// _log_to_file: Bitmask for whether to write to file based on severity Level.
/// _log_to_stderr: Bitmas for whether to write to stderr based on severity Level.
    pub fn init(
        _io: std.Io,
        _env: *const std.process.Environ.Map,
        comptime _app:[]const u8,
        comptime _log_to_file: ?u4,
        comptime _log_to_stderr: ?u4)
    !void {
        io = _io;
        app = _app;
        log_to_file = _log_to_file orelse 0b1111;
        log_to_stderr = _log_to_stderr orelse 0b1111;

        if (log_to_file > 0 ) {
            if (_env.get("XDG_CACHE_HOME")) |XDG_CACHE_HOME| {
                file = try std.fmt.bufPrint(
                    &file_buffer,
                    "{s}/{s}/log",
                    .{XDG_CACHE_HOME,app});
            } else if (_env.get("HOME")) |HOME| {
                file = try std.fmt.bufPrint(
                    &file_buffer,
                    "{s}/.cache/{s}/log",
                    .{HOME,app});
            } else {
                file = try std.fmt.bufPrint(
                    &file_buffer,
                    "/tmp/{s}/log",
                    .{app});
            }
            create_log_file() catch |err| {
                log(.Error,"init","Logfile creation failed: {s}", .{@errorName(err)});
            };
        }
    }

/// Private function used to create the log file written to.
/// Automatically written to ${XDG_CACHE_HOME}/{app}/{timestamp}.
/// A symlink at $XDG_CACHE_HOME/{app}/log will point to the latest timestamped file.
    fn create_log_file() !void {
        const path = std.Io.Dir.path.dirname(file) orelse return error.PathNotFound;

        const dir = try std.Io.Dir.cwd().createDirPathOpen(io, path, .{});

        var time_buffer: [20]u8 = undefined;
        const timestamp = get_time(&time_buffer);
        var timestamped_buffer: [128]u8 = undefined;
        const timestamped_path = try std.fmt.bufPrint(
            &timestamped_buffer,
            "{s}/{s}.log",
            .{path,timestamp});
        const timestamped_file = try dir.createFile(
            io,
            timestamped_path,
            .{.read = true});
        timestamped_file.close(io);

        std.Io.Dir.cwd().deleteFile(io, file) catch {};
        const link = dir.symLink(
            io,
            timestamped_path,
            file, .{}) catch unreachable;
        return link;
    }

/// The main logging function. Errors are swallowed.
// TODO: Actually CHECK the console for color capabiltity.
    pub fn log(
        comptime level: Levels,
        comptime scope: ?[]const u8,
        comptime msg: []const u8,
        args: anytype)
    void {
        // TODO: Account for args unwrapping.
        var msg_buffer: [512]u8 = undefined;
        const message = std.fmt.bufPrint(
            &msg_buffer,
            msg[0..@min(msg_buffer.len,msg.len)],
            args) catch "Buffer ran out of space.";
        const mask = @as(u4,@intCast(1)) << @intFromEnum(level);
        if ((mask & log_to_file) != 0) {
            var format_buffer: [768]u8 = undefined;
            const formatted_message = format_message(
                &format_buffer,
                level,
                scope,
                message[0..@min(format_buffer.len,message.len)],
                false) catch "";
            write_to_file(formatted_message) catch {};
        }
        if ((mask & log_to_stderr) != 0) {
            var format_buffer: [768]u8 = undefined;
            const formatted_message = format_message(
                &format_buffer,
                level,
                scope,
                message[0..@min(format_buffer.len,message.len)],
                true) catch "";
            write_to_stderr(formatted_message) catch {};
        }
    }

/// Formats the string, using the format below.
/// [ {timestamp} ] {app}({scope}){Level} - {message}
    fn format_message(
        buffer: []u8,
        comptime level: Levels,
        comptime scope: ?[]const u8,
        message: []const u8,
        colorized: bool)
    ![]u8 {
        var time_buffer: [20]u8 = undefined;
        const timestamp = get_time(&time_buffer);
        const scope_str = scope orelse "";
        return try std.fmt.bufPrint(buffer,
            "{s}[ {s} ] {s}{s}({s}){} {0s}- {s}{s} {s}\n", .{
            if (colorized) Colors.Gray else "",
                timestamp,
            if (colorized) Colors.level(level) else "",
                app,
                scope_str,
                level,
            if (colorized) Colors.Purple else "",
                message,
            if (colorized) Colors.Clear else "",
        });
    }

/// Opens the logging file, created in init(), and writes the last line.
    fn write_to_file(message:  []const u8) !void {
        const log_file = std.Io.Dir.cwd().openFile(io,
            file,
            .{ .mode = .read_write }) catch |err| return err;
        defer log_file.close(io);

        var writer = log_file.writer(io, &.{});
        try writer.seekTo(try log_file.length(io));

        _ = try writer.interface.write(message);
        try writer.flush();
    }

/// Writes the message to stderr.
    fn write_to_stderr(message: []const u8) !void {
        var stderr = try std.Io.lockStderr(io, &.{}, null);
        defer std.Io.unlockStderr(io);

        _ = try stderr.file_writer.interface.write(message);
    }
};

/// Get current formatted time for logging.
fn get_time(buffer: *[20]u8) []u8 {
    const format = "%F_%T";
    const secs = std.Io.Timestamp.now(Logger.io, .real).toSeconds();
    return strfz.formatUnix(buffer, format, secs, 0);
}


// TODO: Make these actually ASSERT something.
test "Colors" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    try env.put("XDG_CACHE_HOME", "/tmp/logger-tests");

    try Logger.init(std.testing.io, &env, "LoggerTests", 0b1111, 0b1111);
    Logger.log(.Info,"Colors","{s}Te{s}st{s}in{s}g C{s}ol{s}or{s}s.{s}",.{
        Colors.Blue, Colors.Purple, Colors.Green,
        Colors.Gray,
        Colors.Yellow, Colors.Orange, Colors.Red,
        Colors.Clear
    });
}

test "Levels functioning" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    try env.put("XDG_CACHE_HOME", "/tmp/logger-tests");

    try Logger.init(std.testing.io, &env, "LoggerTests", null, null);
    Logger.log(.Critical, "levels", "saba is back?!", .{});
    try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(100), std.Io.Clock.real);
    Logger.log(.Error, null, "ohno", .{});
    Logger.log(.Warn, "levels", "gotta test warn", .{});
    try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(100), std.Io.Clock.real);
    Logger.log(.Info, "levels", "fuckoff", .{});
}

test "Log_to_ functioning" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    try env.put("XDG_CACHE_HOME", "/tmp/logger-tests");

    try Logger.init(std.testing.io, &env, "LoggerTests", 0b0000, 0b1100);
    Logger.log(.Critical, "log_to_", "shachi is back?!", .{});
    try std.Io.sleep(std.testing.io, std.Io.Duration.fromMilliseconds(100), std.Io.Clock.real);
    Logger.log(.Error, "log_to_", "I need these messages to be different.", .{});
    Logger.log(.Warn, "log_to_", "gotta test warn", .{});
    Logger.log(.Info, "log_to_", "Not these though hopefully.", .{});
}

test "Very long messages" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    try env.put("XDG_CACHE_HOME", "/tmp/logger-tests");

    try Logger.init(std.testing.io, &env, "LoggerTests", null, null);
    Logger.log(.Error, "buffer",
        "I need to test really long strings and logging to see what happens. {s}I think colors might be the easiest way to inflate this. {s}But {0s}I'm {1s}not sure. So maybe I should write more because this probably isn't enough.{s}D. Gray Man is kinda trash but that Brightdown opening is actually pretty {0s}great{1s}.{2s} What do you think?{s} I increased the size of the buffer and now need to increase these to match that.",
        .{Colors.Blue, Colors.Red, Colors.Green, Colors.Gray,}
    );
    Logger.log(.Info, "buffer",
        "That one was actually too long so maybe I should try without colors and see where it goes. I don't know how long I need to make this but let's try to figure it out. This seems like it's a perfectly fine length and won't cause problems. But for how much longer is that true? That much is still fine. I'll stop here and see how it goes. It went fine, still.",
        .{}
    );
    Logger.log(.Warn, "buffer",
        "That one was fine actually and passed both buffers without issue. Let's try to make one that will fail on the initial args buffer. They're both the same size so this will need to be even longer than the first one. I should probably use colors to expand this string easily, but I would like a grasp for exactly how many characters I have before it overflows that buffer. Maybe another sentence or two? That reached the format buffer limit, but not the args buffer limit. Still not quite long enough. That's what she said. The first one actually ran out of space and I'm not sure how that can happen when it's basically clamped to the size of the buffer itself. So that will be interesting to figure out I guess. This one is clamping properly seemingly, But I need to write a good bit more to see for certain. I bet what's happening is the args unwrap in msg_buffer, while they're already unwrapped in format_buffer, so the extra space taken from the colors are exceeding msg_buffer.",
        .{}
    );
}
