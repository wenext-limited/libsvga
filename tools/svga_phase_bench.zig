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
    model_mode: ModelMode = .full,
    alloc_stats: bool = false,
    tsv_path: ?[]const u8 = null,
};

const ModelMode = enum {
    full,
    no_paths,
    no_render,
    metadata_only,
    copy_only,
    parse_only,

    fn label(self: ModelMode) []const u8 {
        return switch (self) {
            .full => "full",
            .no_paths => "no-paths",
            .no_render => "no-render",
            .metadata_only => "metadata-only",
            .copy_only => "copy-only",
            .parse_only => "parse-only",
        };
    }

    fn initOptions(self: ModelMode) libsvga.model.MovieInitOptions {
        return switch (self) {
            .full => .{},
            .no_paths => .{ .build_path_commands = false },
            .no_render => .{
                .build_render_data = false,
                .build_visual_frame_indices = false,
            },
            .metadata_only => .{
                .build_path_commands = false,
                .build_render_data = false,
                .build_visual_frame_indices = false,
            },
            .copy_only => .{
                .build_metadata_tables = false,
                .build_path_commands = false,
                .build_render_data = false,
                .build_visual_frame_indices = false,
            },
            .parse_only => unreachable,
        };
    }
};

const Fixture = struct {
    path: []const u8,
    bytes: []u8,
};

const AllocationStats = struct {
    alloc_count: usize = 0,
    resize_count: usize = 0,
    remap_count: usize = 0,
    free_count: usize = 0,
    alloc_bytes: usize = 0,
    freed_bytes: usize = 0,
    live_bytes: usize = 0,
    peak_live_bytes: usize = 0,

    fn add(self: *AllocationStats, other: AllocationStats) void {
        self.alloc_count += other.alloc_count;
        self.resize_count += other.resize_count;
        self.remap_count += other.remap_count;
        self.free_count += other.free_count;
        self.alloc_bytes += other.alloc_bytes;
        self.freed_bytes += other.freed_bytes;
        self.live_bytes += other.live_bytes;
        self.peak_live_bytes += other.peak_live_bytes;
    }

    fn noteAlloc(self: *AllocationStats, len: usize) void {
        self.alloc_count += 1;
        self.alloc_bytes += len;
        self.live_bytes += len;
        self.peak_live_bytes = @max(self.peak_live_bytes, self.live_bytes);
    }

    fn noteResize(self: *AllocationStats, old_len: usize, new_len: usize) void {
        self.resize_count += 1;
        self.noteSizeChange(old_len, new_len);
    }

    fn noteRemap(self: *AllocationStats, old_len: usize, new_len: usize) void {
        self.remap_count += 1;
        self.noteSizeChange(old_len, new_len);
    }

    fn noteSizeChange(self: *AllocationStats, old_len: usize, new_len: usize) void {
        if (new_len > old_len) {
            const delta = new_len - old_len;
            self.alloc_bytes += delta;
            self.live_bytes += delta;
        } else {
            const delta = old_len - new_len;
            self.freed_bytes += delta;
            self.live_bytes -|= delta;
        }
        self.peak_live_bytes = @max(self.peak_live_bytes, self.live_bytes);
    }

    fn noteFree(self: *AllocationStats, len: usize) void {
        self.free_count += 1;
        self.freed_bytes += len;
        self.live_bytes -|= len;
    }
};

const CountingAllocator = struct {
    child: std.mem.Allocator,
    stats: AllocationStats = .{},

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.stats.noteAlloc(len);
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.stats.noteResize(memory.len, new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.stats.noteRemap(memory.len, new_len);
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
        self.stats.noteFree(memory.len);
    }
};

