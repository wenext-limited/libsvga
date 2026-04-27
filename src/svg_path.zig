const std = @import("std");

pub const CommandType = enum(i32) {
    move = 0,
    line = 1,
    quad = 2,
    cubic = 3,
    close = 4,
};

pub const Command = extern struct {
    command_type: i32 = @intFromEnum(CommandType.move),
    p0_x: f32 = 0,
    p0_y: f32 = 0,
    p1_x: f32 = 0,
    p1_y: f32 = 0,
    p2_x: f32 = 0,
    p2_y: f32 = 0,
};

const Point = struct {
    x: f32 = 0,
    y: f32 = 0,

    fn relative(self: Point, x: f32, y: f32, is_relative: bool) Point {
        if (!is_relative) return .{ .x = x, .y = y };
        return .{ .x = self.x + x, .y = self.y + y };
    }

    fn reflectedControl(self: Point, control: ?Point) Point {
        const previous = control orelse return self;
        return .{
            .x = self.x * 2 - previous.x,
            .y = self.y * 2 - previous.y,
        };
    }
};

pub fn parse(allocator: std.mem.Allocator, data: []const u8) ![]Command {
    var parser = Parser{ .data = data };
    var commands: std.ArrayList(Command) = .empty;
    errdefer commands.deinit(allocator);

    var current: Point = .{};
    var subpath_start: Point = .{};
    var active_command: u8 = 0;
    var last_cubic_control: ?Point = null;
    var last_quad_control: ?Point = null;

    while (true) {
        parser.skipSeparators();
        if (parser.isDone()) break;

        if (isCommandChar(parser.peek())) {
            active_command = parser.read();
            if (isCloseCommand(active_command)) {
                try commands.append(allocator, .{
                    .command_type = @intFromEnum(CommandType.close),
                });
                current = subpath_start;
                active_command = 0;
                last_cubic_control = null;
                last_quad_control = null;
                continue;
            }
        } else if (active_command == 0) {
            parser.index += 1;
            continue;
        }

        const relative = std.ascii.isLower(active_command);
        switch (std.ascii.toLower(active_command)) {
            'm' => {
                var first_pair = true;
                while (true) {
                    const x = parser.nextNumber() orelse break;
                    const y = parser.nextNumber() orelse break;
                    const next = current.relative(x, y, relative);
                    if (first_pair) {
                        try commands.append(allocator, .{
                            .command_type = @intFromEnum(CommandType.move),
                            .p0_x = next.x,
                            .p0_y = next.y,
                        });
                        subpath_start = next;
                        first_pair = false;
                    } else {
                        try commands.append(allocator, .{
                            .command_type = @intFromEnum(CommandType.line),
                            .p0_x = next.x,
                            .p0_y = next.y,
                        });
                    }
                    current = next;
                    last_cubic_control = null;
                    last_quad_control = null;
                }
            },
            'l' => {
                while (true) {
                    const x = parser.nextNumber() orelse break;
                    const y = parser.nextNumber() orelse break;
                    const next = current.relative(x, y, relative);
                    try commands.append(allocator, .{
                        .command_type = @intFromEnum(CommandType.line),
                        .p0_x = next.x,
                        .p0_y = next.y,
                    });
                    current = next;
                    last_cubic_control = null;
                    last_quad_control = null;
                }
            },
            'h' => {
                while (parser.nextNumber()) |x| {
                    const next_x = if (relative) current.x + x else x;
                    current = .{ .x = next_x, .y = current.y };
                    try commands.append(allocator, .{
                        .command_type = @intFromEnum(CommandType.line),
                        .p0_x = current.x,
                        .p0_y = current.y,
                    });
                    last_cubic_control = null;
                    last_quad_control = null;
                }
            },
            'v' => {
                while (parser.nextNumber()) |y| {
                    const next_y = if (relative) current.y + y else y;
                    current = .{ .x = current.x, .y = next_y };
                    try commands.append(allocator, .{
                        .command_type = @intFromEnum(CommandType.line),
                        .p0_x = current.x,
                        .p0_y = current.y,
                    });
                    last_cubic_control = null;
                    last_quad_control = null;
                }
            },
            'c' => {
                while (true) {
                    const x1 = parser.nextNumber() orelse break;
                    const y1 = parser.nextNumber() orelse break;
                    const x2 = parser.nextNumber() orelse break;
                    const y2 = parser.nextNumber() orelse break;
                    const x = parser.nextNumber() orelse break;
                    const y = parser.nextNumber() orelse break;
                    const c1 = current.relative(x1, y1, relative);
                    const c2 = current.relative(x2, y2, relative);
                    const end = current.relative(x, y, relative);
                    try commands.append(allocator, .{
                        .command_type = @intFromEnum(CommandType.cubic),
                        .p0_x = c1.x,
                        .p0_y = c1.y,
                        .p1_x = c2.x,
                        .p1_y = c2.y,
                        .p2_x = end.x,
                        .p2_y = end.y,
                    });
                    current = end;
                    last_cubic_control = c2;
                    last_quad_control = null;
                }
            },
            's' => {
                while (true) {
                    const x2 = parser.nextNumber() orelse break;
                    const y2 = parser.nextNumber() orelse break;
                    const x = parser.nextNumber() orelse break;
                    const y = parser.nextNumber() orelse break;
                    const c1 = current.reflectedControl(last_cubic_control);
                    const c2 = current.relative(x2, y2, relative);
                    const end = current.relative(x, y, relative);
                    try commands.append(allocator, .{
                        .command_type = @intFromEnum(CommandType.cubic),
                        .p0_x = c1.x,
                        .p0_y = c1.y,
                        .p1_x = c2.x,
                        .p1_y = c2.y,
                        .p2_x = end.x,
                        .p2_y = end.y,
                    });
                    current = end;
                    last_cubic_control = c2;
                    last_quad_control = null;
                }
            },
            'q' => {
                while (true) {
                    const x1 = parser.nextNumber() orelse break;
                    const y1 = parser.nextNumber() orelse break;
                    const x = parser.nextNumber() orelse break;
                    const y = parser.nextNumber() orelse break;
                    const control = current.relative(x1, y1, relative);
                    const end = current.relative(x, y, relative);
                    try commands.append(allocator, .{
                        .command_type = @intFromEnum(CommandType.quad),
                        .p0_x = control.x,
                        .p0_y = control.y,
                        .p1_x = end.x,
                        .p1_y = end.y,
                    });
                    current = end;
                    last_cubic_control = null;
                    last_quad_control = control;
                }
            },
            't' => {
                while (true) {
                    const x = parser.nextNumber() orelse break;
                    const y = parser.nextNumber() orelse break;
                    const control = current.reflectedControl(last_quad_control);
                    const end = current.relative(x, y, relative);
                    try commands.append(allocator, .{
                        .command_type = @intFromEnum(CommandType.quad),
                        .p0_x = control.x,
                        .p0_y = control.y,
                        .p1_x = end.x,
                        .p1_y = end.y,
                    });
                    current = end;
                    last_cubic_control = null;
                    last_quad_control = control;
                }
            },
            else => {
                parser.skipUntilNextCommand();
                last_cubic_control = null;
                last_quad_control = null;
            },
        }
    }

    return commands.toOwnedSlice(allocator);
}

