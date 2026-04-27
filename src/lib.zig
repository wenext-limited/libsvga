const std = @import("std");

pub const model = @import("model.zig");
pub const core = @import("core.zig");
pub const c_api = @import("c_api.zig");
pub const parser = @import("parser.zig");

pub const Movie = model.Movie;
pub const MovieInfo = model.MovieInfo;
pub const ParseFileOptions = core.ParseFileOptions;
pub const default_max_input_bytes = core.default_max_input_bytes;
pub const parseMovie = core.parseMovie;
pub const parseMovieFile = core.parseMovieFile;
pub const destroyMovie = core.destroyMovie;

test {
    std.testing.refAllDeclsRecursive(@This());
}
