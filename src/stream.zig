const std = @import("std");
const cfg = @import("config.zig");

pub const StreamBundle = struct {
    current_tokens: []u8,
    next_tokens: []u8,
    segments: []u8,
    reset_before: []u8,
    segment_offsets: [cfg.max_segments]usize = [_]usize{0} ** cfg.max_segments,
    segment_lengths: [cfg.max_segments]usize = [_]usize{0} ** cfg.max_segments,
    segment_count: u8,

    pub fn deinit(self: StreamBundle, allocator: std.mem.Allocator) void {
        allocator.free(self.current_tokens);
        allocator.free(self.next_tokens);
        allocator.free(self.segments);
        allocator.free(self.reset_before);
    }

    pub fn predictionsLen(self: StreamBundle) usize {
        return self.current_tokens.len;
    }
};

pub fn loadCorpus(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(200_000_000));
}

pub fn buildPrefixBundle(allocator: std.mem.Allocator, corpus: []const u8, corpus_cfg: cfg.CorpusConfig) !StreamBundle {
    const total_predictions = corpus_cfg.totalPredictions();
    if (corpus.len < total_predictions + 1) return error.CorpusTooSmall;

    const current_tokens = try allocator.alloc(u8, total_predictions);
    errdefer allocator.free(current_tokens);
    const next_tokens = try allocator.alloc(u8, total_predictions);
    errdefer allocator.free(next_tokens);
    @memcpy(current_tokens, corpus[0..total_predictions]);
    @memcpy(next_tokens, corpus[1 .. total_predictions + 1]);

    var segments = try allocator.alloc(u8, total_predictions);
    errdefer allocator.free(segments);
    const reset_before = try allocator.alloc(u8, total_predictions);
    errdefer allocator.free(reset_before);
    @memset(reset_before, 0);

    var segment_offsets = [_]usize{0} ** cfg.max_segments;
    var segment_lengths = [_]usize{0} ** cfg.max_segments;
    const seg_count = corpus_cfg.segment_count;
    for (0..seg_count) |segment_idx| {
        const start = segment_idx * corpus_cfg.segment_len;
        const end = start + corpus_cfg.segment_len;
        segment_offsets[segment_idx] = start;
        segment_lengths[segment_idx] = corpus_cfg.segment_len;
        @memset(segments[start..end], @intCast(segment_idx));
        if (corpus_cfg.reset_on_segment_boundary and segment_idx != 0) reset_before[start] = 1;
    }

    return .{
        .current_tokens = current_tokens,
        .next_tokens = next_tokens,
        .segments = segments,
        .reset_before = reset_before,
        .segment_offsets = segment_offsets,
        .segment_lengths = segment_lengths,
        .segment_count = seg_count,
    };
}

pub fn buildDriftBundle(allocator: std.mem.Allocator, corpus: []const u8, corpus_cfg: cfg.CorpusConfig) !StreamBundle {
    const seg_count = corpus_cfg.segment_count;
    const total_predictions = corpus_cfg.totalPredictions();
    const offsets = corpus_cfg.driftOffsets();
    if (seg_count != 4) return error.DriftRequiresFourSegments;

    const current_tokens = try allocator.alloc(u8, total_predictions);
    errdefer allocator.free(current_tokens);
    const next_tokens = try allocator.alloc(u8, total_predictions);
    errdefer allocator.free(next_tokens);
    var segments = try allocator.alloc(u8, total_predictions);
    errdefer allocator.free(segments);
    const reset_before = try allocator.alloc(u8, total_predictions);
    errdefer allocator.free(reset_before);
    @memset(reset_before, 0);

    var segment_offsets = [_]usize{0} ** cfg.max_segments;
    var segment_lengths = [_]usize{0} ** cfg.max_segments;

    var out_index: usize = 0;
    for (0..seg_count) |segment_idx| {
        const source_offset = offsets[segment_idx];
        const needed = source_offset + corpus_cfg.segment_len + 1;
        if (needed > corpus.len) return error.CorpusTooSmall;
        const src_current = corpus[source_offset .. source_offset + corpus_cfg.segment_len];
        const src_next = corpus[source_offset + 1 .. source_offset + corpus_cfg.segment_len + 1];
        const start = out_index;
        const end = start + corpus_cfg.segment_len;
        @memcpy(current_tokens[start..end], src_current);
        @memcpy(next_tokens[start..end], src_next);
        @memset(segments[start..end], @intCast(segment_idx));
        if (segment_idx != 0) reset_before[start] = 1;
        segment_offsets[segment_idx] = source_offset;
        segment_lengths[segment_idx] = corpus_cfg.segment_len;
        out_index = end;
    }

    return .{
        .current_tokens = current_tokens,
        .next_tokens = next_tokens,
        .segments = segments,
        .reset_before = reset_before,
        .segment_offsets = segment_offsets,
        .segment_lengths = segment_lengths,
        .segment_count = seg_count,
    };
}

test "prefix bundle uses requested prediction length" {
    const allocator = std.testing.allocator;
    const corpus = try allocator.alloc(u8, 1024);
    defer allocator.free(corpus);
    for (corpus, 0..) |*byte, idx| byte.* = @intCast(idx % 256);

    const corpus_cfg = cfg.CorpusConfig{ .dataset_path = "", .segment_len = 100, .segment_count = 4 };
    const bundle = try buildPrefixBundle(allocator, corpus, corpus_cfg);
    defer bundle.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 400), bundle.predictionsLen());
    try std.testing.expectEqual(@as(u8, 4), bundle.segment_count);
}
