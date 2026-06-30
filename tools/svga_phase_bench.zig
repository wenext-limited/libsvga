const std = @import("std");
const builtin = @import("builtin");
const libsvga = @import("libsvga");

const allocator = if (builtin.single_threaded or builtin.target.cpu.arch.isWasm())
    std.heap.page_allocator
else
    std.heap.smp_allocator;

const ContainerKind = enum {
    zlib,
    zip,

    fn label(self: ContainerKind) []const u8 {
        return switch (self) {
            .zlib => "zlib",
            .zip => "zip",
        };
    }
};

const Config = struct {
    fixture_dir: []const u8 = "",
    iterations: usize = 10,
    warmup: usize = 1,
    max_files: ?usize = null,
    max_input_bytes: usize = libsvga.default_max_input_bytes,
    max_output_bytes: usize = libsvga.default_max_output_bytes,
    tsv_path: ?[]const u8 = null,
};

const Fixture = struct {
    path: []const u8,
    bytes: []u8,
};

const Measurement = struct {
    container: ContainerKind,
    input_bytes: usize = 0,
    inflated_bytes: usize = 0,
    total_ns: u64 = 0,
    inflate_ns: u64 = 0,
    proto_ns: u64 = 0,
    zip_metadata_ns: u64 = 0,
    model_ns: u64 = 0,
    destroy_ns: u64 = 0,
    checksum: u64 = 0,
};

const Totals = struct {
    parses: usize = 0,
    zlib_count: usize = 0,
    zip_count: usize = 0,
    input_bytes: usize = 0,
    inflated_bytes: usize = 0,
    total_ns: u64 = 0,
    inflate_ns: u64 = 0,
    proto_ns: u64 = 0,
    zip_metadata_ns: u64 = 0,
    model_ns: u64 = 0,
    destroy_ns: u64 = 0,
    checksum: u64 = 0,

    fn add(self: *Totals, measurement: Measurement) void {
        self.parses += 1;
        switch (measurement.container) {
            .zlib => self.zlib_count += 1,
            .zip => self.zip_count += 1,
        }
        self.input_bytes += measurement.input_bytes;
        self.inflated_bytes += measurement.inflated_bytes;
        self.total_ns += measurement.total_ns;
        self.inflate_ns += measurement.inflate_ns;
        self.proto_ns += measurement.proto_ns;
        self.zip_metadata_ns += measurement.zip_metadata_ns;
        self.model_ns += measurement.model_ns;
        self.destroy_ns += measurement.destroy_ns;
        self.checksum +%= measurement.checksum;
    }
};

pub fn main() !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const config = parseArgs(&args) catch |err| {
        switch (err) {
            error.HelpRequested => {
                printUsage();
                return;
            },
            else => return err,
        }
    };

    if (config.tsv_path) |path| {
        const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();

        var buffer: [64 * 1024]u8 = undefined;
        var file_writer = file.writer(&buffer);
        try writeTsvHeader(&file_writer.interface);
        try run(config, &file_writer.interface);
        try file_writer.interface.flush();
    } else {
        try run(config, null);
    }
}

fn parseArgs(args: *std.process.ArgIterator) !Config {
    _ = args.next();

    var config = Config{};
    var positional_count: usize = 0;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.HelpRequested;
        } else if (std.mem.eql(u8, arg, "--iterations")) {
            config.iterations = try parsePositive(args.next() orelse return error.MissingOptionValue, "--iterations");
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            config.warmup = try parseNonNegative(args.next() orelse return error.MissingOptionValue, "--warmup");
        } else if (std.mem.eql(u8, arg, "--max-files")) {
            config.max_files = try parsePositive(args.next() orelse return error.MissingOptionValue, "--max-files");
        } else if (std.mem.eql(u8, arg, "--max-input-bytes")) {
            config.max_input_bytes = try parsePositive(args.next() orelse return error.MissingOptionValue, "--max-input-bytes");
        } else if (std.mem.eql(u8, arg, "--max-output-bytes")) {
            config.max_output_bytes = try parsePositive(args.next() orelse return error.MissingOptionValue, "--max-output-bytes");
        } else if (std.mem.eql(u8, arg, "--tsv")) {
            config.tsv_path = args.next() orelse return error.MissingOptionValue;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("unknown option: {s}\n", .{arg});
            return error.UnknownOption;
        } else {
            switch (positional_count) {
                0 => config.fixture_dir = arg,
                1 => config.iterations = try parsePositive(arg, "iterations"),
                else => return error.TooManyArguments,
            }
            positional_count += 1;
        }
    }

    if (config.fixture_dir.len == 0) {
        printUsage();
        return error.MissingFixtureDir;
    }
    return config;
}

