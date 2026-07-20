const std = @import("std");

const Pattern = union(enum) {
    str: []const u8,
};

const ParserState = struct {
    target_string: []const u8,
    result: std.ArrayList([]const u8),
    index: usize = 0,

    fn init(target_string: []const u8) ParserState {
        return .{
            .target_string = target_string,
            .result = .empty,
        };
    }

    fn sequence(self: ParserState, patterns: []const Pattern, allocator: std.mem.Allocator) !?ParserState {
        var state = self;
        for (patterns) |pattern| {
            state = switch (pattern) {
                .str => |s| try state.parse_str(s, allocator),
            } orelse return null;
        }

        return state;
    }

    fn parse_str(self: ParserState, s: []const u8, allocator: std.mem.Allocator) !?ParserState {
        const remaining = self.target_string[self.index..];

        if (!std.mem.startsWith(u8, remaining, s))
            return null;

        var state = self;
        try state.result.append(allocator, s);

        state.index += s.len;
        return state;
    }
};

fn str(s: []const u8) Pattern {
    return .{ .str = s };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const p = ParserState.init("hi there");

    const patterns = [_]Pattern{
        str("hi"),
        str(" "),
        str("there"),
    };

    const res = try p.sequence(&patterns, allocator);

    if (res) |r| {
        std.debug.print("matched: {s}\nindex: {d}\n", .{ r.target_string[0..r.index], r.index });
        std.debug.print("{d}\n", .{res.?.result.items.len});

        for (res.?.result.items) |v| {
            std.debug.print("{s}\n", .{v});
        }
    } else {
        std.debug.print("failed to match pattern\n", .{});
    }
}
