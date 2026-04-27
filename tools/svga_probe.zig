const std = @import("std");
const parser = @import("libsvga").parser;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    var saw_path = false;
    var ok_count: usize = 0;
    var fail_count: usize = 0;

    while (args.next()) |path| {
        saw_path = true;
        const bytes = std.fs.cwd().readFileAlloc(allocator, path, 256 * 1024 * 1024) catch |err| {
            fail_count += 1;
            std.debug.print("{s}: read failed: {s}\n", .{ path, @errorName(err) });
            continue;
        };
        defer allocator.free(bytes);

        var metadata = parser.parseMovieMetadata(allocator, bytes) catch |err| {
            fail_count += 1;
            std.debug.print("{s}: parse failed: {s}\n", .{ path, @errorName(err) });
            continue;
        };
        defer metadata.deinit(allocator);

        ok_count += 1;
        const spec = metadata.spec;
        std.debug.print(
            "{s}: {s} {d}x{d} fps={} frames={} images={} sprites={} audios={}\n",
            .{
                path,
                spec.version,
                spec.view_box_width,
                spec.view_box_height,
                spec.fps,
                spec.frames,
                spec.image_count,
                spec.sprite_count,
                spec.audio_count,
            },
        );
    }

    if (!saw_path) {
        std.debug.print("usage: svga_probe <file.svga> [...]\n", .{});
        return error.MissingPath;
    }

    std.debug.print("summary: ok={} failed={}\n", .{ ok_count, fail_count });
    if (fail_count != 0) return error.SomeFilesFailed;
}
