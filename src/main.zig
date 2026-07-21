const std = @import("std");

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
    // digits: ?usize,

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
                    if (start + n >= state.target_string.len) {
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
        }
    }
};

fn str(s: []const u8) Parser {
    return .{ .string = s };
}

fn letters() Parser {
    return .{ .letters = null };
}

fn sequence(parsers: []const Parser) Parser {
    return .{ .sequence = parsers };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var state = ParserState.init("hello big world");
    defer state.deinit(allocator);

    const parser = sequence(&.{
        str("hello"),
        sequence(&.{
            str(" "),
            letters(),
            str(" "),
        }),
        str("world"),
    });

    parser.parse(allocator, &state) catch |err| {
        if (err == error.CouldNotMatch) {
            if (state.parse_error) |parse_error| {
                std.debug.print("Parse error at index {d}: expected '{s}'\n", .{ parse_error.index, parse_error.expected });
            }
            return;
        }
        return err;
    };

    std.debug.print("index: {d}\n", .{state.index});

    for (state.result.items) |result| {
        std.debug.print("matched: '{s}'\n", .{result});
    }
}
