const std = @import("std");
const cfg = @import("config.zig");
const stream = @import("stream.zig");
const network = @import("network.zig");

pub const ExperimentMeta = struct {
    name: []const u8,
    dataset_name: []const u8,
    mode: []const u8,
    protocol: []const u8,
    total_predictions: usize,
    segment_count: u8,
    segment_offsets: [cfg.max_segments]usize = [_]usize{0} ** cfg.max_segments,
    segment_lengths: [cfg.max_segments]usize = [_]usize{0} ** cfg.max_segments,
    checkpoint_interval: usize,
    rolling_window: usize,
};

pub const ExperimentData = struct {
    allocator: std.mem.Allocator,
    meta: ExperimentMeta,
    reports: std.ArrayList(network.RunReport) = .empty,

    pub fn deinit(self: *ExperimentData) void {
        for (self.reports.items) |*report| report.deinit();
        self.reports.deinit(self.allocator);
    }

    fn writeUsizeArray(writer: anytype, values: []const usize) !void {
        try writer.writeAll("[");
        for (values, 0..) |value, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writer.print("{d}", .{value});
        }
        try writer.writeAll("]");
    }

    pub fn writeJson(self: *ExperimentData, writer: anytype) !void {
        try writer.writeAll("{");
        try writer.writeAll("\"meta\":{");
        try writer.print("\"name\":\"{s}\",", .{self.meta.name});
        try writer.print("\"dataset_name\":\"{s}\",", .{self.meta.dataset_name});
        try writer.print("\"mode\":\"{s}\",", .{self.meta.mode});
        try writer.print("\"protocol\":\"{s}\",", .{self.meta.protocol});
        try writer.print("\"total_predictions\":{d},", .{self.meta.total_predictions});
        try writer.print("\"segment_count\":{d},", .{self.meta.segment_count});
        try writer.writeAll("\"segment_offsets\":");
        try writeUsizeArray(writer, self.meta.segment_offsets[0..self.meta.segment_count]);
        try writer.writeAll(",\"segment_lengths\":");
        try writeUsizeArray(writer, self.meta.segment_lengths[0..self.meta.segment_count]);
        try writer.print(",\"checkpoint_interval\":{d},", .{self.meta.checkpoint_interval});
        try writer.print("\"rolling_window\":{d}", .{self.meta.rolling_window});
        try writer.writeAll("},\"models\":[");
        for (self.reports.items, 0..) |*report, idx| {
            if (idx != 0) try writer.writeAll(",");
            try report.writeJson(writer);
        }
        try writer.writeAll("]}");
    }
};

const RowStat = struct {
    best_token: u8,
    actual_rank: u16,
};

fn rowBestAndRank(row: []const u32, actual: u8) RowStat {
    var best_token: u8 = 0;
    var best_count: u32 = 0;
    for (row, 0..) |count, idx| {
        if (count > best_count) {
            best_count = count;
            best_token = @intCast(idx);
        }
    }
    const actual_count = row[actual];
    var actual_rank: u16 = 1;
    for (row) |count| {
        if (count > actual_count) actual_rank += 1;
    }
    return .{ .best_token = best_token, .actual_rank = actual_rank };
}

fn makeMeta(corpus_cfg: cfg.CorpusConfig, bundle: *const stream.StreamBundle, dataset_path: []const u8, protocol: []const u8) ExperimentMeta {
    return .{
        .name = switch (corpus_cfg.mode) {
            .prefix => switch (protocol[0]) {
                'b' => "enwik8_v20_prefix_bit_sweep",
                'a' => "enwik8_v20_prefix_ablation",
                else => "enwik8_v20_prefix_custom",
            },
            .drift => switch (protocol[0]) {
                'b' => "enwik8_v20_drift_bit_sweep",
                'a' => "enwik8_v20_drift_ablation",
                else => "enwik8_v20_drift_custom",
            },
        },
        .dataset_name = std.fs.path.basename(dataset_path),
        .mode = switch (corpus_cfg.mode) {
            .prefix => "prefix",
            .drift => "drift",
        },
        .protocol = protocol,
        .total_predictions = bundle.predictionsLen(),
        .segment_count = bundle.segment_count,
        .segment_offsets = bundle.segment_offsets,
        .segment_lengths = bundle.segment_lengths,
        .checkpoint_interval = corpus_cfg.checkpoint_interval,
        .rolling_window = corpus_cfg.rolling_window,
    };
}