fn parsePositive(value: []const u8, label: []const u8) !usize {
    const parsed = try std.fmt.parseInt(usize, value, 10);
    if (parsed == 0) {
        std.debug.print("{s} must be greater than zero\n", .{label});
        return error.InvalidOptionValue;
    }
    return parsed;
}

fn parseNonNegative(value: []const u8, label: []const u8) !usize {
    const parsed = try std.fmt.parseInt(usize, value, 10);
    _ = label;
    return parsed;
}

fn printUsage() void {
    std.debug.print(
        \\usage: svga_phase_bench [options] <fixture-dir> [iterations]
        \\
        \\options:
        \\  --iterations N        measured iterations, default 10
        \\  --warmup N            unmeasured warmup iterations, default 1
        \\  --max-files N         benchmark only first N sorted .svga files
        \\  --max-input-bytes N   max bytes read per file, default libsvga limit
        \\  --max-output-bytes N  max inflated bytes per file, default libsvga limit
        \\  --tsv PATH            write per-parse phase rows
        \\
    , .{});
}

fn run(config: Config, tsv_writer: ?*std.Io.Writer) !void {
    var fixtures = try loadFixtures(config);
    defer fixtures.deinit(allocator);
    defer freeFixtures(fixtures.items);

    var totals = Totals{};
    const run_count = config.warmup + config.iterations;
    for (0..run_count) |iteration| {
        const measured = iteration >= config.warmup;
        for (fixtures.items) |fixture| {
            const measurement = measureFixture(fixture, config.max_output_bytes) catch |err| {
                std.debug.print("{s}: parse failed: {s}\n", .{ fixture.path, @errorName(err) });
                return err;
            };
            if (!measured) continue;

            totals.add(measurement);
            if (tsv_writer) |writer| {
                try writeTsvRow(writer, iteration - config.warmup, fixture, measurement);
            }
        }
    }

    printSummary(config, fixtures.items.len, totals);
}

fn loadFixtures(config: Config) !std.ArrayList(Fixture) {
    var paths: std.ArrayList([]u8) = .empty;
    errdefer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }

    var dir = try std.fs.cwd().openDir(config.fixture_dir, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".svga")) continue;
        const full_path = try std.fs.path.join(allocator, &.{ config.fixture_dir, entry.path });
        try paths.append(allocator, full_path);
    }

    if (paths.items.len == 0) return error.NoFixtures;
    std.mem.sort([]u8, paths.items, {}, pathLessThan);

    const count = if (config.max_files) |max_files|
        @min(max_files, paths.items.len)
    else
        paths.items.len;

    var fixtures: std.ArrayList(Fixture) = .empty;
    errdefer {
        freeFixtures(fixtures.items);
        fixtures.deinit(allocator);
    }
    try fixtures.ensureTotalCapacity(allocator, count);

    for (paths.items[0..count]) |path| {
        const bytes = try std.fs.cwd().readFileAlloc(allocator, path, config.max_input_bytes);
        fixtures.appendAssumeCapacity(.{
            .path = path,
            .bytes = bytes,
        });
    }

    for (paths.items[count..]) |path| allocator.free(path);
    paths.deinit(allocator);

    return fixtures;
}

fn freeFixtures(fixtures: []const Fixture) void {
    for (fixtures) |fixture| {
        allocator.free(fixture.bytes);
        allocator.free(fixture.path);
    }
}

