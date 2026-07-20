const std = @import("std");

const ParserState = struct {
    target_string: []const u8,
    result: ?[]const u8,
    index: usize,

    fn init(target_string: []const u8) ParserState {
        return .{ .target_string = target_string, .index = 0, .result = null };
    }

    fn str(self: ParserState, s: []const u8) ParserState {
        if (std.mem.startsWith(u8, self.target_string, s)) {
            return .{ .target_string = self.target_string, .result = s, .index = self.index + s.len };
        }
        return self;
    }
};

pub fn main() !void {
    var p = ParserState.init("hello this is big text corpus");
    const res = p.str("hello");
    std.debug.print("target_string = {s}\nresult = {s}\nindex = {d}", .{ res.target_string, res.result.?, res.index });
}