fn loadBundle(io: std.Io, allocator: std.mem.Allocator, corpus_cfg: cfg.CorpusConfig) !struct { corpus: []u8, bundle: stream.StreamBundle } {
    const corpus_bytes = try stream.loadCorpus(io, allocator, corpus_cfg.dataset_path);
    errdefer allocator.free(corpus_bytes);
    const bundle = switch (corpus_cfg.mode) {
        .prefix => try stream.buildPrefixBundle(allocator, corpus_bytes, corpus_cfg),
        .drift => try stream.buildDriftBundle(allocator, corpus_bytes, corpus_cfg),
    };
    return .{ .corpus = corpus_bytes, .bundle = bundle };
}

const SequenceSeedSource = struct {
    owned: ?[]u8 = null,
    bytes: []const u8 = &.{},

    fn deinit(self: *SequenceSeedSource, allocator: std.mem.Allocator) void {
        if (self.owned) |owned| allocator.free(owned);
        self.owned = null;
        self.bytes = &.{};
    }
};

fn resolveSequenceSeedSource(io: std.Io, allocator: std.mem.Allocator, corpus_cfg: cfg.CorpusConfig, loaded_corpus: []const u8) !SequenceSeedSource {
    const seed_path = corpus_cfg.sequence_seed_path orelse return .{};

    var source_owned: ?[]u8 = null;
    var source_bytes: []const u8 = loaded_corpus;
    if (!std.mem.eql(u8, seed_path, corpus_cfg.dataset_path)) {
        source_owned = try stream.loadCorpus(io, allocator, seed_path);
        source_bytes = source_owned.?;
    }
    errdefer if (source_owned) |owned| allocator.free(owned);

    return .{
        .owned = source_owned,
        .bytes = source_bytes,
    };
}

fn sequenceSeedForSegment(corpus_cfg: cfg.CorpusConfig, bundle: *const stream.StreamBundle, source_bytes: []const u8, segment_idx: u8) []const u8 {
    if (source_bytes.len == 0) return &.{};

    var start = corpus_cfg.sequence_seed_offset;
    if (corpus_cfg.sequence_seed_align_to_segment) {
        const base = bundle.segment_offsets[segment_idx] + if (corpus_cfg.sequence_seed_from_segment_end) bundle.segment_lengths[segment_idx] else 0;
        start = base +| corpus_cfg.sequence_seed_offset;
    }
    start = @min(start, source_bytes.len);
    const remaining = source_bytes.len - start;
    const requested_len = if (corpus_cfg.sequence_seed_length == 0) remaining else @min(corpus_cfg.sequence_seed_length, remaining);
    return source_bytes[start .. start + requested_len];
}

fn runOrder1(allocator: std.mem.Allocator, bundle: *const stream.StreamBundle, corpus_cfg: cfg.CorpusConfig) !network.RunReport {
    var report = try network.RunReport.init(allocator, .{
        .name = "markov_order1",
        .kind = "baseline",
        .weight_bits = 0,
        .segment_count = bundle.segment_count,
        .variant = "baseline",
    }, corpus_cfg.checkpoint_interval, corpus_cfg.rolling_window);

    var counts = std.mem.zeroes([256][256]u32);
    const total = bundle.predictionsLen();
    for (0..total) |idx| {
        const current = bundle.current_tokens[idx];
        const actual = bundle.next_tokens[idx];
        const stat = rowBestAndRank(&counts[current], actual);
        const was_correct = stat.best_token == actual;
        report.appendStep(was_correct, stat.actual_rank <= 5, bundle.segments[idx], 0, 0);
        try report.maybeCheckpoint(idx, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false);
        counts[current][actual] += 1;
    }
    if (total > 0) try report.maybeCheckpoint(total - 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, true);
    return report;
}