fn isCommandChar(char: u8) bool {
    return switch (char) {
        'M',
        'm',
        'Z',
        'z',
        'L',
        'l',
        'H',
        'h',
        'V',
        'v',
        'C',
        'c',
        'S',
        's',
        'Q',
        'q',
        'T',
        't',
        'A',
        'a',
        => true,
        else => false,
    };
}

fn isCloseCommand(char: u8) bool {
    return char == 'Z' or char == 'z';
}

const Parser = struct {
    data: []const u8,
    index: usize = 0,

    fn isDone(self: *const Parser) bool {
        return self.index >= self.data.len;
    }

    fn peek(self: *const Parser) u8 {
        return self.data[self.index];
    }

    fn read(self: *Parser) u8 {
        const char = self.data[self.index];
        self.index += 1;
        return char;
    }

    fn skipSeparators(self: *Parser) void {
        while (!self.isDone()) {
            const char = self.peek();
            if (char != ',' and !std.ascii.isWhitespace(char)) break;
            self.index += 1;
        }
    }

    fn skipUntilNextCommand(self: *Parser) void {
        while (!self.isDone()) {
            if (isCommandChar(self.peek())) break;
            self.index += 1;
        }
    }

    fn nextNumber(self: *Parser) ?f32 {
        self.skipSeparators();
        if (self.isDone() or !isNumberStart(self.peek())) return null;

        const start = self.index;
        if (self.peek() == '+' or self.peek() == '-') self.index += 1;

        var saw_digit = false;
        while (!self.isDone() and std.ascii.isDigit(self.peek())) {
            saw_digit = true;
            self.index += 1;
        }

        if (!self.isDone() and self.peek() == '.') {
            self.index += 1;
            while (!self.isDone() and std.ascii.isDigit(self.peek())) {
                saw_digit = true;
                self.index += 1;
            }
        }

        if (!saw_digit) {
            self.index = start;
            return null;
        }

        const before_exponent = self.index;
        if (!self.isDone() and (self.peek() == 'e' or self.peek() == 'E')) {
            self.index += 1;
            if (!self.isDone() and (self.peek() == '+' or self.peek() == '-')) self.index += 1;

            const exponent_start = self.index;
            while (!self.isDone() and std.ascii.isDigit(self.peek())) {
                self.index += 1;
            }
            if (self.index == exponent_start) {
                self.index = before_exponent;
            }
        }

        return std.fmt.parseFloat(f32, self.data[start..self.index]) catch null;
    }
};

