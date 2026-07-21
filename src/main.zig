const std = @import("std");
const testing = std.testing;

const ParserError = struct { index: usize, expected: []const u8 };

const ParserState = struct {
    target_string: []const u8,
    result: std.ArrayList([]const u8),
    index: usize = 0,
    parse_error: ?ParserError = null,

    fn init(target_string: []const u8) ParserState {
        return .{ .target_string = target_string, .result = .empty };
    }

    fn deinit(self: *ParserState, allocator: std.mem.Allocator) void {
        self.result.deinit(allocator);
    }

    fn setError(self: *ParserState, expected: []const u8) void {
        self.parse_error = .{
            .index = self.index,
            .expected = expected,
        };
    }
};

const Parser = union(enum) {
    string: []const u8,
    sequence: []const Parser,
    letters: ?usize,
    digits: ?usize,

    pub fn parse(self: Parser, allocator: std.mem.Allocator, state: *ParserState) anyerror!void {
        switch (self) {
            .string => |expected| {
                const remaining = state.target_string[state.index..];

                if (!std.mem.startsWith(u8, remaining, expected)) {
                    state.setError(expected);
                    return error.CouldNotMatch;
                }

                try state.result.append(allocator, expected);
                state.index += expected.len;
            },
            .sequence => |parsers| {
                for (parsers) |parser| {
                    try parser.parse(allocator, state);
                }
            },
            // generic parsers
            .letters => |size| {
                const start = state.index;

                if (size) |n| {
                    if (start + n > state.target_string.len) {
                        state.setError("n is overflowing");
                        return error.LengthTooBig;
                    }

                    const end = start + n;

                    for (state.target_string[start..end]) |char| {
                        if (!std.ascii.isAlphabetic(char)) {
                            state.setError("letters");
                            return error.CouldNotMatch;
                        }
                    }

                    state.index = end;
                } else {
                    while (state.index < state.target_string.len and std.ascii.isAlphabetic(state.target_string[state.index])) {
                        state.index += 1;
                    }

                    if (state.index == start) {
                        state.setError("letters");
                        return error.CouldNotMatch;
                    }
                }

                try state.result.append(allocator, state.target_string[start..state.index]);
            },

            .digits => |size| {
                const start = state.index;
                if (size) |n| {
                    if (start + n > state.target_string.len) {
                        state.setError("n is overflowing");
                        return error.LengthTooBig;
                    }

                    const end = start + n;

                    for (state.target_string[start..end]) |char| {
                        if (!std.ascii.isDigit(char)) {
                            state.setError("digits");
                            return error.CouldNotMatch;
                        }
                    }

                    state.index = end;
                } else {
                    while (state.index < state.target_string.len and std.ascii.isDigit(state.target_string[state.index])) {
                        state.index += 1;
                    }

                    if (state.index == start) {
                        state.setError("digits");
                        return error.CouldNotMatch;
                    }
                }

                try state.result.append(allocator, state.target_string[start..state.index]);
            },
        }
    }
};

fn str(s: []const u8) Parser {
    return .{ .string = s };
}

fn letters() Parser {
    return .{ .letters = null };
}

fn lettersN(n: usize) Parser {
    return .{ .letters = n };
}

fn digits() Parser {
    return .{ .digits = null };
}

fn digitsN(n: usize) Parser {
    return .{ .digits = n };
}

fn sequence(parsers: []const Parser) Parser {
    return .{ .sequence = parsers };
}

pub fn main() !void {
    std.debug.print("run `zig test src/main.zig`", .{});
}

test "basic str" {
    var state = ParserState.init("hello");
    defer state.deinit(testing.allocator);

    const parser = str("hello");

    try parser.parse(testing.allocator, &state);
    try testing.expectEqual(@as(usize, 5), state.index);
    try testing.expectEqual(@as(usize, 1), state.result.items.len);
    try testing.expectEqualStrings("hello", state.result.items[0]);
}

test "str mismatch" {
    var state = ParserState.init("bye");
    defer state.deinit(testing.allocator);

    try testing.expectError(
        error.CouldNotMatch,
        str("hello").parse(testing.allocator, &state),
    );
}

test "letters" {
    var state = ParserState.init("hello");
    defer state.deinit(testing.allocator);

    const parser = letters();

    try parser.parse(testing.allocator, &state);
    try testing.expectEqual(@as(usize, 5), state.index);
    try testing.expectEqualStrings("hello", state.result.items[0]);
}

test "letters n" {
    var state = ParserState.init("hello");
    defer state.deinit(testing.allocator);

    const parser = lettersN(5);

    try parser.parse(testing.allocator, &state);
    try testing.expectEqual(@as(usize, 5), state.index);
    try testing.expectEqualStrings("hello", state.result.items[0]);
}

test "digits" {
    var state = ParserState.init("1231");
    defer state.deinit(testing.allocator);

    const parser = digits();

    try parser.parse(testing.allocator, &state);
    try testing.expectEqual(@as(usize, 4), state.index);
    try testing.expectEqualStrings("1231", state.result.items[0]);
}

test "digits n" {
    var state = ParserState.init("12313211");
    defer state.deinit(testing.allocator);

    const parser = digitsN(8);

    try parser.parse(testing.allocator, &state);
    try testing.expectEqual(@as(usize, 8), state.index);
    try testing.expectEqualStrings("12313211", state.result.items[0]);
}

test "sequence" {
    var state = ParserState.init("hello big world 12");
    defer state.deinit(testing.allocator);

    const parser = sequence(&.{
        str("hello"),
        str(" "),
        lettersN(3),
        str(" "),
        str("world"),
        str(" "),
        digitsN(2),
    });

    try parser.parse(testing.allocator, &state);

    try testing.expectEqual(@as(usize, 18), state.index);
}
