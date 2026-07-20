const std = @import("std");

const ParserState = struct {
    target_string: []const u8,
    result: ?[]const u8,
    index: usize,
};

fn new_parser(target_string: []const u8) ParserState {
    return .{ .target_string = target_string, .index = 0, .result = null };
}

fn str(parser: ParserState, s: []const u8) !ParserState {
    if (std.mem.startsWith(u8, parser.target_string, s)) {
        return .{ .target_string = parser.target_string, .result = s, .index = parser.index + s.len };
    }
    return error.CouldNotMatch;
}

const ParseFunc = fn (ParserState, []const u8) ParserState;

fn sequence(parser: ParserState, funcs: []ParseFunc) !ParserState {
    const results = []ParserState;

    var next_state = parser;
    for (funcs) |f| {
        next_state = f(parser);
        results.add(f);
    }

    return .{ .index = parser.index, .result = results, .target_string = parser.target_string };
}

pub fn main() !void {
    const p = new_parser("hello this is big text corpus");
    const res = try str(p, "hello");
    std.debug.print("target_string = {s}\nresult = {s}\nindex = {d}", .{ res.target_string, res.result.?, res.index });
}