const Measurement = struct {
    container: ContainerKind,
    model_mode: ModelMode = .full,
    input_bytes: usize = 0,
    inflated_bytes: usize = 0,
    total_ns: u64 = 0,
    inflate_ns: u64 = 0,
    proto_ns: u64 = 0,
    zip_metadata_ns: u64 = 0,
    model_ns: u64 = 0,
    destroy_ns: u64 = 0,
    checksum: u64 = 0,
    allocation_stats: AllocationStats = .{},
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
    allocation_stats: AllocationStats = .{},

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
        self.allocation_stats.add(measurement.allocation_stats);
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
        } else if (std.mem.eql(u8, arg, "--model-mode")) {
            config.model_mode = try parseModelMode(args.next() orelse return error.MissingOptionValue);
        } else if (std.mem.eql(u8, arg, "--alloc-stats")) {
            config.alloc_stats = true;
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

fn parseModelMode(value: []const u8) !ModelMode {
    inline for (@typeInfo(ModelMode).@"enum".fields) |field| {
        const mode: ModelMode = @enumFromInt(field.value);
        if (std.mem.eql(u8, value, mode.label())) return mode;
    }
    std.debug.print("unknown model mode: {s}\n", .{value});
    return error.InvalidOptionValue;
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
        \\  --model-mode MODE     full, no-paths, no-render, metadata-only, copy-only, parse-only
        \\  --alloc-stats         count allocator calls and backing bytes
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
            const measurement = measureFixture(fixture, config) catch |err| {
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

fn measureFixture(fixture: Fixture, config: Config) !Measurement {
    if (!config.alloc_stats) {
        return measureFixtureWithAllocator(allocator, fixture, config);
    }

    var counting_allocator = CountingAllocator{ .child = allocator };
    const measured_allocator = counting_allocator.allocator();
    var measurement = try measureFixtureWithAllocator(measured_allocator, fixture, config);
    measurement.allocation_stats = counting_allocator.stats;
    return measurement;
}

fn measureFixtureWithAllocator(measured_allocator: std.mem.Allocator, fixture: Fixture, config: Config) !Measurement {
    const total_start = timestamp();
    var result = Measurement{
        .container = undefined,
        .model_mode = config.model_mode,
        .input_bytes = fixture.bytes.len,
    };

    if (libsvga.parser.isZip(fixture.bytes)) {
        result.container = .zip;

        const metadata_start = timestamp();
        var metadata = try libsvga.parser.parseMovieMetadataWithOptions(measured_allocator, fixture.bytes, .{
            .max_output_bytes = config.max_output_bytes,
        });
        result.zip_metadata_ns = elapsedSince(metadata_start);
        defer metadata.deinit(measured_allocator);

        if (config.model_mode == .parse_only) {
            result.checksum = checksumSpec(metadata.spec);
        } else {
            const model_start = timestamp();
            var movie = try libsvga.model.Movie.initWithOptions(measured_allocator, metadata.spec, config.model_mode.initOptions());
            result.model_ns = elapsedSince(model_start);

            result.checksum = checksumMovie(&movie);
            const destroy_start = timestamp();
            movie.deinit(measured_allocator);
            result.destroy_ns = elapsedSince(destroy_start);
        }
    } else {
        if (!libsvga.parser.isZlibStream(fixture.bytes)) return error.InvalidData;
        result.container = .zlib;

        const inflate_start = timestamp();
        const inflated = try libsvga.parser.inflateZlibForBenchmark(measured_allocator, fixture.bytes, config.max_output_bytes);
        result.inflate_ns = elapsedSince(inflate_start);
        result.inflated_bytes = inflated.len;
        defer measured_allocator.free(inflated);

        var arena = std.heap.ArenaAllocator.init(measured_allocator);
        defer arena.deinit();

        const proto_start = timestamp();
        const spec = try libsvga.parser.parseMovieProto(arena.allocator(), inflated);
        result.proto_ns = elapsedSince(proto_start);

        if (config.model_mode == .parse_only) {
            result.checksum = checksumSpec(spec);
        } else {
            const model_start = timestamp();
            var movie = try libsvga.model.Movie.initWithOptions(measured_allocator, spec, config.model_mode.initOptions());
            result.model_ns = elapsedSince(model_start);

            result.checksum = checksumMovie(&movie);
            const destroy_start = timestamp();
            movie.deinit(measured_allocator);
            result.destroy_ns = elapsedSince(destroy_start);
        }
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

fn checksumSpec(spec: libsvga.model.MovieSpec) u64 {
    var checksum: u64 = 0;
    checksum +%= @intCast(spec.frames);
    checksum +%= spec.image_count;
    checksum +%= spec.sprite_count;
    checksum +%= spec.audio_count;
    checksum +%= spec.assets.len;
    checksum +%= spec.sprites.len;
    checksum +%= spec.audios.len;
    for (spec.sprites) |sprite| {
        checksum +%= sprite.frames.len;
        for (sprite.frames) |frame| {
            checksum +%= frame.shapes.len;
        }
    }
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
    stdout.print(
        "model_mode={s} alloc_stats={}\n",
        .{ config.model_mode.label(), config.alloc_stats },
    );
    printPhase("inflate", totals.inflate_ns, totals);
    printPhase("protobuf", totals.proto_ns, totals);
    printPhase("zip_metadata", totals.zip_metadata_ns, totals);
    printPhase("model_init", totals.model_ns, totals);
    printPhase("destroy", totals.destroy_ns, totals);
    const accounted = totals.inflate_ns + totals.proto_ns + totals.zip_metadata_ns + totals.model_ns + totals.destroy_ns;
    printPhase("unaccounted", totals.total_ns -| accounted, totals);
    if (config.alloc_stats) {
        printAllocationStats(totals);
    }
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

fn printAllocationStats(totals: Totals) void {
    const stats = totals.allocation_stats;
    std.debug.print(
        "allocations allocs_per_parse={d:.1} resizes_per_parse={d:.1} remaps_per_parse={d:.1} frees_per_parse={d:.1} alloc_bytes_per_parse={d:.1} peak_live_bytes_per_parse={d:.1}\n",
        .{
            countPerParse(stats.alloc_count, totals.parses),
            countPerParse(stats.resize_count, totals.parses),
            countPerParse(stats.remap_count, totals.parses),
            countPerParse(stats.free_count, totals.parses),
            countPerParse(stats.alloc_bytes, totals.parses),
            countPerParse(stats.peak_live_bytes, totals.parses),
        },
    );
}

fn countPerParse(count: usize, parses: usize) f64 {
    if (parses == 0) return 0;
    return @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(parses));
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
        "iteration\tpath\tcontainer\tmodel_mode\tinput_bytes\tinflated_bytes\ttotal_ns\tinflate_ns\tprotobuf_ns\tzip_metadata_ns\tmodel_init_ns\tdestroy_ns\tchecksum\talloc_count\tresize_count\tremap_count\tfree_count\talloc_bytes\tpeak_live_bytes\n",
    );
}

fn writeTsvRow(writer: *std.Io.Writer, iteration: usize, fixture: Fixture, measurement: Measurement) !void {
    try writer.print(
        "{}\t{s}\t{s}\t{s}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
        .{
            iteration,
            fixture.path,
            measurement.container.label(),
            measurement.model_mode.label(),
            measurement.input_bytes,
            measurement.inflated_bytes,
            measurement.total_ns,
            measurement.inflate_ns,
            measurement.proto_ns,
            measurement.zip_metadata_ns,
            measurement.model_ns,
            measurement.destroy_ns,
            measurement.checksum,
            measurement.allocation_stats.alloc_count,
            measurement.allocation_stats.resize_count,
            measurement.allocation_stats.remap_count,
            measurement.allocation_stats.free_count,
            measurement.allocation_stats.alloc_bytes,
            measurement.allocation_stats.peak_live_bytes,
        },
    );
}
