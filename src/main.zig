const std = @import("std");
const testing = std.testing;

const ParserError = struct { index: usize, expected: []const u8 };

fn MappedParser(comptime mapper: anytype) type {
    const fn_info = @typeInfo(@TypeOf(mapper)).@"fn";
    const ReturnType = fn_info.return_type.?;

    return struct {
        parser: Parser,
        const Self = @This();

        pub fn parse(self: Self, allocator: std.mem.Allocator, state: *ParserState) !ReturnType {
            const result_start = state.result.items.len;

            try self.parser.parse(allocator, state);
            const results = state.result.items[result_start..];

            return mapper(results);
        }

        pub fn run(self: Self, allocator: std.mem.Allocator, input: []const u8) !ReturnType {
            var state = ParserState.init(input);
            defer state.deinit(allocator);

            return try self.parse(allocator, &state);
        }
    };
}

fn ChainedParser(comptime chainer: anytype) type {
    return struct {
        parser: Parser,

        const Self = @This();

        pub fn parse(self: Self, allocator: std.mem.Allocator, state: *ParserState) anyerror!void {
            const result_start = state.result.items.len;
            //
            // workfloow
            // run the first parser -> use the results only by THAT PARSER -> pass them into chain callback -> use those results in the chainer
            // -> continue parsing
            //
            try self.parser.parse(allocator, state);
            const results = state.result.items[result_start..];
            const next_parser = chainer(results);
            try next_parser.parse(allocator, state);
        }

        pub fn run(self: Self, allocator: std.mem.Allocator, input: []const u8) !ParserState {
            var state = ParserState.init(input);
            // clean this up ONLY if you fail.
            errdefer state.deinit(allocator);

            try self.parse(allocator, &state);
            return state;
        }
    };
}

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
    choice: []const Parser,
    many: []const Parser,
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

            .choice => |parsers| {
                const orig_index = state.index;
                const orig_result_len = state.result.items.len;

                for (parsers) |parser| {
                    state.index = orig_index;
                    state.result.items.len = orig_result_len;
                    state.parse_error = null;
                    if (parser.parse(allocator, state)) |_| {
                        return;
                    } else |_| {}
                }

                return error.CouldNotMatch;
            },

            .many => |parsers| {
                while (true) {
                    const original_index = state.index;
                    const original_result_len = state.result.items.len;
                    const original_error = state.parse_error;

                    var match = true;

                    for (parsers) |parser| {
                        parser.parse(allocator, state) catch |err| {
                            if (err == error.CouldNotMatch or err == error.LengthTooBig) {
                                match = false;
                                break;
                            }

                            return err;
                        };
                    }

                    if (!match) {
                        state.index = original_index;
                        state.result.items.len = original_result_len;
                        state.parse_error = original_error;

                        break;
                    }

                    if (state.index == original_index) {
                        return error.ParserDidNotConsumeInput;
                    }
                }
            },
        }
    }

    pub fn map(self: Parser, comptime mapper: anytype) MappedParser(mapper) {
        return .{ .parser = self };
    }

    pub fn chain(self: Parser, comptime chainer: anytype) ChainedParser(chainer) {
        return .{ .parser = self };
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

fn choice(parsers: []const Parser) Parser {
    return .{ .choice = parsers };
}

fn many(parsers: []const Parser) Parser {
    return .{ .many = parsers };
}
fn digitsN(n: usize) Parser {
    return .{ .digits = n };
}

fn sequence(parsers: []const Parser) Parser {
    return .{ .sequence = parsers };
}

pub fn main() !void {
    std.debug.print("run `zig test src/main.zig`\n", .{});
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

test "choice test" {
    var state = ParserState.init("hello nam");
    defer state.deinit(testing.allocator);

    const parser = sequence(&.{
        str("hello "),
        choice(&.{
            str("world"),
            str("zig"),
            lettersN(3),
        }),
    });

    try parser.parse(testing.allocator, &state);
    try testing.expectEqualStrings("nam", state.result.items[1]);
}

test "many test" {
    var state = ParserState.init("hahahaha!");
    defer state.deinit(testing.allocator);

    const parser = sequence(&.{
        many(&.{
            str("ha"),
        }),
        str("!"),
    });

    try parser.parse(testing.allocator, &state);
}

fn extract_html_tag(results: []const []const u8) []const u8 {
    return results[1];
}

test "extract html tags" {
    const parser = sequence(&.{ str("<"), letters(), str(">") }).map(extract_html_tag);

    const result = try parser.run(
        std.testing.allocator,
        "<html>",
    );

    try std.testing.expectEqualStrings("html", result);
}

const SelectStatement = struct {
    column: []const u8,
    table: []const u8,
};

fn extract_into_select(results: []const []const u8) SelectStatement {
    return .{
        .column = results[1],
        .table = results[3],
    };
}

test "extract into select statement" {
    const parser = sequence(&.{ str("SELECT "), letters(), str(" FROM "), letters(), str(";") })
        .map(extract_into_select);

    const result: SelectStatement = try parser.run(
        std.testing.allocator,
        "SELECT name FROM users;",
    );

    try std.testing.expectEqualStrings("name", result.column);
}

fn parse_based_on_value(results: []const []const u8) Parser {
    const kind = results[0];
    if (std.mem.eql(u8, kind, "word")) {
        return sequence(&.{ str(":"), letters() });
    }
    return sequence(&.{ str(":"), digits() });
}

test "chainer" {
    const parser = choice(&.{ str("word"), str("number") }).chain(parse_based_on_value);

    var state = try parser.run(testing.allocator, "word:hello");
    defer state.deinit(testing.allocator);

    try std.testing.expectEqualStrings("word", state.result.items[0]);
    try std.testing.expectEqualStrings("hello", state.result.items[2]);
}