fn runOrder2(allocator: std.mem.Allocator, bundle: *const stream.StreamBundle, corpus_cfg: cfg.CorpusConfig) !network.RunReport {
    var report = try network.RunReport.init(allocator, .{
        .name = "markov_order2",
        .kind = "baseline",
        .weight_bits = 0,
        .segment_count = bundle.segment_count,
        .variant = "baseline",
    }, corpus_cfg.checkpoint_interval, corpus_cfg.rolling_window);

    var order1 = std.mem.zeroes([256][256]u32);
    const row_count: usize = 256 * 256 * 256;
    var counts = try allocator.alloc(u32, row_count);
    defer allocator.free(counts);
    @memset(counts, 0);

    var prev_token: u8 = 0;
    var have_prev = false;
    const total = bundle.predictionsLen();
    for (0..total) |idx| {
        if (bundle.reset_before[idx] == 1) have_prev = false;
        const current = bundle.current_tokens[idx];
        const actual = bundle.next_tokens[idx];

        var stat: RowStat = undefined;
        if (have_prev) {
            const base = (((@as(usize, prev_token) << 8) | @as(usize, current)) << 8);
            stat = rowBestAndRank(counts[base .. base + 256], actual);
            counts[base + actual] += 1;
        } else {
            stat = rowBestAndRank(&order1[current], actual);
        }

        const was_correct = stat.best_token == actual;
        report.appendStep(was_correct, stat.actual_rank <= 5, bundle.segments[idx], 0, 0);
        try report.maybeCheckpoint(idx, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false);
        order1[current][actual] += 1;
        prev_token = current;
        have_prev = true;
    }
    if (total > 0) try report.maybeCheckpoint(total - 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, true);
    return report;
}

fn finalizeReport(report: *network.RunReport, net: *const network.Network) void {
    report.summary.final_short_memories = net.countAliveShortMemories();
    report.summary.final_long_memories = net.countAliveLongMemories();
    report.summary.final_bridge_memories = net.countAliveBridgeMemories();
    report.summary.final_regions = net.countLiveRegions();
    report.summary.final_target_short = net.currentShortTarget();
    report.summary.final_memories = net.countAliveMemories();
    report.summary.final_synapses = net.countAliveSynapses();
    report.summary.births = net.births;
    report.summary.bridge_births = net.bridge_births;
    report.summary.promotions = net.promotions;
    report.summary.demotions = net.demotions;
    report.summary.recycled_slots = net.recycled_slots;
    report.summary.pruned_neurons = net.pruned_neurons;
    report.summary.pruned_synapses = net.pruned_synapses;
    report.summary.elastic_grows = net.elastic_grows;
    report.summary.elastic_shrinks = net.elastic_shrinks;
    report.summary.max_active_regions = net.max_active_regions_seen;
}