fn pathLessThan(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn measureFixture(fixture: Fixture, max_output_bytes: usize) !Measurement {
    const total_start = timestamp();
    var result = Measurement{
        .container = undefined,
        .input_bytes = fixture.bytes.len,
    };

    if (libsvga.parser.isZip(fixture.bytes)) {
        result.container = .zip;

        const metadata_start = timestamp();
        var metadata = try libsvga.parser.parseMovieMetadataWithOptions(allocator, fixture.bytes, .{
            .max_output_bytes = max_output_bytes,
        });
        result.zip_metadata_ns = elapsedSince(metadata_start);
        defer metadata.deinit(allocator);

        const model_start = timestamp();
        var movie = try libsvga.model.Movie.initWithLimits(allocator, metadata.spec, .{});
        result.model_ns = elapsedSince(model_start);

        result.checksum = checksumMovie(&movie);
        const destroy_start = timestamp();
        movie.deinit(allocator);
        result.destroy_ns = elapsedSince(destroy_start);
    } else {
        if (!libsvga.parser.isZlibStream(fixture.bytes)) return error.InvalidData;
        result.container = .zlib;

        const inflate_start = timestamp();
        const inflated = try libsvga.parser.inflateZlibForBenchmark(allocator, fixture.bytes, max_output_bytes);
        result.inflate_ns = elapsedSince(inflate_start);
        result.inflated_bytes = inflated.len;
        defer allocator.free(inflated);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const proto_start = timestamp();
        const spec = try libsvga.parser.parseMovieProto(arena.allocator(), inflated);
        result.proto_ns = elapsedSince(proto_start);

        const model_start = timestamp();
        var movie = try libsvga.model.Movie.initWithLimits(allocator, spec, .{});
        result.model_ns = elapsedSince(model_start);

        result.checksum = checksumMovie(&movie);
        const destroy_start = timestamp();
        movie.deinit(allocator);
        result.destroy_ns = elapsedSince(destroy_start);
    }

    result.total_ns = elapsedSince(total_start);
    return result;
}

fn timestamp() std.time.Instant {
    return std.time.Instant.now() catch unreachable;
}

fn elapsedSince(start: std.time.Instant) u64 {
    return timestamp().since(start);
}

fn checksumMovie(movie: *const libsvga.model.Movie) u64 {
    var checksum: u64 = 0;
    checksum +%= @intCast(movie.frames);
    checksum +%= movie.image_count;
    checksum +%= movie.sprite_count;
    checksum +%= movie.audio_count;
    checksum +%= movie.assets.len;
    checksum +%= movie.sprites.len;
    checksum +%= movie.audios.len;
    checksum +%= movie.metadata.frame_records.len;
    checksum +%= movie.metadata.shape_records.len;
    checksum +%= movie.metadata.clip_path_commands.len;
    checksum +%= movie.metadata.shape_path_commands.len;
    checksum +%= movie.render_commands.len;
    checksum +%= movie.render_items.len;
    checksum +%= movie.visual_frame_indices.len;
    return checksum;
}

fn printSummary(config: Config, file_count: usize, totals: Totals) void {
    const stdout = std.debug;
    stdout.print(
        "zig/libsvga-phase files={} iterations={} warmup={} parses={} zlib={} zip={} input_mb={d:.3} inflated_mb={d:.3} total_ms={d:.3} ns_per_parse={d:.1} checksum={}\n",
        .{
            file_count,
            config.iterations,
            config.warmup,
            totals.parses,
            totals.zlib_count,
            totals.zip_count,
            mb(totals.input_bytes),
            mb(totals.inflated_bytes),
            ms(totals.total_ns),
            nsPerParse(totals.total_ns, totals.parses),
            totals.checksum,
        },
    );
    printPhase("inflate", totals.inflate_ns, totals);
    printPhase("protobuf", totals.proto_ns, totals);
    printPhase("zip_metadata", totals.zip_metadata_ns, totals);
    printPhase("model_init", totals.model_ns, totals);
    printPhase("destroy", totals.destroy_ns, totals);
    const accounted = totals.inflate_ns + totals.proto_ns + totals.zip_metadata_ns + totals.model_ns + totals.destroy_ns;
    printPhase("unaccounted", totals.total_ns -| accounted, totals);
}

fn printPhase(name: []const u8, ns: u64, totals: Totals) void {
    std.debug.print(
        "phase={s} total_ms={d:.3} ns_per_parse={d:.1} pct_total={d:.1}\n",
        .{
            name,
            ms(ns),
            nsPerParse(ns, totals.parses),
            percent(ns, totals.total_ns),
        },
    );
}

fn ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

fn nsPerParse(ns: u64, parses: usize) f64 {
    if (parses == 0) return 0;
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(parses));
}

fn percent(part: u64, total: u64) f64 {
    if (total == 0) return 0;
    return @as(f64, @floatFromInt(part)) * 100.0 / @as(f64, @floatFromInt(total));
}

fn mb(bytes: usize) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
}

fn writeTsvHeader(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        "iteration\tpath\tcontainer\tinput_bytes\tinflated_bytes\ttotal_ns\tinflate_ns\tprotobuf_ns\tzip_metadata_ns\tmodel_init_ns\tdestroy_ns\tchecksum\n",
    );
}

fn writeTsvRow(writer: *std.Io.Writer, iteration: usize, fixture: Fixture, measurement: Measurement) !void {
    try writer.print(
        "{}\t{s}\t{s}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
        .{
            iteration,
            fixture.path,
            measurement.container.label(),
            measurement.input_bytes,
            measurement.inflated_bytes,
            measurement.total_ns,
            measurement.inflate_ns,
            measurement.proto_ns,
            measurement.zip_metadata_ns,
            measurement.model_ns,
            measurement.destroy_ns,
            measurement.checksum,
        },
    );
}
