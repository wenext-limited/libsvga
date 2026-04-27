const std = @import("std");
const libsvga = @import("libsvga");

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
        const movie = libsvga.parseMovieFile(allocator, path, .{}) catch |err| {
            fail_count += 1;
            std.debug.print("{s}: parse failed: {s}\n", .{ path, @errorName(err) });
            continue;
        };
        defer libsvga.destroyMovie(allocator, movie);

        ok_count += 1;
        const info = movie.info();
        std.debug.print(
            "{s}: {s} {d}x{d} fps={} frames={} images={} sprites={} audios={}\n",
            .{
                path,
                info.version,
                info.view_box_width,
                info.view_box_height,
                info.fps,
                info.frames,
                info.image_count,
                info.sprite_count,
                info.audio_count,
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