fn runSbanConfig(allocator: std.mem.Allocator, bundle: *const stream.StreamBundle, corpus_cfg: cfg.CorpusConfig, sequence_seed_source: []const u8, model_name: []const u8, variant_name: []const u8, net_config: cfg.NetworkConfig) !network.RunReport {
    var net = try network.Network.init(allocator, net_config);
    defer net.deinit();
    const initial_seed = sequenceSeedForSegment(corpus_cfg, bundle, sequence_seed_source, 0);
    if (initial_seed.len > 1) try net.pretrainSequenceExperts(initial_seed);

    var report = try network.RunReport.init(allocator, .{
        .name = model_name,
        .kind = "sban",
        .weight_bits = net_config.weight_bits,
        .segment_count = bundle.segment_count,
        .variant = variant_name,
    }, corpus_cfg.checkpoint_interval, corpus_cfg.rolling_window);

    const total = bundle.predictionsLen();
    for (0..total) |idx| {
        if (bundle.reset_before[idx] == 1) {
            net.resetTransient();
            const segment_seed = sequenceSeedForSegment(corpus_cfg, bundle, sequence_seed_source, bundle.segments[idx]);
            const should_seed = (corpus_cfg.sequence_seed_on_reset or corpus_cfg.sequence_seed_align_to_segment) and segment_seed.len > 1;
            if (should_seed) {
                if (corpus_cfg.sequence_seed_replace_on_reset) net.resetSequenceExperts();
                try net.pretrainSequenceExperts(segment_seed);
            }
        }
        const prediction = try net.step(bundle.current_tokens[idx], bundle.next_tokens[idx]);
        const was_correct = prediction.token == bundle.next_tokens[idx];
        report.appendStep(was_correct, prediction.actual_rank <= 5, bundle.segments[idx], prediction.active_count, prediction.margin);
        if ((idx + 1) % corpus_cfg.checkpoint_interval == 0) {
            try report.maybeCheckpoint(idx, net.countAliveShortMemories(), net.countAliveLongMemories(), net.countAliveBridgeMemories(), net.countLiveRegions(), net.currentShortTarget(), net.countAliveSynapses(), net.births, net.bridge_births, net.promotions, net.recycled_slots, false);
        }
    }
    if (total > 0) try report.maybeCheckpoint(total - 1, net.countAliveShortMemories(), net.countAliveLongMemories(), net.countAliveBridgeMemories(), net.countLiveRegions(), net.currentShortTarget(), net.countAliveSynapses(), net.births, net.bridge_births, net.promotions, net.recycled_slots, true);
    finalizeReport(&report, &net);
    return report;
}

fn runSbanVariant(allocator: std.mem.Allocator, bundle: *const stream.StreamBundle, corpus_cfg: cfg.CorpusConfig, sequence_seed_source: []const u8, bits: u8, variant: cfg.NetworkVariant) !network.RunReport {
    const net_config = cfg.configForVariant(bits, variant);
    return runSbanConfig(allocator, bundle, corpus_cfg, sequence_seed_source, cfg.sbanVariantLabel(bits, variant), variant.label(), net_config);
}

pub fn runCorpus(io: std.Io, allocator: std.mem.Allocator, corpus_cfg: cfg.CorpusConfig) !ExperimentData {
    var loaded = try loadBundle(io, allocator, corpus_cfg);
    defer allocator.free(loaded.corpus);
    defer loaded.bundle.deinit(allocator);
    var sequence_seed_source = try resolveSequenceSeedSource(io, allocator, corpus_cfg, loaded.corpus);
    defer sequence_seed_source.deinit(allocator);

    var data = ExperimentData{
        .allocator = allocator,
        .meta = makeMeta(corpus_cfg, &loaded.bundle, corpus_cfg.dataset_path, "bit_sweep"),
    };

    for (cfg.default_bit_widths) |bits| {
        try data.reports.append(allocator, try runSbanVariant(allocator, &loaded.bundle, corpus_cfg, sequence_seed_source.bytes, bits, .default));
    }
    try data.reports.append(allocator, try runOrder1(allocator, &loaded.bundle, corpus_cfg));
    try data.reports.append(allocator, try runOrder2(allocator, &loaded.bundle, corpus_cfg));
    return data;
}