fn isNumberStart(char: u8) bool {
    return char == '+' or char == '-' or char == '.' or std.ascii.isDigit(char);
}

test "SVG path parser lowers commands to absolute geometry" {
    const commands = try parse(
        std.testing.allocator,
        "M10 20 l5,-5 H30 v10 q1 2 3 4 c1 2 3 4 5 6 z",
    );
    defer std.testing.allocator.free(commands);

    try std.testing.expectEqual(@as(usize, 7), commands.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(CommandType.move)), commands[0].command_type);
    try std.testing.expectEqual(@as(f32, 10), commands[0].p0_x);
    try std.testing.expectEqual(@as(f32, 20), commands[0].p0_y);
    try std.testing.expectEqual(@as(i32, @intFromEnum(CommandType.line)), commands[1].command_type);
    try std.testing.expectEqual(@as(f32, 15), commands[1].p0_x);
    try std.testing.expectEqual(@as(f32, 15), commands[1].p0_y);
    try std.testing.expectEqual(@as(f32, 30), commands[2].p0_x);
    try std.testing.expectEqual(@as(f32, 15), commands[2].p0_y);
    try std.testing.expectEqual(@as(f32, 30), commands[3].p0_x);
    try std.testing.expectEqual(@as(f32, 25), commands[3].p0_y);
    try std.testing.expectEqual(@as(i32, @intFromEnum(CommandType.quad)), commands[4].command_type);
    try std.testing.expectEqual(@as(f32, 31), commands[4].p0_x);
    try std.testing.expectEqual(@as(f32, 27), commands[4].p0_y);
    try std.testing.expectEqual(@as(f32, 33), commands[4].p1_x);
    try std.testing.expectEqual(@as(f32, 29), commands[4].p1_y);
    try std.testing.expectEqual(@as(i32, @intFromEnum(CommandType.cubic)), commands[5].command_type);
    try std.testing.expectEqual(@as(f32, 34), commands[5].p0_x);
    try std.testing.expectEqual(@as(f32, 31), commands[5].p0_y);
    try std.testing.expectEqual(@as(f32, 38), commands[5].p2_x);
    try std.testing.expectEqual(@as(f32, 35), commands[5].p2_y);
    try std.testing.expectEqual(@as(i32, @intFromEnum(CommandType.close)), commands[6].command_type);
}

test "SVG path parser handles compact numbers and smooth curves" {
    const commands = try parse(std.testing.allocator, "M.5.6 1-2 C0 0 10 10 20 20 s5 5 10 10 T40 40");
    defer std.testing.allocator.free(commands);

    try std.testing.expectEqual(@as(usize, 5), commands.len);
    try std.testing.expectEqual(@as(f32, 0.5), commands[0].p0_x);
    try std.testing.expectEqual(@as(f32, 0.6), commands[0].p0_y);
    try std.testing.expectEqual(@as(i32, @intFromEnum(CommandType.line)), commands[1].command_type);
    try std.testing.expectEqual(@as(f32, 1), commands[1].p0_x);
    try std.testing.expectEqual(@as(f32, -2), commands[1].p0_y);
    try std.testing.expectEqual(@as(i32, @intFromEnum(CommandType.cubic)), commands[3].command_type);
    try std.testing.expectEqual(@as(f32, 30), commands[3].p0_x);
    try std.testing.expectEqual(@as(f32, 30), commands[3].p0_y);
    try std.testing.expectEqual(@as(i32, @intFromEnum(CommandType.quad)), commands[4].command_type);
    try std.testing.expectEqual(@as(f32, 30), commands[4].p0_x);
    try std.testing.expectEqual(@as(f32, 30), commands[4].p0_y);
    try std.testing.expectEqual(@as(f32, 40), commands[4].p1_x);
    try std.testing.expectEqual(@as(f32, 40), commands[4].p1_y);
}