pub fn runAblations(io: std.Io, allocator: std.mem.Allocator, corpus_cfg: cfg.CorpusConfig, bits: u8) !ExperimentData {
    var loaded = try loadBundle(io, allocator, corpus_cfg);
    defer allocator.free(loaded.corpus);
    defer loaded.bundle.deinit(allocator);
    var sequence_seed_source = try resolveSequenceSeedSource(io, allocator, corpus_cfg, loaded.corpus);
    defer sequence_seed_source.deinit(allocator);

    var data = ExperimentData{
        .allocator = allocator,
        .meta = makeMeta(corpus_cfg, &loaded.bundle, corpus_cfg.dataset_path, "ablation"),
    };

    const variants = [_]cfg.NetworkVariant{ .default, .no_bridge, .fixed_capacity, .single_region, .no_reputation };
    for (variants) |variant| {
        try data.reports.append(allocator, try runSbanVariant(allocator, &loaded.bundle, corpus_cfg, sequence_seed_source.bytes, bits, variant));
    }
    try data.reports.append(allocator, try runOrder2(allocator, &loaded.bundle, corpus_cfg));
    return data;
}

test "experiment can build prefix bundle and run reports" {
    const allocator = std.testing.allocator;
    const corpus = try allocator.alloc(u8, 4096);
    defer allocator.free(corpus);
    for (corpus, 0..) |*byte, idx| byte.* = @intCast(idx % 256);

    const tmp_path = "/tmp/sban_v5_test_enwik8.bin";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = corpus });
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var data = try runCorpus(io, allocator, .{ .dataset_path = tmp_path, .mode = .prefix, .segment_len = 128, .segment_count = 4, .checkpoint_interval = 64, .rolling_window = 32 });
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 10), data.reports.items.len);

    var ablation_data = try runAblations(io, allocator, .{ .dataset_path = tmp_path, .mode = .prefix, .segment_len = 128, .segment_count = 4, .checkpoint_interval = 64, .rolling_window = 32 }, 4);
    defer ablation_data.deinit();
    try std.testing.expectEqual(@as(usize, 6), ablation_data.reports.items.len);
}

pub fn runSingleVariant(io: std.Io, allocator: std.mem.Allocator, corpus_cfg: cfg.CorpusConfig, bits: u8, variant: cfg.NetworkVariant) !ExperimentData {
    var loaded = try loadBundle(io, allocator, corpus_cfg);
    defer allocator.free(loaded.corpus);
    defer loaded.bundle.deinit(allocator);
    var sequence_seed_source = try resolveSequenceSeedSource(io, allocator, corpus_cfg, loaded.corpus);
    defer sequence_seed_source.deinit(allocator);

    var data = ExperimentData{
        .allocator = allocator,
        .meta = makeMeta(corpus_cfg, &loaded.bundle, corpus_cfg.dataset_path, "single_variant"),
    };

    try data.reports.append(allocator, try runSbanVariant(allocator, &loaded.bundle, corpus_cfg, sequence_seed_source.bytes, bits, variant));
    try data.reports.append(allocator, try runOrder2(allocator, &loaded.bundle, corpus_cfg));
    return data;
}

pub fn runSingleCustom(io: std.Io, allocator: std.mem.Allocator, corpus_cfg: cfg.CorpusConfig, model_name: []const u8, variant_name: []const u8, net_config: cfg.NetworkConfig) !ExperimentData {
    var loaded = try loadBundle(io, allocator, corpus_cfg);
    defer allocator.free(loaded.corpus);
    defer loaded.bundle.deinit(allocator);
    var sequence_seed_source = try resolveSequenceSeedSource(io, allocator, corpus_cfg, loaded.corpus);
    defer sequence_seed_source.deinit(allocator);

    var data = ExperimentData{
        .allocator = allocator,
        .meta = makeMeta(corpus_cfg, &loaded.bundle, corpus_cfg.dataset_path, "single_variant"),
    };

    try data.reports.append(allocator, try runSbanConfig(allocator, &loaded.bundle, corpus_cfg, sequence_seed_source.bytes, model_name, variant_name, net_config));
    try data.reports.append(allocator, try runOrder2(allocator, &loaded.bundle, corpus_cfg));
    return data;
}
