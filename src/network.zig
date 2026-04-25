const std = @import("std");
const cfg = @import("config.zig");
const numeric_cuda = @import("numeric_cuda.zig");

pub const attribution_expert_count: usize = 9;

pub const Prediction = struct {
    token: u8,
    top_score: i32,
    margin: i32,
    actual_rank: u16,
    actual_score: i32,
    active_count: u16,
    surprise: bool,
};

pub const StepProfile = struct {
    prediction: Prediction,
    seed_ns: u64,
    propagate_ns: u64,
    score_ns: u64,
    output_update_ns: u64,
    plasticity_ns: u64,
    expert_update_ns: u64,
    housekeeping_ns: u64,
    maintenance_ns: u64,
    adapt_ns: u64,
    backend_used: cfg.NumericScoreBackend,

    pub fn totalNs(self: StepProfile) u64 {
        return self.seed_ns + self.propagate_ns + self.score_ns + self.adapt_ns;
    }
};

pub const Checkpoint = struct {
    step: u32,
    rolling_accuracy_ppm: u32,
    cumulative_accuracy_ppm: u32,
    memories: u32,
    short_memories: u32,
    long_memories: u32,
    bridge_memories: u32,
    regions: u16,
    target_short: u32,
    synapses: u32,
    births: u32,
    bridge_births: u32,
    promotions: u32,
    recycled_slots: u32,
};

pub const RunSummary = struct {
    name: []const u8,
    kind: []const u8,
    weight_bits: u8,
    segment_count: u8,
    variant: []const u8 = "default",
    total_predictions: usize = 0,
    total_correct: usize = 0,
    top5_correct: usize = 0,
    segment_correct: [cfg.max_segments]usize = [_]usize{0} ** cfg.max_segments,
    segment_total: [cfg.max_segments]usize = [_]usize{0} ** cfg.max_segments,
    final_memories: usize = 0,
    final_short_memories: usize = 0,
    final_long_memories: usize = 0,
    final_bridge_memories: usize = 0,
    final_regions: usize = 0,
    final_target_short: usize = 0,
    final_synapses: usize = 0,
    births: usize = 0,
    bridge_births: usize = 0,
    promotions: usize = 0,
    demotions: usize = 0,
    recycled_slots: usize = 0,
    pruned_neurons: usize = 0,
    pruned_synapses: usize = 0,
    elastic_grows: usize = 0,
    elastic_shrinks: usize = 0,
    active_total: u64 = 0,
    margin_total: i64 = 0,
    max_active_nodes: u16 = 0,
    max_active_regions: u16 = 0,
    sban_graph_correct: usize = 0,
    hybrid_changed_top: usize = 0,
    hybrid_changed_top_correct: usize = 0,
    bridge_activation_total: usize = 0,
    bridge_satisfied_total: usize = 0,
    expert_active: [attribution_expert_count]usize = [_]usize{0} ** attribution_expert_count,
    expert_correct: [attribution_expert_count]usize = [_]usize{0} ** attribution_expert_count,
    expert_final_match: [attribution_expert_count]usize = [_]usize{0} ** attribution_expert_count,
};

pub const RunReport = struct {
    allocator: std.mem.Allocator,
    summary: RunSummary,
    checkpoint_interval: usize,
    rolling_window: usize,
    checkpoints: std.ArrayList(Checkpoint) = .empty,
    rolling: []u8,
    rolling_pos: usize = 0,
    rolling_count: usize = 0,
    rolling_sum: usize = 0,

    pub fn init(allocator: std.mem.Allocator, summary: RunSummary, checkpoint_interval: usize, rolling_window: usize) !RunReport {
        const rolling = try allocator.alloc(u8, rolling_window);
        @memset(rolling, 0);
        return .{
            .allocator = allocator,
            .summary = summary,
            .checkpoint_interval = checkpoint_interval,
            .rolling_window = rolling_window,
            .rolling = rolling,
        };
    }

    pub fn deinit(self: *RunReport) void {
        self.checkpoints.deinit(self.allocator);
        self.allocator.free(self.rolling);
    }

    pub fn appendStep(self: *RunReport, was_correct: bool, top5: bool, segment_index: u8, active_count: u16, margin: i32) void {
        self.summary.total_predictions += 1;
        self.summary.segment_total[segment_index] += 1;
        if (was_correct) {
            self.summary.total_correct += 1;
            self.summary.segment_correct[segment_index] += 1;
        }
        if (top5) self.summary.top5_correct += 1;
        self.summary.active_total += active_count;
        self.summary.margin_total += margin;
        if (active_count > self.summary.max_active_nodes) self.summary.max_active_nodes = active_count;

        if (self.rolling_count < self.rolling_window) {
            self.rolling[self.rolling_count] = if (was_correct) 1 else 0;
            self.rolling_count += 1;
            self.rolling_sum += if (was_correct) 1 else 0;
        } else {
            self.rolling_sum -= self.rolling[self.rolling_pos];
            self.rolling[self.rolling_pos] = if (was_correct) 1 else 0;
            self.rolling_sum += if (was_correct) 1 else 0;
            self.rolling_pos = (self.rolling_pos + 1) % self.rolling_window;
        }
    }

    pub fn maybeCheckpoint(self: *RunReport, step: usize, short_memories: usize, long_memories: usize, bridge_memories: usize, regions: usize, target_short: usize, synapses: usize, births: usize, bridge_births: usize, promotions: usize, recycled_slots: usize, force: bool) !void {
        if (!force and (step + 1) % self.checkpoint_interval != 0) return;
        if (self.summary.total_predictions == 0) return;
        const rolling_denom = if (self.rolling_count == 0) 1 else self.rolling_count;
        const rolling_accuracy_ppm: u32 = @intCast((self.rolling_sum * 1_000_000) / rolling_denom);
        const cumulative_accuracy_ppm: u32 = @intCast((self.summary.total_correct * 1_000_000) / self.summary.total_predictions);
        if (self.checkpoints.items.len > 0 and self.checkpoints.items[self.checkpoints.items.len - 1].step == step + 1) return;
        try self.checkpoints.append(self.allocator, .{
            .step = @intCast(step + 1),
            .rolling_accuracy_ppm = rolling_accuracy_ppm,
            .cumulative_accuracy_ppm = cumulative_accuracy_ppm,
            .memories = @intCast(short_memories + long_memories),
            .short_memories = @intCast(short_memories),
            .long_memories = @intCast(long_memories),
            .bridge_memories = @intCast(bridge_memories),
            .regions = @intCast(regions),
            .target_short = @intCast(target_short),
            .synapses = @intCast(synapses),
            .births = @intCast(births),
            .bridge_births = @intCast(bridge_births),
            .promotions = @intCast(promotions),
            .recycled_slots = @intCast(recycled_slots),
        });
    }

    fn writeUsizeArray(writer: anytype, values: []const usize) !void {
        try writer.writeAll("[");
        for (values, 0..) |value, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writer.print("{d}", .{value});
        }
        try writer.writeAll("]");
    }

    pub fn writeJson(self: *const RunReport, writer: anytype) !void {
        try writer.writeAll("{");
        try writer.print("\"name\":\"{s}\",", .{self.summary.name});
        try writer.print("\"kind\":\"{s}\",", .{self.summary.kind});
        try writer.print("\"variant\":\"{s}\",", .{self.summary.variant});
        try writer.print("\"weight_bits\":{d},", .{self.summary.weight_bits});
        try writer.print("\"segment_count\":{d},", .{self.summary.segment_count});
        try writer.print("\"total_predictions\":{d},", .{self.summary.total_predictions});
        try writer.print("\"total_correct\":{d},", .{self.summary.total_correct});
        try writer.print("\"top5_correct\":{d},", .{self.summary.top5_correct});
        try writer.writeAll("\"segment_correct\":");
        try writeUsizeArray(writer, self.summary.segment_correct[0..self.summary.segment_count]);
        try writer.writeAll(",\"segment_total\":");
        try writeUsizeArray(writer, self.summary.segment_total[0..self.summary.segment_count]);
        try writer.print(",\"final_memories\":{d},", .{self.summary.final_memories});
        try writer.print("\"final_short_memories\":{d},", .{self.summary.final_short_memories});
        try writer.print("\"final_long_memories\":{d},", .{self.summary.final_long_memories});
        try writer.print("\"final_bridge_memories\":{d},", .{self.summary.final_bridge_memories});
        try writer.print("\"final_regions\":{d},", .{self.summary.final_regions});
        try writer.print("\"final_target_short\":{d},", .{self.summary.final_target_short});
        try writer.print("\"final_synapses\":{d},", .{self.summary.final_synapses});
        try writer.print("\"births\":{d},", .{self.summary.births});
        try writer.print("\"bridge_births\":{d},", .{self.summary.bridge_births});
        try writer.print("\"promotions\":{d},", .{self.summary.promotions});
        try writer.print("\"demotions\":{d},", .{self.summary.demotions});
        try writer.print("\"recycled_slots\":{d},", .{self.summary.recycled_slots});
        try writer.print("\"pruned_neurons\":{d},", .{self.summary.pruned_neurons});
        try writer.print("\"pruned_synapses\":{d},", .{self.summary.pruned_synapses});
        try writer.print("\"elastic_grows\":{d},", .{self.summary.elastic_grows});
        try writer.print("\"elastic_shrinks\":{d},", .{self.summary.elastic_shrinks});
        try writer.print("\"active_total\":{d},", .{self.summary.active_total});
        try writer.print("\"margin_total\":{d},", .{self.summary.margin_total});
        try writer.print("\"max_active_nodes\":{d},", .{self.summary.max_active_nodes});
        try writer.print("\"max_active_regions\":{d},", .{self.summary.max_active_regions});
        try writer.print("\"sban_graph_correct\":{d},", .{self.summary.sban_graph_correct});
        try writer.print("\"hybrid_changed_top\":{d},", .{self.summary.hybrid_changed_top});
        try writer.print("\"hybrid_changed_top_correct\":{d},", .{self.summary.hybrid_changed_top_correct});
        try writer.print("\"bridge_activation_total\":{d},", .{self.summary.bridge_activation_total});
        try writer.print("\"bridge_satisfied_total\":{d},", .{self.summary.bridge_satisfied_total});
        try writer.writeAll("\"expert_active\":");
        try writeUsizeArray(writer, &self.summary.expert_active);
        try writer.writeAll(",\"expert_correct\":");
        try writeUsizeArray(writer, &self.summary.expert_correct);
        try writer.writeAll(",\"expert_final_match\":");
        try writeUsizeArray(writer, &self.summary.expert_final_match);
        try writer.writeAll(",\"checkpoints\":[");
        for (self.checkpoints.items, 0..) |point, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writer.print(
                "{{\"step\":{d},\"rolling_accuracy_ppm\":{d},\"cumulative_accuracy_ppm\":{d},\"memories\":{d},\"short_memories\":{d},\"long_memories\":{d},\"bridge_memories\":{d},\"regions\":{d},\"target_short\":{d},\"synapses\":{d},\"births\":{d},\"bridge_births\":{d},\"promotions\":{d},\"recycled_slots\":{d}}}",
                .{ point.step, point.rolling_accuracy_ppm, point.cumulative_accuracy_ppm, point.memories, point.short_memories, point.long_memories, point.bridge_memories, point.regions, point.target_short, point.synapses, point.births, point.bridge_births, point.promotions, point.recycled_slots },
            );
        }
        try writer.writeAll("]}");
    }
};

const NeuronKind = enum(u8) {
    dead,
    sensory,
    memory_short,
    memory_long,
    output,
};

const MemoryRole = enum(u8) {
    local,
    bridge,
};

const Synapse = struct {
    target: u32,
    state: i16,
    permanence: u8,
    reputation: i16,
    last_touched: u32,
};

const Region = struct {
    live_short: u32 = 0,
    live_long: u32 = 0,
    live_bridge: u32 = 0,
    target_short: u32 = 0,
    recent_births: u16 = 0,
    recent_active: u16 = 0,
    recent_correct: u16 = 0,
    recent_wrong: u16 = 0,
    last_active_step: u32 = 0,
};

const Neuron = struct {
    kind: NeuronKind,
    role: MemoryRole,
    region: u16,
    secondary_region: u16,
    threshold: i32,
    utility: i16,
    support: u16,
    reputation: i16,
    wins: u16,
    losses: u16,
    birth_step: u32,
    last_active_step: u32,
    signature: u64,
    last_activation: i32,
    outgoing: std.ArrayList(Synapse) = .empty,

    fn init(kind: NeuronKind, threshold: i32) Neuron {
        return .{
            .kind = kind,
            .role = .local,
            .region = 0,
            .secondary_region = cfg.invalid_region,
            .threshold = threshold,
            .utility = 0,
            .support = 0,
            .reputation = 0,
            .wins = 0,
            .losses = 0,
            .birth_step = 0,
            .last_active_step = 0,
            .signature = 0,
            .last_activation = 0,
        };
    }

    fn reset(self: *Neuron, kind: NeuronKind, threshold: i32) void {
        self.kind = kind;
        self.role = .local;
        self.region = 0;
        self.secondary_region = cfg.invalid_region;
        self.threshold = threshold;
        self.utility = 0;
        self.support = 0;
        self.reputation = 0;
        self.wins = 0;
        self.losses = 0;
        self.birth_step = 0;
        self.last_active_step = 0;
        self.signature = 0;
        self.last_activation = 0;
        self.outgoing.clearRetainingCapacity();
    }

    fn deinit(self: *Neuron, allocator: std.mem.Allocator) void {
        self.outgoing.deinit(allocator);
    }
};

const Candidate = struct {
    id: u32,
    score: i32,
};

fn absI16(value: i16) i16 {
    return if (value < 0) -value else value;
}

fn absI32(value: i32) i32 {
    return if (value < 0) -value else value;
}

fn maxIntI32(a: i32, b: i32) i32 {
    return if (a > b) a else b;
}

fn clampI16(value: i32) i16 {
    if (value > std.math.maxInt(i16)) return std.math.maxInt(i16);
    if (value < std.math.minInt(i16)) return std.math.minInt(i16);
    return @intCast(value);
}

const hybrid_expert_count: usize = attribution_expert_count;
const expert_sban_idx: usize = 0;
const expert_markov1_idx: usize = 1;
const expert_markov2_idx: usize = 2;
const expert_markov3_idx: usize = 3;
const expert_markov4_idx: usize = 4;
const expert_markov5_idx: usize = 5;
const expert_continuation_idx: usize = 6;
const expert_burst_idx: usize = 7;
const expert_recent_markov2_idx: usize = 8;
const default_hybrid_weights = [hybrid_expert_count]i16{ 1088, 320, 832, 960, 1248, 1408, 1664, 640, 1152 };
const recent_row2_sentinel: u32 = std.math.maxInt(u32);
const continuation_hash_offset: u64 = 14695981039346656037;
const continuation_hash_prime: u64 = 1099511628211;

const ScoreTop = struct {
    token: u8,
    top_score: i32,
    second_score: i32,
};

const ContinuationCell = struct {
    token: u8 = 0,
    vote: u16 = 0,
    support: u16 = 0,
};

fn contextKey(prev: u8, current: u8) usize {
    return (@as(usize, prev) << 8) | @as(usize, current);
}

fn contextKey3(prev2: u8, prev1: u8, current: u8) u32 {
    return (@as(u32, prev2) << 16) | (@as(u32, prev1) << 8) | @as(u32, current);
}

fn contextKey4(prev3: u8, prev2: u8, prev1: u8, current: u8) u32 {
    return (@as(u32, prev3) << 24) | (@as(u32, prev2) << 16) | (@as(u32, prev1) << 8) | @as(u32, current);
}

fn contextKey5(prev4: u8, prev3: u8, prev2: u8, prev1: u8, current: u8) u64 {
    return (@as(u64, prev4) << 32) | (@as(u64, prev3) << 24) | (@as(u64, prev2) << 16) | (@as(u64, prev1) << 8) | @as(u64, current);
}

fn hashByte(hash: u64, byte: u8) u64 {
    return (hash ^ @as(u64, byte)) *% continuation_hash_prime;
}

fn findTop2(scores: []const i32) ScoreTop {
    var top_token: u8 = 0;
    var top_score: i32 = std.math.minInt(i32);
    var second_score: i32 = std.math.minInt(i32);
    for (scores, 0..) |score, idx| {
        if (score > top_score) {
            second_score = top_score;
            top_score = score;
            top_token = @intCast(idx);
        } else if (score > second_score) {
            second_score = score;
        }
    }
    if (top_score == std.math.minInt(i32)) top_score = 0;
    if (second_score == std.math.minInt(i32)) second_score = 0;
    return .{ .token = top_token, .top_score = top_score, .second_score = second_score };
}

const score_parallel_io = std.Options.debug_io;

const ParallelScoreTask = struct {
    network: ?*const Network = null,
    start_index: usize = 0,
    end_index: usize = 0,
};

const ParallelScoreRuntime = struct {
    allocator: std.mem.Allocator,
    slot_count: usize,
    max_regions: usize,
    vocab_size: usize,
    workers: []std.Thread,
    start_semaphores: []std.Io.Semaphore,
    tasks: []ParallelScoreTask,
    partial_region_scores: []i32,
    completed: std.Io.Semaphore = .{},
    stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn init(allocator: std.mem.Allocator, config: cfg.NetworkConfig) !?*ParallelScoreRuntime {
        const cpu_count = std.Thread.getCpuCount() catch 1;
        const requested = if (config.score_threads != 0) config.score_threads else @as(u16, @intCast(cpu_count));
        const slot_count = @min(@max(@as(usize, 1), requested), @max(@as(usize, 1), cpu_count));
        if (slot_count <= 1) return null;

        const runtime = try allocator.create(ParallelScoreRuntime);
        errdefer allocator.destroy(runtime);

        runtime.* = .{
            .allocator = allocator,
            .slot_count = slot_count,
            .max_regions = config.max_regions,
            .vocab_size = config.vocab_size,
            .workers = try allocator.alloc(std.Thread, slot_count - 1),
            .start_semaphores = try allocator.alloc(std.Io.Semaphore, slot_count - 1),
            .tasks = try allocator.alloc(ParallelScoreTask, slot_count),
            .partial_region_scores = try allocator.alloc(i32, slot_count * @as(usize, config.max_regions) * @as(usize, config.vocab_size)),
        };
        errdefer allocator.free(runtime.partial_region_scores);
        errdefer allocator.free(runtime.tasks);
        errdefer allocator.free(runtime.start_semaphores);
        errdefer allocator.free(runtime.workers);

        for (runtime.start_semaphores) |*sem| sem.* = .{};
        for (runtime.tasks) |*task| task.* = .{};
        @memset(runtime.partial_region_scores, 0);

        var spawned: usize = 0;
        errdefer {
            runtime.stop_requested.store(true, .release);
            for (runtime.start_semaphores[0..spawned]) |*sem| sem.post(score_parallel_io);
            for (runtime.workers[0..spawned]) |thread| thread.join();
        }
        for (0..runtime.workers.len) |worker_index| {
            runtime.workers[worker_index] = try std.Thread.spawn(.{}, parallelScoreWorkerMain, .{ runtime, worker_index + 1 });
            spawned += 1;
        }
        return runtime;
    }

    fn deinit(self: *ParallelScoreRuntime) void {
        self.stop_requested.store(true, .release);
        for (self.start_semaphores) |*sem| sem.post(score_parallel_io);
        for (self.workers) |thread| thread.join();
        self.allocator.free(self.partial_region_scores);
        self.allocator.free(self.tasks);
        self.allocator.free(self.start_semaphores);
        self.allocator.free(self.workers);
        self.allocator.destroy(self);
    }

    fn bufferLen(self: *const ParallelScoreRuntime) usize {
        return self.max_regions * self.vocab_size;
    }

    fn workerCount(self: *const ParallelScoreRuntime) usize {
        return self.slot_count - 1;
    }

    fn regionSlice(self: *ParallelScoreRuntime, slot_index: usize) []i32 {
        const buffer_len = self.bufferLen();
        const start = slot_index * buffer_len;
        return self.partial_region_scores[start .. start + buffer_len];
    }
};

fn parallelScoreWorkerMain(runtime: *ParallelScoreRuntime, slot_index: usize) void {
    const start_sem = &runtime.start_semaphores[slot_index - 1];
    while (true) {
        start_sem.waitUncancelable(score_parallel_io);
        if (runtime.stop_requested.load(.acquire)) break;
        const task = runtime.tasks[slot_index];
        const output = runtime.regionSlice(slot_index);
        if (task.network) |network| {
            network.scorePredictiveRange(output, task.start_index, task.end_index);
        } else {
            @memset(output, 0);
        }
        runtime.completed.post(score_parallel_io);
    }
}

fn numericCudaMaxNeuronCount(config: cfg.NetworkConfig) usize {
    return @as(usize, config.history_lags) * @as(usize, config.vocab_size) +
        @as(usize, config.vocab_size) +
        @as(usize, config.max_short_memories) +
        @as(usize, config.max_long_memories);
}

fn initNumericCudaRuntime(allocator: std.mem.Allocator, config: cfg.NetworkConfig) !?*numeric_cuda.NumericCudaRuntime {
    if (config.numeric_backend != .cuda and config.numeric_backend != .auto) return null;
    const runtime = try allocator.create(numeric_cuda.NumericCudaRuntime);
    errdefer allocator.destroy(runtime);
    runtime.* = try numeric_cuda.NumericCudaRuntime.init(
        allocator,
        @as(usize, config.max_regions) * @as(usize, config.vocab_size),
        numericCudaMaxNeuronCount(config),
        config.max_outgoing_per_node,
    );
    return runtime;
}

pub const Network = struct {
    allocator: std.mem.Allocator,
    config: cfg.NetworkConfig,
    neurons: std.ArrayList(Neuron) = .empty,
    lag_sensory_ids: std.ArrayList(u32) = .empty,
    output_ids: std.ArrayList(u32) = .empty,
    regions: std.ArrayList(Region) = .empty,
    active_now: std.ArrayList(u32) = .empty,
    predictive_nodes: std.ArrayList(u32) = .empty,
    carry_memories: std.ArrayList(u32) = .empty,
    active_regions: std.ArrayList(u16) = .empty,
    frontier: std.ArrayList(u32) = .empty,
    next_frontier: std.ArrayList(u32) = .empty,
    touched: std.ArrayList(u32) = .empty,
    candidate_buffer: std.ArrayList(Candidate) = .empty,
    active_marks: std.ArrayList(u32) = .empty,
    score_values: std.ArrayList(i32) = .empty,
    score_marks: std.ArrayList(u32) = .empty,
    output_scores: std.ArrayList(i32) = .empty,
    order1_counts: []u32,
    order2_counts: []u32,
    order3_row_map: std.AutoHashMap(u32, u32),
    order3_rows: std.ArrayList(u16) = .empty,
    order4_row_map: std.AutoHashMap(u32, u32),
    order4_rows: std.ArrayList(u16) = .empty,
    order5_row_map: std.AutoHashMap(u64, u32),
    order5_rows: std.ArrayList(u16) = .empty,
    continuation_map: std.AutoHashMap(u64, u32),
    continuation_cells: std.ArrayList(ContinuationCell) = .empty,
    recent_order2_counts: []u16,
    recent_row2_ring: []u32,
    burst_next: []u8,
    burst_streak: []u8,
    burst_last_step: []u32,
    region_marks: []u32,
    region_output_scores: []i32,
    parallel_score_runtime: ?*ParallelScoreRuntime = null,
    numeric_cuda_runtime: ?*numeric_cuda.NumericCudaRuntime = null,
    numeric_cuda_indices: std.ArrayList(u32) = .empty,
    numeric_cuda_values: std.ArrayList(i32) = .empty,
    numeric_cuda_region_bases: std.ArrayList(u32) = .empty,
    numeric_cuda_long_scales: std.ArrayList(u32) = .empty,
    numeric_cuda_bridge_scales: std.ArrayList(u32) = .empty,
    numeric_cuda_dirty_nodes: std.ArrayList(u32) = .empty,
    numeric_cuda_dirty_flags: std.ArrayList(u8) = .empty,
    numeric_cuda_force_full_resync: bool = false,
    free_memory_ids: std.ArrayList(u32) = .empty,
    protected_memories: std.ArrayList(u32) = .empty,
    signature_map: std.AutoHashMap(u64, u32),
    recent_tokens: []u8,
    recent_len: usize = 0,
    output_base: u32 = 0,
    open_region_count: u16 = 1,
    global_short_target: u32 = 0,
    alive_short_memories: usize = 0,
    alive_long_memories: usize = 0,
    step_index: u32 = 0,
    mark_epoch: u32 = 1,
    births: usize = 0,
    bridge_births: usize = 0,
    promotions: usize = 0,
    demotions: usize = 0,
    recycled_slots: usize = 0,
    pruned_neurons: usize = 0,
    pruned_synapses: usize = 0,
    elastic_grows: usize = 0,
    elastic_shrinks: usize = 0,
    max_active_regions_seen: u16 = 0,
    last_score_backend_used: cfg.NumericScoreBackend = .cpu,
    interval_steps: u32 = 0,
    interval_surprises: u32 = 0,
    interval_births: u32 = 0,
    interval_correct: u32 = 0,
    interval_confident: u32 = 0,
    last_birth_step: u32 = 0,
    recent_ring_pos: usize = 0,
    recent_ring_count: usize = 0,
    hybrid_weights: [hybrid_expert_count]i16 = default_hybrid_weights,
    last_expert_tokens: [hybrid_expert_count]u8 = [_]u8{0} ** hybrid_expert_count,
    last_expert_scores: [hybrid_expert_count]i32 = [_]i32{0} ** hybrid_expert_count,
    last_expert_active: [hybrid_expert_count]bool = [_]bool{false} ** hybrid_expert_count,
    expert_active_total: [hybrid_expert_count]usize = [_]usize{0} ** hybrid_expert_count,
    expert_correct_total: [hybrid_expert_count]usize = [_]usize{0} ** hybrid_expert_count,
    expert_final_match_total: [hybrid_expert_count]usize = [_]usize{0} ** hybrid_expert_count,
    sban_graph_correct: usize = 0,
    hybrid_changed_top: usize = 0,
    hybrid_changed_top_correct: usize = 0,
    bridge_activation_total: usize = 0,
    bridge_satisfied_total: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: cfg.NetworkConfig) !Network {
        const clamped_regions = @max(@as(u16, 1), @min(config.initial_regions, config.max_regions));
        const initial_target = @max(config.min_short_target, @min(config.initial_short_target, config.max_short_memories));
        var self = Network{
            .allocator = allocator,
            .config = config,
            .signature_map = std.AutoHashMap(u64, u32).init(allocator),
            .order3_row_map = std.AutoHashMap(u32, u32).init(allocator),
            .order4_row_map = std.AutoHashMap(u32, u32).init(allocator),
            .order5_row_map = std.AutoHashMap(u64, u32).init(allocator),
            .continuation_map = std.AutoHashMap(u64, u32).init(allocator),
            .recent_tokens = try allocator.alloc(u8, @max(@as(usize, 1), @as(usize, config.history_lags) - 1)),
            .order1_counts = try allocator.alloc(u32, @as(usize, config.vocab_size) * @as(usize, config.vocab_size)),
            .order2_counts = try allocator.alloc(u32, @as(usize, config.vocab_size) * @as(usize, config.vocab_size) * @as(usize, config.vocab_size)),
            .recent_order2_counts = try allocator.alloc(u16, @as(usize, config.vocab_size) * @as(usize, config.vocab_size) * @as(usize, config.vocab_size)),
            .recent_row2_ring = try allocator.alloc(u32, @max(@as(usize, 1), @as(usize, config.recent_expert_window))),
            .burst_next = try allocator.alloc(u8, @as(usize, config.vocab_size) * @as(usize, config.vocab_size)),
            .burst_streak = try allocator.alloc(u8, @as(usize, config.vocab_size) * @as(usize, config.vocab_size)),
            .burst_last_step = try allocator.alloc(u32, @as(usize, config.vocab_size) * @as(usize, config.vocab_size)),
            .region_marks = try allocator.alloc(u32, config.max_regions),
            .region_output_scores = try allocator.alloc(i32, @as(usize, config.max_regions) * @as(usize, config.vocab_size)),
            .open_region_count = clamped_regions,
            .global_short_target = initial_target,
        };
        @memset(self.order1_counts, 0);
        @memset(self.order2_counts, 0);
        @memset(self.recent_order2_counts, 0);
        @memset(self.recent_row2_ring, recent_row2_sentinel);
        @memset(self.burst_next, 0);
        @memset(self.burst_streak, 0);
        @memset(self.burst_last_step, 0);
        @memset(self.region_marks, 0);
        @memset(self.region_output_scores, 0);

        const sensory_count = @as(usize, config.history_lags) * @as(usize, config.vocab_size);
        const initial_neurons = sensory_count + @as(usize, config.vocab_size) + 128;
        try self.neurons.ensureTotalCapacity(allocator, initial_neurons);
        try self.lag_sensory_ids.ensureTotalCapacity(allocator, sensory_count);
        try self.output_ids.ensureTotalCapacity(allocator, config.vocab_size);
        try self.active_regions.ensureTotalCapacity(allocator, config.max_regions);
        try self.active_marks.resize(allocator, initial_neurons);
        try self.score_values.resize(allocator, initial_neurons);
        try self.score_marks.resize(allocator, initial_neurons);
        try self.output_scores.resize(allocator, config.vocab_size);
        try self.regions.resize(allocator, config.max_regions);
        for (self.regions.items) |*region| region.* = .{};
        @memset(self.active_marks.items, 0);
        @memset(self.score_values.items, 0);
        @memset(self.score_marks.items, 0);
        @memset(self.output_scores.items, 0);

        self.parallel_score_runtime = try ParallelScoreRuntime.init(allocator, config);
        self.numeric_cuda_runtime = initNumericCudaRuntime(allocator, config) catch null;

        for (0..config.history_lags) |_| {
            for (0..config.vocab_size) |_| {
                const sensory_id = try self.addNeuron(.sensory, 0);
                try self.lag_sensory_ids.append(allocator, sensory_id);
            }
        }
        self.output_base = @intCast(self.neurons.items.len);
        for (0..config.vocab_size) |_| {
            const output_id = try self.addNeuron(.output, 0);
            try self.output_ids.append(allocator, output_id);
        }
        self.rebalanceRegionTargets();
        return self;
    }

    pub fn deinit(self: *Network) void {
        for (self.neurons.items) |*neuron| neuron.deinit(self.allocator);
        if (self.numeric_cuda_runtime) |runtime| {
            runtime.deinit();
            self.allocator.destroy(runtime);
        }
        if (self.parallel_score_runtime) |runtime| runtime.deinit();
        self.neurons.deinit(self.allocator);
        self.lag_sensory_ids.deinit(self.allocator);
        self.output_ids.deinit(self.allocator);
        self.regions.deinit(self.allocator);
        self.active_now.deinit(self.allocator);
        self.predictive_nodes.deinit(self.allocator);
        self.carry_memories.deinit(self.allocator);
        self.active_regions.deinit(self.allocator);
        self.frontier.deinit(self.allocator);
        self.next_frontier.deinit(self.allocator);
        self.touched.deinit(self.allocator);
        self.candidate_buffer.deinit(self.allocator);
        self.active_marks.deinit(self.allocator);
        self.score_values.deinit(self.allocator);
        self.score_marks.deinit(self.allocator);
        self.output_scores.deinit(self.allocator);
        self.allocator.free(self.order1_counts);
        self.allocator.free(self.order2_counts);
        self.order3_row_map.deinit();
        self.order3_rows.deinit(self.allocator);
        self.order4_row_map.deinit();
        self.order4_rows.deinit(self.allocator);
        self.order5_row_map.deinit();
        self.order5_rows.deinit(self.allocator);
        self.continuation_map.deinit();
        self.continuation_cells.deinit(self.allocator);
        self.allocator.free(self.recent_order2_counts);
        self.allocator.free(self.recent_row2_ring);
        self.allocator.free(self.burst_next);
        self.allocator.free(self.burst_streak);
        self.allocator.free(self.burst_last_step);
        self.numeric_cuda_indices.deinit(self.allocator);
        self.numeric_cuda_values.deinit(self.allocator);
        self.numeric_cuda_region_bases.deinit(self.allocator);
        self.numeric_cuda_long_scales.deinit(self.allocator);
        self.numeric_cuda_bridge_scales.deinit(self.allocator);
        self.numeric_cuda_dirty_nodes.deinit(self.allocator);
        self.numeric_cuda_dirty_flags.deinit(self.allocator);
        self.free_memory_ids.deinit(self.allocator);
        self.protected_memories.deinit(self.allocator);
        self.signature_map.deinit();
        self.allocator.free(self.recent_tokens);
        self.allocator.free(self.region_marks);
        self.allocator.free(self.region_output_scores);
    }

    fn clearRecentExpertState(self: *Network) void {
        @memset(self.recent_order2_counts, 0);
        @memset(self.recent_row2_ring, recent_row2_sentinel);
        @memset(self.burst_next, 0);
        @memset(self.burst_streak, 0);
        @memset(self.burst_last_step, 0);
        self.recent_ring_pos = 0;
        self.recent_ring_count = 0;
    }

    fn clearLocalExpertState(self: *Network) void {
        self.clearRecentExpertState();
        self.hybrid_weights = default_hybrid_weights;
    }

    pub fn resetSequenceExperts(self: *Network) void {
        @memset(self.order1_counts, 0);
        @memset(self.order2_counts, 0);
        self.order3_row_map.clearRetainingCapacity();
        self.order3_rows.clearRetainingCapacity();
        self.order4_row_map.clearRetainingCapacity();
        self.order4_rows.clearRetainingCapacity();
        self.order5_row_map.clearRetainingCapacity();
        self.order5_rows.clearRetainingCapacity();
        self.continuation_map.clearRetainingCapacity();
        self.continuation_cells.clearRetainingCapacity();
        self.clearLocalExpertState();
        self.recent_len = 0;
    }

    pub fn resetTransient(self: *Network) void {
        self.recent_len = 0;
        self.carry_memories.clearRetainingCapacity();
        if (self.config.reset_local_experts_on_boundary) {
            self.clearLocalExpertState();
        }
    }

    pub fn pretrainSequenceExperts(self: *Network, bytes: []const u8) !void {
        if (bytes.len < 2) return;

        const saved_step_index = self.step_index;
        self.clearLocalExpertState();
        self.recent_len = 0;
        self.step_index = 0;

        var idx: usize = 0;
        while (idx + 1 < bytes.len) : (idx += 1) {
            self.step_index +|= 1;
            try self.updateSequenceExperts(bytes[idx], bytes[idx + 1]);
            self.pushHistory(bytes[idx]);
        }

        self.clearLocalExpertState();
        self.recent_len = 0;
        self.step_index = 0;

        idx = 0;
        while (idx + 1 < bytes.len) : (idx += 1) {
            self.step_index +|= 1;
            @memset(self.output_scores.items, 0);
            _ = self.applyHybridExperts(bytes[idx]);
            self.recordExpertPrediction(expert_sban_idx, 0, 0, false);
            self.updateHybridExpertWeights(bytes[idx + 1]);
            self.updateLocalExpertState(bytes[idx], bytes[idx + 1]);
            self.pushHistory(bytes[idx]);
        }

        const calibrated_weights = self.hybrid_weights;
        self.clearRecentExpertState();
        self.hybrid_weights = calibrated_weights;
        for (0..hybrid_expert_count) |expert_idx| self.recordExpertPrediction(expert_idx, 0, 0, false);
        self.recent_len = 0;
        self.step_index = saved_step_index;
    }

    fn ensureScratchForNeuronCount(self: *Network) !void {
        const n = self.neurons.items.len;
        if (self.active_marks.items.len < n) {
            const old_len = self.active_marks.items.len;
            try self.active_marks.resize(self.allocator, n);
            @memset(self.active_marks.items[old_len..], 0);
        }
        if (self.score_values.items.len < n) {
            const old_len = self.score_values.items.len;
            try self.score_values.resize(self.allocator, n);
            @memset(self.score_values.items[old_len..], 0);
        }
        if (self.score_marks.items.len < n) {
            const old_len = self.score_marks.items.len;
            try self.score_marks.resize(self.allocator, n);
            @memset(self.score_marks.items[old_len..], 0);
        }
        if (self.numeric_cuda_dirty_flags.items.len < n) {
            const old_len = self.numeric_cuda_dirty_flags.items.len;
            try self.numeric_cuda_dirty_flags.resize(self.allocator, n);
            @memset(self.numeric_cuda_dirty_flags.items[old_len..], 0);
        }
    }

    fn addNeuron(self: *Network, kind: NeuronKind, threshold: i32) !u32 {
        try self.neurons.append(self.allocator, Neuron.init(kind, threshold));
        try self.ensureScratchForNeuronCount();
        return @intCast(self.neurons.items.len - 1);
    }

    fn addMemoryNeuron(self: *Network, kind: NeuronKind, threshold: i32) !u32 {
        if (self.free_memory_ids.pop()) |reused_id| {
            const idx: usize = @intCast(reused_id);
            self.neurons.items[idx].reset(kind, threshold);
            self.recycled_slots += 1;
            return reused_id;
        }
        return try self.addNeuron(kind, threshold);
    }

    fn markNumericCudaNeuronDirty(self: *Network, id: u32) void {
        if (self.numeric_cuda_runtime == null) return;
        const idx: usize = @intCast(id);
        if (idx >= self.numeric_cuda_dirty_flags.items.len) return;
        if (self.numeric_cuda_dirty_flags.items[idx] != 0) return;
        self.numeric_cuda_dirty_flags.items[idx] = 1;
        self.numeric_cuda_dirty_nodes.append(self.allocator, id) catch {
            self.numeric_cuda_force_full_resync = true;
        };
    }

    fn maxQuant(self: *const Network) i16 {
        return @as(i16, 1) << @intCast(self.config.weight_bits - 1);
    }

    fn nudgeQuantum(self: *const Network) i16 {
        const quantum = @divTrunc(self.maxQuant(), 16);
        return if (quantum < 1) 1 else quantum;
    }

    fn positiveState(self: *const Network, strong: bool) i16 {
        const max_quant = self.maxQuant();
        if (strong) return max_quant;
        const weak = @divTrunc(max_quant, 2);
        return if (weak < 1) 1 else weak;
    }

    fn negativeState(self: *const Network, strong: bool) i16 {
        return -self.positiveState(strong);
    }

    fn nudgePositive(self: *const Network, state: *i16) void {
        const max_quant = self.maxQuant();
        const quantum = self.nudgeQuantum();
        var next = state.* + quantum;
        if (state.* < 0 and next > 0) next = 1;
        if (next == 0) next = 1;
        if (next > max_quant) next = max_quant;
        state.* = next;
    }

    fn nudgeNegative(self: *const Network, state: *i16) void {
        const max_quant = self.maxQuant();
        const quantum = self.nudgeQuantum();
        var next = state.* - quantum;
        if (state.* > 0 and next < 0) next = -1;
        if (next == 0) next = -1;
        if (next < -max_quant) next = -max_quant;
        state.* = next;
    }

    fn scaledValue(self: *const Network, state: i16) i32 {
        return @divTrunc(@as(i32, state) * cfg.score_scale, @as(i32, self.maxQuant()));
    }

    fn lagSensoryId(self: *const Network, lag: u8, token: u8) u32 {
        const idx = @as(usize, lag) * @as(usize, self.config.vocab_size) + @as(usize, token);
        return self.lag_sensory_ids.items[idx];
    }

    fn rebalanceRegionTargets(self: *Network) void {
        if (self.regions.items.len == 0) return;
        if (self.open_region_count == 0) self.open_region_count = 1;
        const open_count: usize = self.open_region_count;
        const base = @divTrunc(self.global_short_target, @as(u32, self.open_region_count));
        const remainder = self.global_short_target % @as(u32, self.open_region_count);
        for (self.regions.items, 0..) |*region, idx| {
            if (idx < open_count) {
                const extra: u32 = if (@as(u32, @intCast(idx)) < remainder) 1 else 0;
                var target: u32 = base + extra;
                if (target == 0) target = 1;
                region.target_short = target;
            } else {
                region.target_short = 0;
            }
        }
    }

    fn maybeGrowOpenRegions(self: *Network, desired: u16) void {
        const capped = @min(desired, self.config.max_regions);
        if (capped <= self.open_region_count) return;
        self.open_region_count = capped;
        self.rebalanceRegionTargets();
    }

    fn tokenRegionClass(token: u8) u16 {
        if (token == ' ' or token == '\n' or token == '\t' or token == '\r') return 0;
        if (token >= 'a' and token <= 'z') return 1;
        if (token >= 'A' and token <= 'Z') return 2;
        if (token >= '0' and token <= '9') return 3;
        if ((token >= 33 and token <= 47) or (token >= 58 and token <= 64) or (token >= 91 and token <= 96) or (token >= 123 and token <= 126)) return 4;
        if (token < 32) return 5;
        return 6;
    }

    fn tokenRegion(self: *const Network, token: u8) u16 {
        const open_count = self.open_region_count;
        if (!self.config.enable_token_region_routing or open_count <= 1) return 0;
        const class = tokenRegionClass(token);
        const mixed: u32 = (@as(u32, token) *% 131) ^ (@as(u32, token >> 3) *% 17) ^ (@as(u32, class) *% 29);
        return @intCast(mixed % @as(u32, open_count));
    }

    fn nodeRegion(self: *const Network, id: u32) u16 {
        const idx: usize = @intCast(id);
        if (idx >= self.neurons.items.len) return 0;
        const neuron = self.neurons.items[idx];
        return switch (neuron.kind) {
            .memory_short, .memory_long => neuron.region,
            .sensory => self.tokenRegion(@intCast(id % self.config.vocab_size)),
            else => 0,
        };
    }

    fn noteRegionActive(self: *Network, region: u16) !void {
        const idx: usize = region;
        if (idx >= self.region_marks.len) return;
        if (self.region_marks[idx] != self.mark_epoch) {
            self.region_marks[idx] = self.mark_epoch;
            try self.active_regions.append(self.allocator, region);
        }
        self.regions.items[idx].last_active_step = self.step_index;
        self.regions.items[idx].recent_active +|= 1;
    }

    fn bridgeSatisfied(self: *const Network, neuron: Neuron) bool {
        if (neuron.role != .bridge) return true;
        if (neuron.secondary_region == cfg.invalid_region) return true;
        const primary_idx: usize = neuron.region;
        const secondary_idx: usize = neuron.secondary_region;
        if (primary_idx >= self.region_marks.len or secondary_idx >= self.region_marks.len) return false;
        return self.region_marks[primary_idx] == self.mark_epoch and self.region_marks[secondary_idx] == self.mark_epoch;
    }

    fn birthPressureHigh(self: *const Network) bool {
        if (self.interval_births >= self.config.birth_pressure_soft_threshold) return true;
        if (self.global_short_target == 0) return false;
        return self.alive_short_memories * 1000 >= self.global_short_target * 900;
    }

    fn birthSaturationHigh(self: *const Network) bool {
        if (self.global_short_target == 0) return false;
        return @as(u64, self.alive_short_memories) * 1_000_000 >= @as(u64, self.global_short_target) * self.config.birth_saturation_soft_ppm;
    }

    fn severeSurprise(self: *const Network, prediction: Prediction) bool {
        _ = self;
        return prediction.actual_rank > 6 or prediction.margin <= -cfg.score_scale / 2;
    }

    fn memoryContributionBonus(self: *const Network, neuron: Neuron) i32 {
        var bonus: i32 = 0;
        if (self.config.use_reputation) {
            bonus += @divTrunc(@as(i32, neuron.reputation), 2);
        }
        bonus += @divTrunc(@as(i32, neuron.utility), 2);
        if (neuron.kind == .memory_long) bonus += cfg.score_scale / 8;
        if (neuron.role == .bridge) {
            if (self.bridgeSatisfied(neuron)) bonus += @divTrunc(self.config.bridge_activation_bonus, 2) else bonus -= @divTrunc(self.config.bridge_threshold_bonus, 4);
        }
        return bonus;
    }

    fn synapseContributionBonus(self: *const Network, synapse: Synapse) i32 {
        if (!self.config.use_reputation) return 0;
        return @divTrunc(@as(i32, synapse.reputation), 4);
    }

    fn canUseParallelScore(self: *const Network) bool {
        if (self.parallel_score_runtime == null) return false;
        return self.predictive_nodes.items.len >= self.config.parallel_score_min_predictive_nodes;
    }

    fn scoreContributionForSynapse(self: *const Network, neuron: Neuron, synapse: Synapse) i32 {
        var contribution = self.scaledValue(synapse.state) + self.synapseContributionBonus(synapse);
        if (neuron.kind == .memory_long) {
            contribution = @divTrunc(contribution * @as(i32, self.longTermContributionScalePpm(neuron)), 1000);
        }
        if (neuron.role == .bridge) {
            if (self.bridgeSatisfied(neuron)) {
                contribution = @divTrunc(contribution * @as(i32, self.config.bridge_bonus_ppm), 1000);
            } else {
                contribution = @divTrunc(contribution * 9, 10);
            }
        }
        return contribution;
    }

    fn numericCudaBaseContribution(self: *const Network, synapse: Synapse) i32 {
        return self.scaledValue(synapse.state) + self.synapseContributionBonus(synapse);
    }

    fn numericCudaLongScalePpm(self: *const Network, neuron: Neuron) u32 {
        if (neuron.kind != .memory_long) return 1000;
        return self.longTermContributionScalePpm(neuron);
    }

    fn numericCudaBridgeScalePpm(self: *const Network, neuron: Neuron) u32 {
        if (neuron.role != .bridge) return 1000;
        return if (self.bridgeSatisfied(neuron)) self.config.bridge_bonus_ppm else 900;
    }

    fn countPredictiveOutputEdges(self: *const Network) usize {
        var total: usize = 0;
        for (self.predictive_nodes.items) |src_id| {
            const src_idx: usize = @intCast(src_id);
            const neuron = self.neurons.items[src_idx];
            if (neuron.kind == .dead) continue;
            total += self.countOutputEdgesForNeuron(neuron);
        }
        return total;
    }

    fn countOutputEdgesForNeuron(self: *const Network, neuron: Neuron) usize {
        var total: usize = 0;
        for (neuron.outgoing.items) |synapse| {
            const target_idx: usize = @intCast(synapse.target);
            if (target_idx < self.neurons.items.len and self.neurons.items[target_idx].kind == .output) total += 1;
        }
        return total;
    }

    fn shouldAttemptCudaScore(self: *const Network, edge_count: usize) bool {
        if (self.numeric_cuda_runtime == null) return false;
        return switch (self.config.numeric_backend) {
            .cuda => true,
            .auto => edge_count >= self.config.cuda_min_scoring_edges,
            else => false,
        };
    }

    fn syncNumericCudaNeuron(self: *Network, id: u32) !void {
        const runtime = self.numeric_cuda_runtime orelse return;
        const idx: usize = @intCast(id);
        if (idx >= self.neurons.items.len) return;

        self.numeric_cuda_indices.clearRetainingCapacity();
        self.numeric_cuda_values.clearRetainingCapacity();

        const neuron = self.neurons.items[idx];
        for (neuron.outgoing.items) |synapse| {
            const target_idx: usize = @intCast(synapse.target);
            if (target_idx >= self.neurons.items.len) continue;
            if (self.neurons.items[target_idx].kind != .output) continue;
            const logical_index = target_idx - self.output_base;
            const contribution = self.numericCudaBaseContribution(synapse);
            if (contribution == 0) continue;
            try self.numeric_cuda_indices.append(self.allocator, @intCast(logical_index));
            try self.numeric_cuda_values.append(self.allocator, contribution);
        }
        try runtime.syncNeuronOutputEdges(id, self.numeric_cuda_indices.items, self.numeric_cuda_values.items);
    }

    fn syncDirtyNumericCudaNeurons(self: *Network) bool {
        if (self.numeric_cuda_runtime == null) return false;

        if (self.numeric_cuda_force_full_resync) {
            var neuron_id: usize = 0;
            while (neuron_id < self.neurons.items.len) : (neuron_id += 1) {
                self.syncNumericCudaNeuron(@intCast(neuron_id)) catch return false;
            }
            if (self.numeric_cuda_dirty_flags.items.len != 0) @memset(self.numeric_cuda_dirty_flags.items, 0);
            self.numeric_cuda_dirty_nodes.clearRetainingCapacity();
            self.numeric_cuda_force_full_resync = false;
            return true;
        }

        for (self.numeric_cuda_dirty_nodes.items) |dirty_id| {
            const dirty_idx: usize = @intCast(dirty_id);
            if (dirty_idx >= self.numeric_cuda_dirty_flags.items.len) continue;
            if (self.numeric_cuda_dirty_flags.items[dirty_idx] == 0) continue;
            self.syncNumericCudaNeuron(dirty_id) catch return false;
            self.numeric_cuda_dirty_flags.items[dirty_idx] = 0;
        }
        self.numeric_cuda_dirty_nodes.clearRetainingCapacity();
        return true;
    }

    fn fillRegionOutputScoresSerial(self: *Network) void {
        self.scorePredictiveRange(self.region_output_scores, 0, self.predictive_nodes.items.len);
        self.last_score_backend_used = .cpu;
    }

    fn fillRegionOutputScoresParallel(self: *Network) void {
        const runtime = self.parallel_score_runtime.?;
        const slot_count = runtime.slot_count;
        const chunk_size = @divTrunc(self.predictive_nodes.items.len + slot_count - 1, slot_count);
        for (0..slot_count) |slot_index| {
            const start_index = slot_index * chunk_size;
            const end_index = @min(self.predictive_nodes.items.len, start_index + chunk_size);
            runtime.tasks[slot_index] = .{
                .network = self,
                .start_index = start_index,
                .end_index = end_index,
            };
            if (slot_index == 0) continue;
            runtime.start_semaphores[slot_index - 1].post(score_parallel_io);
        }

        self.scorePredictiveRange(runtime.regionSlice(0), runtime.tasks[0].start_index, runtime.tasks[0].end_index);
        for (0..runtime.workerCount()) |_| runtime.completed.waitUncancelable(score_parallel_io);

        @memcpy(self.region_output_scores, runtime.regionSlice(0));
        for (1..slot_count) |slot_index| {
            const partial = runtime.regionSlice(slot_index);
            for (self.region_output_scores, partial) |*dst, value| dst.* += value;
        }
        self.last_score_backend_used = .cpu_mt;
    }

    fn fillRegionOutputScoresCuda(self: *Network, edge_count: usize) bool {
        if (!self.shouldAttemptCudaScore(edge_count)) return false;
        if (!self.syncDirtyNumericCudaNeurons()) return false;

        const predictive_len = self.predictive_nodes.items.len;
        self.numeric_cuda_region_bases.resize(self.allocator, predictive_len) catch return false;
        self.numeric_cuda_long_scales.resize(self.allocator, predictive_len) catch return false;
        self.numeric_cuda_bridge_scales.resize(self.allocator, predictive_len) catch return false;

        for (self.predictive_nodes.items, 0..) |src_id, predictive_index| {
            const src_idx: usize = @intCast(src_id);
            if (src_idx >= self.neurons.items.len) return false;
            const neuron = self.neurons.items[src_idx];
            const region = self.nodeRegion(src_id);
            self.numeric_cuda_region_bases.items[predictive_index] = @intCast(@as(usize, region) * @as(usize, self.config.vocab_size));
            self.numeric_cuda_long_scales.items[predictive_index] = self.numericCudaLongScalePpm(neuron);
            self.numeric_cuda_bridge_scales.items[predictive_index] = self.numericCudaBridgeScalePpm(neuron);
        }

        if (self.numeric_cuda_runtime) |runtime| {
            runtime.scoreResident(
                self.predictive_nodes.items,
                self.numeric_cuda_region_bases.items,
                self.numeric_cuda_long_scales.items,
                self.numeric_cuda_bridge_scales.items,
                self.region_output_scores,
            ) catch return false;
            self.last_score_backend_used = .cuda;
            return true;
        }
        return false;
    }

    fn scorePredictiveRange(self: *const Network, region_output_scores: []i32, start_index: usize, end_index: usize) void {
        @memset(region_output_scores, 0);
        var predictive_index = start_index;
        while (predictive_index < end_index) : (predictive_index += 1) {
            const src_id = self.predictive_nodes.items[predictive_index];
            const src_idx: usize = @intCast(src_id);
            const neuron = &self.neurons.items[src_idx];
            if (neuron.kind == .dead) continue;
            const region = self.nodeRegion(src_id);
            const base = @as(usize, region) * @as(usize, self.config.vocab_size);
            for (neuron.outgoing.items) |synapse| {
                const target_idx: usize = @intCast(synapse.target);
                if (self.neurons.items[target_idx].kind != .output) continue;
                const logical_index = target_idx - self.output_base;
                const contribution = self.scoreContributionForSynapse(neuron.*, synapse);
                region_output_scores[base + logical_index] += contribution;
            }
        }
    }

    fn fillRegionOutputScores(self: *Network) void {
        const edge_count = self.countPredictiveOutputEdges();
        switch (self.config.numeric_backend) {
            .cpu => self.fillRegionOutputScoresSerial(),
            .cpu_mt => {
                if (self.canUseParallelScore()) {
                    self.fillRegionOutputScoresParallel();
                } else {
                    self.fillRegionOutputScoresSerial();
                }
            },
            .cuda => {
                if (!self.fillRegionOutputScoresCuda(edge_count)) {
                    if (self.canUseParallelScore()) {
                        self.fillRegionOutputScoresParallel();
                    } else {
                        self.fillRegionOutputScoresSerial();
                    }
                }
            },
            .auto => {
                if (self.fillRegionOutputScoresCuda(edge_count)) return;
                if (self.canUseParallelScore()) {
                    self.fillRegionOutputScoresParallel();
                } else {
                    self.fillRegionOutputScoresSerial();
                }
            },
        }
    }

    fn effectiveThreshold(self: *const Network, neuron: Neuron) i32 {
        var threshold = neuron.threshold;
        if (neuron.kind == .memory_long) {
            threshold = @divTrunc(neuron.threshold * @as(i32, self.config.long_term_threshold_discount_ppm), 1000);
        }
        if (neuron.role == .bridge and neuron.secondary_region != cfg.invalid_region) {
            if (self.bridgeSatisfied(neuron)) threshold -= self.config.bridge_activation_bonus else threshold += self.config.bridge_threshold_bonus;
        }
        return threshold;
    }

    fn markActive(self: *Network, id: u32) !void {
        const idx: usize = @intCast(id);
        if (self.active_marks.items[idx] == self.mark_epoch) return;
        self.active_marks.items[idx] = self.mark_epoch;
        try self.active_now.append(self.allocator, id);
        try self.noteRegionActive(self.nodeRegion(id));
        const neuron = self.neurons.items[idx];
        if ((neuron.kind == .memory_short or neuron.kind == .memory_long) and neuron.role == .bridge) {
            self.bridge_activation_total += 1;
            if (self.bridgeSatisfied(neuron)) self.bridge_satisfied_total += 1;
        }
    }

    fn seedFromHistory(self: *Network, current_token: u8) !void {
        self.step_index += 1;
        self.mark_epoch +%= 1;
        if (self.mark_epoch == 0) {
            self.mark_epoch = 1;
            @memset(self.active_marks.items, 0);
            @memset(self.score_marks.items, 0);
            @memset(self.region_marks, 0);
        }
        self.active_now.clearRetainingCapacity();
        self.predictive_nodes.clearRetainingCapacity();
        self.active_regions.clearRetainingCapacity();
        self.frontier.clearRetainingCapacity();
        self.next_frontier.clearRetainingCapacity();
        self.touched.clearRetainingCapacity();

        const current_id = self.lagSensoryId(0, current_token);
        try self.markActive(current_id);
        try self.frontier.append(self.allocator, current_id);
        try self.predictive_nodes.append(self.allocator, current_id);

        const lag_count = @min(@as(usize, self.config.history_lags), self.recent_len + 1);
        for (1..lag_count) |lag| {
            const token = self.recent_tokens[lag - 1];
            const lag_id = self.lagSensoryId(@intCast(lag), token);
            try self.markActive(lag_id);
            try self.frontier.append(self.allocator, lag_id);
        }

        for (self.carry_memories.items) |memory_id| {
            const idx: usize = @intCast(memory_id);
            if (idx >= self.neurons.items.len) continue;
            const kind = self.neurons.items[idx].kind;
            if (kind != .memory_short and kind != .memory_long) continue;
            try self.markActive(memory_id);
            try self.frontier.append(self.allocator, memory_id);
        }
    }

    fn accumulateScore(self: *Network, target: u32, delta: i32) !void {
        const idx: usize = @intCast(target);
        if (self.score_marks.items[idx] != self.mark_epoch) {
            self.score_marks.items[idx] = self.mark_epoch;
            self.score_values.items[idx] = delta;
            try self.touched.append(self.allocator, target);
        } else {
            self.score_values.items[idx] += delta;
        }
    }

    fn considerCandidate(self: *Network, id: u32, score: i32, max_items: usize) !void {
        if (self.candidate_buffer.items.len < max_items) {
            try self.candidate_buffer.append(self.allocator, .{ .id = id, .score = score });
            return;
        }
        var min_index: usize = 0;
        var min_score = self.candidate_buffer.items[0].score;
        for (self.candidate_buffer.items, 0..) |candidate, idx| {
            if (candidate.score < min_score) {
                min_score = candidate.score;
                min_index = idx;
            }
        }
        if (score > min_score) {
            self.candidate_buffer.items[min_index] = .{ .id = id, .score = score };
        }
    }

    fn propagateMemories(self: *Network) !void {
        var hop: usize = 0;
        while (hop < self.config.propagation_depth and self.frontier.items.len > 0) : (hop += 1) {
            self.touched.clearRetainingCapacity();
            self.candidate_buffer.clearRetainingCapacity();
            for (self.frontier.items) |src_id| {
                const src_idx: usize = @intCast(src_id);
                const neuron = &self.neurons.items[src_idx];
                if (neuron.kind == .dead) continue;
                for (neuron.outgoing.items) |synapse| {
                    const target_idx: usize = @intCast(synapse.target);
                    const target_kind = self.neurons.items[target_idx].kind;
                    if (target_kind != .memory_short and target_kind != .memory_long) continue;
                    try self.accumulateScore(synapse.target, self.scaledValue(synapse.state) + self.synapseContributionBonus(synapse));
                }
            }

            self.next_frontier.clearRetainingCapacity();
            for (self.touched.items) |target_id| {
                const target_idx: usize = @intCast(target_id);
                const neuron = &self.neurons.items[target_idx];
                const kind = neuron.kind;
                if (kind != .memory_short and kind != .memory_long) continue;
                if (self.active_marks.items[target_idx] == self.mark_epoch) continue;
                const score = self.score_values.items[target_idx] + self.memoryContributionBonus(neuron.*);
                if (score < self.effectiveThreshold(neuron.*)) continue;
                try self.considerCandidate(target_id, score, self.config.max_hidden_per_hop);
            }

            for (self.candidate_buffer.items) |candidate| {
                const idx: usize = @intCast(candidate.id);
                try self.markActive(candidate.id);
                try self.predictive_nodes.append(self.allocator, candidate.id);
                try self.next_frontier.append(self.allocator, candidate.id);
                self.neurons.items[idx].last_active_step = self.step_index;
                self.neurons.items[idx].last_activation = candidate.score;
            }
            std.mem.swap(std.ArrayList(u32), &self.frontier, &self.next_frontier);
        }
    }

    fn recordExpertPrediction(self: *Network, expert_idx: usize, token: u8, score: i32, active: bool) void {
        self.last_expert_tokens[expert_idx] = token;
        self.last_expert_scores[expert_idx] = score;
        self.last_expert_active[expert_idx] = active;
    }

    fn recordPredictionAttribution(self: *Network, sban_top: ScoreTop, final_top: ScoreTop, actual_next: u8) void {
        if (sban_top.token == actual_next) self.sban_graph_correct += 1;
        if (final_top.token != sban_top.token) {
            self.hybrid_changed_top += 1;
            if (final_top.token == actual_next) self.hybrid_changed_top_correct += 1;
        }
        for (0..hybrid_expert_count) |idx| {
            if (!self.last_expert_active[idx]) continue;
            self.expert_active_total[idx] += 1;
            if (self.last_expert_tokens[idx] == actual_next) self.expert_correct_total[idx] += 1;
            if (self.last_expert_tokens[idx] == final_top.token) self.expert_final_match_total[idx] += 1;
        }
    }

    fn lookupOrder3Row(self: *const Network, key: u32) ?[]const u16 {
        const row_idx = self.order3_row_map.get(key) orelse return null;
        const row_len = @as(usize, self.config.vocab_size);
        const base = @as(usize, row_idx) * row_len;
        return self.order3_rows.items[base .. base + row_len];
    }

    fn getOrCreateOrder3Row(self: *Network, key: u32) ![]u16 {
        if (self.order3_row_map.get(key)) |row_idx| {
            const row_len = @as(usize, self.config.vocab_size);
            const base = @as(usize, row_idx) * row_len;
            return self.order3_rows.items[base .. base + row_len];
        }

        const row_len = @as(usize, self.config.vocab_size);
        const row_idx: u32 = @intCast(self.order3_rows.items.len / row_len);
        try self.order3_row_map.put(key, row_idx);
        const base = self.order3_rows.items.len;
        try self.order3_rows.resize(self.allocator, base + row_len);
        @memset(self.order3_rows.items[base .. base + row_len], 0);
        return self.order3_rows.items[base .. base + row_len];
    }

    fn lookupOrder4Row(self: *const Network, key: u32) ?[]const u16 {
        const row_idx = self.order4_row_map.get(key) orelse return null;
        const row_len = @as(usize, self.config.vocab_size);
        const base = @as(usize, row_idx) * row_len;
        return self.order4_rows.items[base .. base + row_len];
    }

    fn getOrCreateOrder4Row(self: *Network, key: u32) ![]u16 {
        if (self.order4_row_map.get(key)) |row_idx| {
            const row_len = @as(usize, self.config.vocab_size);
            const base = @as(usize, row_idx) * row_len;
            return self.order4_rows.items[base .. base + row_len];
        }

        const row_len = @as(usize, self.config.vocab_size);
        const row_idx: u32 = @intCast(self.order4_rows.items.len / row_len);
        try self.order4_row_map.put(key, row_idx);
        const base = self.order4_rows.items.len;
        try self.order4_rows.resize(self.allocator, base + row_len);
        @memset(self.order4_rows.items[base .. base + row_len], 0);
        return self.order4_rows.items[base .. base + row_len];
    }

    fn lookupOrder5Row(self: *const Network, key: u64) ?[]const u16 {
        const row_idx = self.order5_row_map.get(key) orelse return null;
        const row_len = @as(usize, self.config.vocab_size);
        const base = @as(usize, row_idx) * row_len;
        return self.order5_rows.items[base .. base + row_len];
    }

    fn getOrCreateOrder5Row(self: *Network, key: u64) ![]u16 {
        if (self.order5_row_map.get(key)) |row_idx| {
            const row_len = @as(usize, self.config.vocab_size);
            const base = @as(usize, row_idx) * row_len;
            return self.order5_rows.items[base .. base + row_len];
        }

        const row_len = @as(usize, self.config.vocab_size);
        const row_idx: u32 = @intCast(self.order5_rows.items.len / row_len);
        try self.order5_row_map.put(key, row_idx);
        const base = self.order5_rows.items.len;
        try self.order5_rows.resize(self.allocator, base + row_len);
        @memset(self.order5_rows.items[base .. base + row_len], 0);
        return self.order5_rows.items[base .. base + row_len];
    }

    fn continuationKey(self: *const Network, current_token: u8, order: u8) u64 {
        var hash = continuation_hash_offset;
        hash = hashByte(hash, order);
        var remaining: usize = order - 1;
        while (remaining > 0) {
            remaining -= 1;
            hash = hashByte(hash, self.recent_tokens[remaining]);
        }
        hash = hashByte(hash, current_token);
        return hash;
    }

    fn lookupContinuationCell(self: *const Network, key: u64) ?*const ContinuationCell {
        const row_idx = self.continuation_map.get(key) orelse return null;
        return &self.continuation_cells.items[row_idx];
    }

    fn getOrCreateContinuationCell(self: *Network, key: u64) !?*ContinuationCell {
        if (self.continuation_map.get(key)) |row_idx| {
            return &self.continuation_cells.items[row_idx];
        }
        if (self.config.continuation_max_cells != 0 and self.continuation_cells.items.len >= self.config.continuation_max_cells) {
            return null;
        }
        const row_idx: u32 = @intCast(self.continuation_cells.items.len);
        try self.continuation_map.put(key, row_idx);
        try self.continuation_cells.append(self.allocator, .{});
        return &self.continuation_cells.items[row_idx];
    }

    fn updateContinuationCell(cell: *ContinuationCell, actual_next: u8) void {
        if (cell.support == 0) {
            cell.token = actual_next;
            cell.vote = 1;
            cell.support = 1;
            return;
        }

        if (cell.token == actual_next) {
            if (cell.vote < std.math.maxInt(u16)) cell.vote += 1;
        } else if (cell.vote > 0) {
            cell.vote -= 1;
        } else {
            cell.token = actual_next;
            cell.vote = 1;
        }

        if (cell.support < std.math.maxInt(u16)) cell.support += 1;
    }

    fn continuationReliabilityPpm(self: *const Network, cell: ContinuationCell) u32 {
        if (cell.support < self.config.continuation_min_support or cell.vote == 0) return 0;
        const support_ppm = if (self.config.continuation_support_prior == 0)
            @as(u32, 1000)
        else
            @as(u32, @intCast(@divTrunc(@as(u64, cell.support) * 1000, @as(u64, cell.support) + @as(u64, self.config.continuation_support_prior))));
        const purity_ppm = @as(u32, @intCast(@divTrunc(@as(u64, cell.vote) * 1000, @as(u64, cell.support))));
        return @intCast(@divTrunc(@as(u64, support_ppm) * @as(u64, purity_ppm), 1000));
    }

    fn expertReliabilityPpm(self: *const Network, total: u32, top_count: u32, second_count: u32) u32 {
        if (total == 0 or top_count == 0 or top_count <= second_count) return 0;
        const gap = top_count - second_count;
        const support_ppm = if (self.config.hybrid_support_prior == 0)
            @as(u32, 1000)
        else
            @as(u32, @intCast(@divTrunc(@as(u64, total) * 1000, @as(u64, total) + @as(u64, self.config.hybrid_support_prior))));
        const evidence_ppm = if (self.config.hybrid_evidence_prior == 0)
            @as(u32, 1000)
        else
            @as(u32, @intCast(@divTrunc(@as(u64, gap) * 1000, @as(u64, gap) + @as(u64, self.config.hybrid_evidence_prior))));
        return @intCast(@divTrunc(@as(u64, support_ppm) * @as(u64, evidence_ppm), 1000));
    }

    fn blendDistribution(self: *Network, row: []const u32, base_bonus_ppm: u16, expert_idx: usize) void {
        if (!self.config.enable_hybrid_experts) return;
        var total: u32 = 0;
        var top_token: u8 = 0;
        var top_count: u32 = 0;
        var second_count: u32 = 0;
        for (row, 0..) |count, idx| {
            total +%= count;
            if (count > top_count) {
                second_count = top_count;
                top_count = count;
                top_token = @intCast(idx);
            } else if (count > second_count) {
                second_count = count;
            }
        }
        if (total == 0 or top_count == 0) {
            self.recordExpertPrediction(expert_idx, 0, 0, false);
            return;
        }
        const scaled_bonus = @divTrunc(@as(i32, base_bonus_ppm) * @as(i32, self.hybrid_weights[expert_idx]), 1024);
        const reliability_ppm: i32 = @intCast(self.expertReliabilityPpm(total, top_count, second_count));
        const effective_bonus = @divTrunc(scaled_bonus * reliability_ppm, 1000);
        if (effective_bonus == 0) {
            self.recordExpertPrediction(expert_idx, 0, 0, false);
            return;
        }
        for (row, 0..) |count, idx| {
            if (count == 0) continue;
            const delta: i32 = @intCast(@divTrunc(@as(i64, effective_bonus) * @as(i64, count), @as(i64, total)));
            self.output_scores.items[idx] += delta;
        }
        const confidence: i32 = @intCast(@divTrunc(@as(i64, effective_bonus) * @as(i64, top_count - second_count), @as(i64, total)));
        self.recordExpertPrediction(expert_idx, top_token, confidence, true);
    }

    fn blendDistributionU16(self: *Network, row: []const u16, base_bonus_ppm: u16, expert_idx: usize) void {
        if (!self.config.enable_hybrid_experts) return;
        var total: u32 = 0;
        var top_token: u8 = 0;
        var top_count: u16 = 0;
        var second_count: u16 = 0;
        for (row, 0..) |count, idx| {
            total +%= count;
            if (count > top_count) {
                second_count = top_count;
                top_count = count;
                top_token = @intCast(idx);
            } else if (count > second_count) {
                second_count = count;
            }
        }
        if (total == 0 or top_count == 0) {
            self.recordExpertPrediction(expert_idx, 0, 0, false);
            return;
        }
        const scaled_bonus = @divTrunc(@as(i32, base_bonus_ppm) * @as(i32, self.hybrid_weights[expert_idx]), 1024);
        const reliability_ppm: i32 = @intCast(self.expertReliabilityPpm(total, top_count, second_count));
        const effective_bonus = @divTrunc(scaled_bonus * reliability_ppm, 1000);
        if (effective_bonus == 0) {
            self.recordExpertPrediction(expert_idx, 0, 0, false);
            return;
        }
        for (row, 0..) |count, idx| {
            if (count == 0) continue;
            const delta: i32 = @intCast(@divTrunc(@as(i64, effective_bonus) * @as(i64, count), @as(i64, total)));
            self.output_scores.items[idx] += delta;
        }
        const confidence: i32 = @intCast(@divTrunc(@as(i64, effective_bonus) * @as(i64, top_count - second_count), @as(i64, total)));
        self.recordExpertPrediction(expert_idx, top_token, confidence, true);
    }

    fn applyBurstExpert(self: *Network, prev_token: u8, current_token: u8) void {
        if (!self.config.enable_hybrid_experts) return;
        const key = contextKey(prev_token, current_token);
        const token = self.burst_next[key];
        const streak = self.burst_streak[key];
        const last_step = self.burst_last_step[key];
        if (streak < self.config.burst_min_streak or last_step == 0) {
            self.recordExpertPrediction(expert_burst_idx, 0, 0, false);
            return;
        }
        const age = self.step_index -| last_step;
        if (age > self.config.burst_max_age) {
            self.recordExpertPrediction(expert_burst_idx, 0, 0, false);
            return;
        }
        const scaled_bonus = @divTrunc(@as(i32, self.config.burst_bonus_ppm) * @as(i32, self.hybrid_weights[expert_burst_idx]), 1024);
        const freshness_ppm: u32 = @intCast(@divTrunc(@as(u64, self.config.burst_max_age - age) * 1000, @max(@as(u64, 1), self.config.burst_max_age)));
        const streak_bonus = @min(@as(i32, streak), 6);
        const delta = @divTrunc(@divTrunc(scaled_bonus * streak_bonus, 2) * @as(i32, @intCast(freshness_ppm)), 1000);
        self.output_scores.items[token] += delta;
        self.recordExpertPrediction(expert_burst_idx, token, delta, true);
    }

    fn applyContinuationExpert(self: *Network, current_token: u8) void {
        if (!self.config.enable_hybrid_experts or self.config.continuation_bonus_ppm == 0) {
            self.recordExpertPrediction(expert_continuation_idx, 0, 0, false);
            return;
        }

        const max_order: usize = @min(@as(usize, self.config.continuation_max_order), @min(self.recent_len + 1, @as(usize, self.config.history_lags)));
        const min_order: usize = @max(@as(usize, self.config.continuation_min_order), 2);
        if (max_order < min_order) {
            self.recordExpertPrediction(expert_continuation_idx, 0, 0, false);
            return;
        }

        var order = max_order;
        while (true) {
            const key = self.continuationKey(current_token, @intCast(order));
            if (self.lookupContinuationCell(key)) |cell| {
                const reliability_ppm: i32 = @intCast(self.continuationReliabilityPpm(cell.*));
                if (reliability_ppm > 0) {
                    const scaled_bonus = @divTrunc(@as(i32, self.config.continuation_bonus_ppm) * @as(i32, self.hybrid_weights[expert_continuation_idx]), 1024);
                    const effective_bonus = @divTrunc(scaled_bonus * reliability_ppm, 1000);
                    if (effective_bonus > 0) {
                        self.output_scores.items[cell.token] += effective_bonus;
                        self.recordExpertPrediction(expert_continuation_idx, cell.token, effective_bonus, true);
                        return;
                    }
                }
            }

            if (order == min_order) break;
            order -= 1;
        }

        self.recordExpertPrediction(expert_continuation_idx, 0, 0, false);
    }

    fn applyHybridExperts(self: *Network, current_token: u8) ScoreTop {
        for (0..hybrid_expert_count) |idx| self.recordExpertPrediction(idx, 0, 0, false);
        const sban_top = findTop2(self.output_scores.items);
        self.recordExpertPrediction(expert_sban_idx, sban_top.token, sban_top.top_score - sban_top.second_score, true);
        self.blendDistribution(self.order1_counts[@as(usize, current_token) * @as(usize, self.config.vocab_size) .. (@as(usize, current_token) + 1) * @as(usize, self.config.vocab_size)], self.config.markov1_bonus_ppm, expert_markov1_idx);
        if (self.recent_len >= 1) {
            const prev_token = self.recent_tokens[0];
            const base = contextKey(prev_token, current_token) * @as(usize, self.config.vocab_size);
            self.blendDistribution(self.order2_counts[base .. base + @as(usize, self.config.vocab_size)], self.config.markov2_bonus_ppm, expert_markov2_idx);
            self.applyBurstExpert(prev_token, current_token);
            self.blendDistributionU16(self.recent_order2_counts[base .. base + @as(usize, self.config.vocab_size)], self.config.recent_markov2_bonus_ppm, expert_recent_markov2_idx);
        }
        if (self.recent_len >= 2) {
            const prev1 = self.recent_tokens[0];
            const prev2 = self.recent_tokens[1];
            const key3 = contextKey3(prev2, prev1, current_token);
            if (self.lookupOrder3Row(key3)) |row| {
                self.blendDistributionU16(row, self.config.markov3_bonus_ppm, expert_markov3_idx);
            }
        }
        if (self.recent_len >= 3) {
            const prev1 = self.recent_tokens[0];
            const prev2 = self.recent_tokens[1];
            const prev3 = self.recent_tokens[2];
            const key4 = contextKey4(prev3, prev2, prev1, current_token);
            if (self.lookupOrder4Row(key4)) |row| {
                self.blendDistributionU16(row, self.config.markov4_bonus_ppm, expert_markov4_idx);
            }
        }
        if (self.recent_len >= 4) {
            const prev1 = self.recent_tokens[0];
            const prev2 = self.recent_tokens[1];
            const prev3 = self.recent_tokens[2];
            const prev4 = self.recent_tokens[3];
            const key5 = contextKey5(prev4, prev3, prev2, prev1, current_token);
            if (self.lookupOrder5Row(key5)) |row| {
                self.blendDistributionU16(row, self.config.markov5_bonus_ppm, expert_markov5_idx);
            }
        }
        self.applyContinuationExpert(current_token);
        return sban_top;
    }

    fn updateRecentExpertWindow(self: *Network, current_token: u8, actual_next: u8) void {
        if (self.config.recent_expert_window == 0) return;
        const window: usize = @intCast(self.config.recent_expert_window);
        if (self.recent_ring_count == window) {
            const evict_idx = self.recent_row2_ring[self.recent_ring_pos];
            if (evict_idx != recent_row2_sentinel and self.recent_order2_counts[evict_idx] > 0) {
                self.recent_order2_counts[evict_idx] -= 1;
            }
        } else {
            self.recent_ring_count += 1;
        }
        var row2_idx: u32 = recent_row2_sentinel;
        if (self.recent_len >= 1) {
            const prev_token = self.recent_tokens[0];
            row2_idx = @intCast(contextKey(prev_token, current_token) * @as(usize, self.config.vocab_size) + @as(usize, actual_next));
            if (self.recent_order2_counts[row2_idx] < std.math.maxInt(u16)) self.recent_order2_counts[row2_idx] += 1;
        }
        self.recent_row2_ring[self.recent_ring_pos] = row2_idx;
        self.recent_ring_pos = (self.recent_ring_pos + 1) % window;
    }

    fn updateLocalExpertState(self: *Network, current_token: u8, actual_next: u8) void {
        self.updateRecentExpertWindow(current_token, actual_next);
        if (self.recent_len < 1) return;

        const prev_token = self.recent_tokens[0];
        const key = contextKey(prev_token, current_token);
        if (self.burst_next[key] == actual_next) {
            self.burst_streak[key] +|= 1;
        } else {
            self.burst_next[key] = actual_next;
            self.burst_streak[key] = 1;
        }
        self.burst_last_step[key] = self.step_index;
    }

    fn updateHybridExpertWeights(self: *Network, actual_next: u8) void {
        if (!self.config.enable_hybrid_experts) return;
        var staged: [hybrid_expert_count]i32 = undefined;
        var total_weight: i32 = 0;
        for (0..hybrid_expert_count) |idx| {
            var weight: i32 = self.hybrid_weights[idx];
            const target: i32 = default_hybrid_weights[idx];
            if (self.last_expert_active[idx]) {
                const strength_bonus: i32 = @divTrunc(@max(self.last_expert_scores[idx], 0), 48);
                if (self.last_expert_tokens[idx] == actual_next) {
                    weight += self.config.hybrid_reward + strength_bonus;
                } else {
                    const penalty_bonus: i32 = @divTrunc(@max(self.last_expert_scores[idx], 0), 96);
                    weight -= self.config.hybrid_penalty + penalty_bonus;
                }
            }
            if (idx == expert_recent_markov2_idx and self.last_expert_active[expert_recent_markov2_idx] and self.last_expert_tokens[expert_recent_markov2_idx] == actual_next and self.last_expert_tokens[expert_markov2_idx] != actual_next and self.last_expert_scores[expert_recent_markov2_idx] > self.last_expert_scores[expert_markov2_idx]) {
                weight += self.config.hybrid_recent_drift_bonus;
            }
            if (weight > target) weight -= self.config.hybrid_decay else if (weight < target) weight += self.config.hybrid_decay;
            if (weight < self.config.hybrid_weight_min) weight = self.config.hybrid_weight_min;
            if (weight > self.config.hybrid_weight_max) weight = self.config.hybrid_weight_max;
            staged[idx] = weight;
            total_weight += weight;
        }
        const share: i32 = self.config.hybrid_share_ppm;
        const mean_weight: i32 = @divTrunc(total_weight, @as(i32, hybrid_expert_count));
        for (0..hybrid_expert_count) |idx| {
            var weight = staged[idx];
            if (share > 0) {
                weight = @divTrunc(weight * (1000 - share) + mean_weight * share, 1000);
            }
            if (weight < self.config.hybrid_weight_min) weight = self.config.hybrid_weight_min;
            if (weight > self.config.hybrid_weight_max) weight = self.config.hybrid_weight_max;
            self.hybrid_weights[idx] = @intCast(weight);
        }
    }

    fn updateSequenceExperts(self: *Network, current_token: u8, actual_next: u8) !void {
        const row1_idx = @as(usize, current_token) * @as(usize, self.config.vocab_size) + @as(usize, actual_next);
        self.order1_counts[row1_idx] +|= 1;
        self.updateLocalExpertState(current_token, actual_next);
        if (self.recent_len >= 1) {
            const prev_token = self.recent_tokens[0];
            const key = contextKey(prev_token, current_token);
            const row2_idx = key * @as(usize, self.config.vocab_size) + @as(usize, actual_next);
            self.order2_counts[row2_idx] +|= 1;
        }
        if (self.config.markov3_bonus_ppm != 0 and self.recent_len >= 2) {
            const prev1 = self.recent_tokens[0];
            const prev2 = self.recent_tokens[1];
            const row = try self.getOrCreateOrder3Row(contextKey3(prev2, prev1, current_token));
            const next_idx = @as(usize, actual_next);
            if (row[next_idx] < std.math.maxInt(u16)) row[next_idx] += 1;
        }
        if (self.config.markov4_bonus_ppm != 0 and self.recent_len >= 3) {
            const prev1 = self.recent_tokens[0];
            const prev2 = self.recent_tokens[1];
            const prev3 = self.recent_tokens[2];
            const row = try self.getOrCreateOrder4Row(contextKey4(prev3, prev2, prev1, current_token));
            const next_idx = @as(usize, actual_next);
            if (row[next_idx] < std.math.maxInt(u16)) row[next_idx] += 1;
        }
        if (self.config.markov5_bonus_ppm != 0 and self.recent_len >= 4) {
            const prev1 = self.recent_tokens[0];
            const prev2 = self.recent_tokens[1];
            const prev3 = self.recent_tokens[2];
            const prev4 = self.recent_tokens[3];
            const row = try self.getOrCreateOrder5Row(contextKey5(prev4, prev3, prev2, prev1, current_token));
            const next_idx = @as(usize, actual_next);
            if (row[next_idx] < std.math.maxInt(u16)) row[next_idx] += 1;
        }

        const continuation_enabled = self.config.enable_hybrid_experts and self.config.continuation_bonus_ppm != 0 and self.config.continuation_max_order >= 2;
        const max_order: usize = @min(@as(usize, self.config.continuation_max_order), @min(self.recent_len + 1, @as(usize, self.config.history_lags)));
        const min_order: usize = @max(@as(usize, self.config.continuation_min_order), 2);
        if (continuation_enabled and max_order >= min_order) {
            var order = min_order;
            while (order <= max_order) : (order += 1) {
                if (try self.getOrCreateContinuationCell(self.continuationKey(current_token, @intCast(order)))) |cell| {
                    updateContinuationCell(cell, actual_next);
                }
            }
        }
    }

    fn scoreOutputs(self: *Network, current_token: u8, actual_next: u8) Prediction {
        @memset(self.output_scores.items, 0);
        self.fillRegionOutputScores();

        for (self.active_regions.items) |region| {
            const base = @as(usize, region) * @as(usize, self.config.vocab_size);
            for (self.output_scores.items, 0..) |*score, idx| {
                score.* += self.region_output_scores[base + idx];
            }
        }
        if (self.active_regions.items.len > self.max_active_regions_seen) {
            self.max_active_regions_seen = @intCast(self.active_regions.items.len);
        }

        const sban_top = self.applyHybridExperts(current_token);
        const top = findTop2(self.output_scores.items);
        self.recordPredictionAttribution(sban_top, top, actual_next);
        const top_token = top.token;
        const top_score = top.top_score;
        const second_score = top.second_score;
        const actual_score = self.output_scores.items[actual_next];
        var actual_rank: u16 = 1;
        for (self.output_scores.items) |score| {
            if (score > actual_score) actual_rank += 1;
        }
        return .{
            .token = top_token,
            .top_score = top_score,
            .margin = top_score - second_score,
            .actual_rank = actual_rank,
            .actual_score = actual_score,
            .active_count = @intCast(self.active_now.items.len),
            .surprise = false,
        };
    }

    fn longTermContributionScalePpm(self: *const Network, neuron: Neuron) u16 {
        if (neuron.kind != .memory_long) return 1000;
        const precision = self.precisionPpm(neuron);
        const low = self.config.long_term_low_precision_scale_ppm;
        const high = self.config.long_term_bonus_ppm;
        const gate = self.config.long_term_bonus_precision_ppm;
        if (precision >= gate) return high;
        const floor: u16 = 400;
        const clamped = if (precision < floor) floor else precision;
        const span = if (gate > floor) gate - floor else 1;
        const num = @as(u32, clamped - floor) * @as(u32, high - low);
        return @intCast(@as(u32, low) + @divTrunc(num, span));
    }

    fn longMemorySelectionBonus(self: *const Network, neuron: Neuron) i32 {
        if (neuron.kind != .memory_long) return 0;
        const precision = self.precisionPpm(neuron);
        if (precision >= self.config.long_term_bonus_precision_ppm) return 64;
        return -@as(i32, self.config.long_term_quality_penalty);
    }

    fn sortU32(ids: []u32) void {
        var i: usize = 1;
        while (i < ids.len) : (i += 1) {
            const value = ids[i];
            var j = i;
            while (j > 0 and ids[j - 1] > value) : (j -= 1) {
                ids[j] = ids[j - 1];
            }
            ids[j] = value;
        }
    }

    fn sortCandidatesDesc(candidates: []Candidate) void {
        var i: usize = 1;
        while (i < candidates.len) : (i += 1) {
            const value = candidates[i];
            var j = i;
            while (j > 0 and candidates[j - 1].score < value.score) : (j -= 1) {
                candidates[j] = candidates[j - 1];
            }
            candidates[j] = value;
        }
    }

    fn collectBirthParents(self: *Network, current_token: u8, parent_ids: *[24]u32) usize {
        var count: usize = 0;
        const max_parents = @min(@as(usize, self.config.max_parents_per_new_memory), parent_ids.len);
        const lag_limit = @min(@as(usize, self.config.max_lag_parents), max_parents);
        const available_lags = @min(lag_limit, self.recent_len + 1);
        if (available_lags >= 1) {
            parent_ids[count] = self.lagSensoryId(0, current_token);
            count += 1;
        }
        var lag: usize = 1;
        while (lag < available_lags and count < max_parents) : (lag += 1) {
            parent_ids[count] = self.lagSensoryId(@intCast(lag), self.recent_tokens[lag - 1]);
            count += 1;
        }

        var memories: [128]Candidate = undefined;
        var memory_count: usize = 0;
        for (self.active_now.items) |id| {
            const idx: usize = @intCast(id);
            const neuron = self.neurons.items[idx];
            if (neuron.kind != .memory_short and neuron.kind != .memory_long) continue;
            if (memory_count < memories.len) {
                var score = neuron.last_activation + @as(i32, neuron.utility) * 8;
                if (self.config.use_reputation) score += @as(i32, neuron.reputation) * 4;
                score += self.longMemorySelectionBonus(neuron);
                memories[memory_count] = .{ .id = id, .score = score };
                memory_count += 1;
            }
        }
        sortCandidatesDesc(memories[0..memory_count]);
        for (memories[0..memory_count]) |candidate| {
            if (count >= max_parents) break;
            parent_ids[count] = candidate.id;
            count += 1;
        }
        sortU32(parent_ids[0..count]);
        return count;
    }

    fn signatureForParents(parent_ids: []const u32, actual_next: u8) u64 {
        var hash = std.hash.Wyhash.init(0x51A2_D3E4_F5B6_8790);
        hash.update(std.mem.asBytes(&actual_next));
        for (parent_ids) |id| hash.update(std.mem.asBytes(&id));
        return hash.final();
    }

    fn precisionPpm(self: *const Network, neuron: Neuron) u16 {
        _ = self;
        const total = @as(u32, neuron.wins) + @as(u32, neuron.losses);
        if (total == 0) return 500;
        return @intCast((@as(u32, neuron.wins) * 1000) / total);
    }

    fn regionMemoryCount(self: *const Network, region: u16) u32 {
        const idx: usize = region;
        if (idx >= self.regions.items.len) return 0;
        const entry = self.regions.items[idx];
        return entry.live_short + entry.live_long;
    }

    fn regionChoiceFromParents(self: *const Network, parent_ids: []const u32) struct { primary: u16, secondary: u16, diversity: u8 } {
        var counts: [32]u16 = [_]u16{0} ** 32;
        var primary: u16 = 0;
        var secondary: u16 = cfg.invalid_region;
        var primary_count: u16 = 0;
        var secondary_count: u16 = 0;
        var diversity: u8 = 0;
        for (parent_ids) |id| {
            const region = self.nodeRegion(id);
            const idx: usize = region;
            if (idx >= counts.len or idx >= self.open_region_count) continue;
            if (counts[idx] == 0) diversity += 1;
            counts[idx] +|= 1;
            if (counts[idx] > primary_count) {
                if (region != primary) {
                    secondary = primary;
                    secondary_count = primary_count;
                }
                primary = region;
                primary_count = counts[idx];
            } else if (region != primary and counts[idx] > secondary_count) {
                secondary = region;
                secondary_count = counts[idx];
            }
        }
        if (primary_count == 0) primary = 0;
        if (secondary_count == 0) secondary = cfg.invalid_region;
        return .{ .primary = primary, .secondary = secondary, .diversity = diversity };
    }

    fn regionErrorPpm(self: *const Network, region: u16) u16 {
        const idx: usize = region;
        if (idx >= self.regions.items.len) return 500;
        const entry = self.regions.items[idx];
        const total = @as(u32, entry.recent_correct) + @as(u32, entry.recent_wrong);
        if (total < 8) return 500;
        return @intCast((@as(u32, entry.recent_wrong) * 1000) / total);
    }

    fn shouldCreateBridge(self: *const Network, primary: u16, secondary: u16, diversity: u8, prediction: Prediction) bool {
        if (!self.config.enable_bridge_memories) return false;
        if (secondary == cfg.invalid_region or diversity < self.config.bridge_birth_min_diversity) return false;
        const surprise_gate = prediction.actual_rank > 6 or prediction.margin < 0;
        if (!surprise_gate) return false;

        const primary_error = self.regionErrorPpm(primary);
        const secondary_error = self.regionErrorPpm(secondary);
        const error_gap: u16 = if (secondary_error > primary_error) secondary_error - primary_error else 0;
        if (secondary_error >= self.config.bridge_error_gate_ppm and error_gap >= self.config.bridge_error_gap_ppm) {
            return true;
        }
        if (diversity >= self.config.bridge_fallback_diversity and prediction.actual_rank > 12 and prediction.margin < 0 and secondary_error + self.config.bridge_retire_error_slack_ppm >= primary_error) {
            return true;
        }
        return false;
    }

    fn bestMergeTarget(self: *const Network, donor: u16) ?u16 {
        var best: ?u16 = null;
        var best_score: i32 = std.math.minInt(i32);
        for (0..self.open_region_count) |idx_usize| {
            const idx: u16 = @intCast(idx_usize);
            if (idx == donor) continue;
            const live = self.regionMemoryCount(idx);
            if (live == 0) continue;
            const err_ppm = self.regionErrorPpm(idx);
            const score = @as(i32, @intCast(live)) * 4 - @as(i32, err_ppm);
            if (score > best_score) {
                best_score = score;
                best = idx;
            }
        }
        return best;
    }

    fn mergeTailRegionInto(self: *Network, donor: u16, target: u16) void {
        if (donor == target or donor + 1 != self.open_region_count) return;

        var converted_bridge_count: u32 = 0;
        for (self.neurons.items) |*neuron| {
            switch (neuron.kind) {
                .memory_short, .memory_long => {
                    if (neuron.region == donor) neuron.region = target;
                    if (neuron.secondary_region == donor) neuron.secondary_region = target;
                    if (neuron.role == .bridge and neuron.secondary_region == neuron.region) {
                        neuron.role = .local;
                        neuron.secondary_region = cfg.invalid_region;
                        converted_bridge_count +|= 1;
                    }
                },
                else => {},
            }
        }

        self.regions.items[target].live_short +|= self.regions.items[donor].live_short;
        self.regions.items[target].live_long +|= self.regions.items[donor].live_long;
        self.regions.items[target].live_bridge +|= self.regions.items[donor].live_bridge;
        if (self.regions.items[target].live_bridge >= converted_bridge_count) {
            self.regions.items[target].live_bridge -= converted_bridge_count;
        } else {
            self.regions.items[target].live_bridge = 0;
        }
        self.regions.items[target].recent_births +|= self.regions.items[donor].recent_births;
        self.regions.items[target].recent_active +|= self.regions.items[donor].recent_active;
        self.regions.items[target].recent_correct +|= self.regions.items[donor].recent_correct;
        self.regions.items[target].recent_wrong +|= self.regions.items[donor].recent_wrong;
        if (self.regions.items[donor].last_active_step > self.regions.items[target].last_active_step) {
            self.regions.items[target].last_active_step = self.regions.items[donor].last_active_step;
        }
        self.regions.items[donor] = .{};
        self.open_region_count -= 1;
        self.signature_map.clearRetainingCapacity();
        self.rebalanceRegionTargets();
    }

    fn compactTailRegions(self: *Network) void {
        if (!self.config.enable_region_compaction) return;
        while (self.open_region_count > self.config.initial_regions) {
            const donor: u16 = self.open_region_count - 1;
            const live = self.regionMemoryCount(donor);
            const idle = self.step_index - self.regions.items[donor].last_active_step;
            if (live == 0) {
                self.regions.items[donor] = .{};
                self.open_region_count -= 1;
                self.rebalanceRegionTargets();
                continue;
            }
            if (live > self.config.region_merge_live_threshold or idle < self.config.region_merge_idle) break;
            if (self.bestMergeTarget(donor)) |target| {
                self.mergeTailRegionInto(donor, target);
            } else {
                break;
            }
        }
    }

    fn adjustIncomingSynapseReputation(self: *Network, memory_id: u32, delta: i16) void {
        if (!self.config.use_reputation) return;
        for (self.active_now.items) |parent_id| {
            if (parent_id == memory_id) continue;
            if (self.getSynapsePtr(parent_id, memory_id)) |synapse| {
                synapse.reputation = clampI16(@as(i32, synapse.reputation) + delta);
            }
        }
    }

    fn recordElasticityStep(self: *Network, was_correct: bool, surprise_like: bool, confident_like: bool) void {
        self.interval_steps +|= 1;
        if (surprise_like) self.interval_surprises +|= 1;
        if (was_correct) self.interval_correct +|= 1;
        if (confident_like) self.interval_confident +|= 1;
        for (self.active_regions.items) |region| {
            const idx: usize = region;
            if (idx >= self.regions.items.len) continue;
            if (was_correct) {
                self.regions.items[idx].recent_correct +|= 1;
            } else {
                self.regions.items[idx].recent_wrong +|= 1;
            }
        }
    }

    fn adjustElasticity(self: *Network) void {
        if (!self.config.enable_elasticity) return;
        if (self.interval_steps == 0) return;

        const surprise_ppm: u32 = (self.interval_surprises * 1_000_000) / self.interval_steps;
        const confident_ppm: u32 = (self.interval_confident * 1_000_000) / self.interval_steps;
        const util_ppm: u32 = if (self.global_short_target == 0) 0 else @intCast((self.alive_short_memories * 1_000_000) / self.global_short_target);
        var changed = false;

        if (((surprise_ppm > self.config.growth_surprise_ppm) and (util_ppm > self.config.growth_utilization_ppm)) or self.interval_births >= self.config.growth_birth_threshold) {
            const next_target = @min(self.config.max_short_memories, self.global_short_target + self.config.growth_step);
            if (next_target != self.global_short_target) {
                self.global_short_target = next_target;
                self.elastic_grows += 1;
                changed = true;
            }
        } else if (surprise_ppm < self.config.collapse_surprise_ppm and confident_ppm >= self.config.collapse_confident_ppm and self.interval_births <= self.config.shrink_birth_threshold and self.global_short_target > self.config.min_short_target and self.alive_short_memories + self.config.collapse_shrink_step < self.global_short_target) {
            const next_target = @max(self.config.min_short_target, self.global_short_target - self.config.collapse_shrink_step);
            if (next_target != self.global_short_target) {
                self.global_short_target = next_target;
                self.elastic_shrinks += 1;
                changed = true;
            }
        } else if (surprise_ppm < self.config.shrink_surprise_ppm and self.interval_births <= self.config.shrink_birth_threshold and self.global_short_target > self.config.min_short_target and self.alive_short_memories + self.config.shrink_step < self.global_short_target) {
            const next_target = @max(self.config.min_short_target, self.global_short_target - self.config.shrink_step);
            if (next_target != self.global_short_target) {
                self.global_short_target = next_target;
                self.elastic_shrinks += 1;
                changed = true;
            }
        }

        var heaviest: u32 = 0;
        for (self.regions.items[0..self.open_region_count]) |region| {
            const live = region.live_short + region.live_long;
            if (live > heaviest) heaviest = live;
        }
        if (heaviest > self.config.region_split_load and self.open_region_count < self.config.max_regions) {
            self.maybeGrowOpenRegions(self.open_region_count + 1);
            changed = true;
        } else {
            const desired_regions_u32 = @max(@as(u32, self.config.initial_regions), (self.alive_short_memories + self.config.region_split_load - 1) / self.config.region_split_load);
            const desired_regions: u16 = @intCast(@min(@as(u32, self.config.max_regions), desired_regions_u32));
            if (desired_regions > self.open_region_count) {
                self.maybeGrowOpenRegions(desired_regions);
                changed = true;
            }
        }

        if (changed) self.rebalanceRegionTargets();
        self.compactTailRegions();
        self.interval_steps = 0;
        self.interval_surprises = 0;
        self.interval_births = 0;
        self.interval_correct = 0;
        self.interval_confident = 0;
        for (self.regions.items) |*region| {
            region.recent_births = 0;
            region.recent_active = 0;
            region.recent_correct = 0;
            region.recent_wrong = 0;
        }
    }

    fn weakestOutgoingIndex(self: *Network, synapses: []const Synapse) usize {
        var weakest_index: usize = 0;
        var weakest_score: i32 = std.math.maxInt(i32);
        for (synapses, 0..) |synapse, idx| {
            const strength = @as(i32, synapse.permanence) * 16 + absI16(synapse.state) + @divTrunc(@as(i32, synapse.reputation), 2);
            const age_penalty: i32 = @intCast((self.step_index - synapse.last_touched) / 512);
            const score = strength - age_penalty;
            if (score < weakest_score) {
                weakest_score = score;
                weakest_index = idx;
            }
        }
        return weakest_index;
    }

    fn enforceOutgoingBudget(self: *Network, neuron: *Neuron) void {
        const limit = self.config.max_outgoing_per_node;
        while (neuron.outgoing.items.len > limit) {
            const remove_index = self.weakestOutgoingIndex(neuron.outgoing.items);
            const last_index = neuron.outgoing.items.len - 1;
            neuron.outgoing.items[remove_index] = neuron.outgoing.items[last_index];
            neuron.outgoing.items.len = last_index;
            self.pruned_synapses += 1;
        }
    }

    fn touchOrCreateSynapse(self: *Network, src_id: u32, target_id: u32, make_positive: bool, strong: bool) !void {
        const src_idx: usize = @intCast(src_id);
        const neuron = &self.neurons.items[src_idx];
        const rep_delta: i32 = if (strong) 3 else 1;
        const permanence_bonus: u8 = if (strong) 2 else 0;
        const target_idx: usize = @intCast(target_id);
        const target_is_output = target_idx < self.neurons.items.len and self.neurons.items[target_idx].kind == .output;
        for (neuron.outgoing.items) |*synapse| {
            if (synapse.target != target_id) continue;
            if (make_positive) {
                self.nudgePositive(&synapse.state);
                if (strong) self.nudgePositive(&synapse.state);
                if (self.config.use_reputation) synapse.reputation = clampI16(@as(i32, synapse.reputation) + rep_delta);
            } else {
                self.nudgeNegative(&synapse.state);
                if (strong) self.nudgeNegative(&synapse.state);
                if (self.config.use_reputation) synapse.reputation = clampI16(@as(i32, synapse.reputation) - rep_delta);
            }
            synapse.permanence = @min(self.config.synapse_max_permanence, synapse.permanence + 1);
            synapse.last_touched = self.step_index;
            if (target_is_output) self.markNumericCudaNeuronDirty(src_id);
            return;
        }
        const output_count_before = self.countOutputEdgesForNeuron(neuron.*);
        const init_state = if (make_positive) self.positiveState(strong) else self.negativeState(strong);
        const init_rep: i16 = if (self.config.use_reputation) clampI16(if (make_positive) rep_delta else -rep_delta) else 0;
        try neuron.outgoing.append(self.allocator, .{
            .target = target_id,
            .state = init_state,
            .permanence = @min(self.config.synapse_max_permanence, self.config.synapse_init_permanence + permanence_bonus),
            .reputation = init_rep,
            .last_touched = self.step_index,
        });
        self.enforceOutgoingBudget(neuron);
        if (target_is_output or self.countOutputEdgesForNeuron(neuron.*) != output_count_before) {
            self.markNumericCudaNeuronDirty(src_id);
        }
    }

    fn getSynapsePtr(self: *Network, src_id: u32, target_id: u32) ?*Synapse {
        const src_idx: usize = @intCast(src_id);
        const neuron = &self.neurons.items[src_idx];
        for (neuron.outgoing.items) |*synapse| {
            if (synapse.target == target_id) return synapse;
        }
        return null;
    }

    fn spawnMemory(self: *Network, current_token: u8, actual_next: u8, prediction: Prediction) !void {
        if (self.step_index - self.last_birth_step < self.config.birth_cooldown) return;
        if (self.alive_short_memories >= self.config.max_short_memories) return;
        if (self.alive_short_memories >= @min(self.config.max_short_memories, self.global_short_target + self.config.growth_step)) return;

        var parent_ids: [24]u32 = undefined;
        const parent_count = self.collectBirthParents(current_token, &parent_ids);
        const pressured_birth = self.birthPressureHigh();
        const saturated_birth = self.birthSaturationHigh();
        const severe_surprise = self.severeSurprise(prediction);
        const min_parents_required: usize = self.config.min_parents_for_birth + @as(u16, if (pressured_birth and !severe_surprise) self.config.birth_pressure_parent_boost else 0) + @as(u16, if (saturated_birth and !severe_surprise) self.config.birth_saturation_parent_boost else 0);
        if (parent_count < min_parents_required) return;

        var region_choice = self.regionChoiceFromParents(parent_ids[0..parent_count]);
        if (self.config.enable_elasticity and self.regionMemoryCount(region_choice.primary) >= self.regions.items[region_choice.primary].target_short and self.open_region_count < self.config.max_regions) {
            self.maybeGrowOpenRegions(self.open_region_count + 1);
            region_choice.primary = self.open_region_count - 1;
        }
        const create_bridge = self.shouldCreateBridge(region_choice.primary, region_choice.secondary, region_choice.diversity, prediction);

        var signature = signatureForParents(parent_ids[0..parent_count], actual_next);
        signature ^= (@as(u64, region_choice.primary) << 8);
        if (create_bridge) {
            signature ^= 0x9E37_79B9_7F4A_7C15;
            signature ^= (@as(u64, region_choice.secondary) << 24);
        }
        if (self.signature_map.get(signature)) |existing_id| {
            const existing_idx: usize = @intCast(existing_id);
            if (existing_idx < self.neurons.items.len) {
                const kind = self.neurons.items[existing_idx].kind;
                if (kind == .memory_short or kind == .memory_long) {
                    for (parent_ids[0..parent_count]) |parent_id| {
                        try self.touchOrCreateSynapse(parent_id, existing_id, true, true);
                    }
                    try self.touchOrCreateSynapse(existing_id, self.output_ids.items[actual_next], true, true);
                    self.neurons.items[existing_idx].support +|= 1;
                    self.neurons.items[existing_idx].reputation = clampI16(@as(i32, self.neurons.items[existing_idx].reputation) + 1);
                    return;
                }
            }
            _ = self.signature_map.remove(signature);
        }

        const pressure_bonus: i32 = if (pressured_birth and !severe_surprise) self.config.birth_pressure_threshold_bonus else 0;
        const saturation_bonus: i32 = if (saturated_birth and !severe_surprise) self.config.birth_saturation_threshold_bonus else 0;
        const threshold = cfg.score_scale * maxIntI32(2, @intCast(parent_count - 1)) + if (create_bridge) self.config.bridge_threshold_bonus else 0 + pressure_bonus + saturation_bonus;
        const memory_id = try self.addMemoryNeuron(.memory_short, threshold);
        const memory_idx: usize = @intCast(memory_id);
        self.neurons.items[memory_idx].signature = signature;
        self.neurons.items[memory_idx].role = if (create_bridge) .bridge else .local;
        self.neurons.items[memory_idx].region = region_choice.primary;
        self.neurons.items[memory_idx].secondary_region = if (create_bridge) region_choice.secondary else cfg.invalid_region;
        self.neurons.items[memory_idx].utility = if (create_bridge) 2 else 1;
        self.neurons.items[memory_idx].support = 1;
        self.neurons.items[memory_idx].reputation = if (create_bridge) 2 else 1;
        self.neurons.items[memory_idx].birth_step = self.step_index;
        self.neurons.items[memory_idx].last_active_step = self.step_index;
        self.neurons.items[memory_idx].last_activation = threshold;
        try self.signature_map.put(signature, memory_id);

        for (parent_ids[0..parent_count]) |parent_id| {
            try self.touchOrCreateSynapse(parent_id, memory_id, true, true);
        }
        try self.touchOrCreateSynapse(memory_id, self.output_ids.items[actual_next], true, true);
        self.alive_short_memories += 1;
        self.births += 1;
        self.interval_births +|= 1;
        self.regions.items[region_choice.primary].live_short +|= 1;
        self.regions.items[region_choice.primary].recent_births +|= 1;
        if (create_bridge) {
            self.bridge_births += 1;
            self.regions.items[region_choice.primary].live_bridge +|= 1;
        }
        self.last_birth_step = self.step_index;
    }

    fn updateSynapseReputation(self: *Network, src_id: u32, target_id: u32, delta: i16) void {
        if (!self.config.use_reputation) return;
        if (self.getSynapsePtr(src_id, target_id)) |synapse| {
            const old_bonus = @divTrunc(@as(i32, synapse.reputation), 4);
            synapse.reputation = clampI16(@as(i32, synapse.reputation) + delta);
            const new_bonus = @divTrunc(@as(i32, synapse.reputation), 4);
            const target_idx: usize = @intCast(target_id);
            if (old_bonus != new_bonus and target_idx < self.neurons.items.len and self.neurons.items[target_idx].kind == .output) {
                self.markNumericCudaNeuronDirty(src_id);
            }
        }
    }

    fn updateUtilities(self: *Network, prediction: Prediction, actual_next: u8) void {
        const was_correct = prediction.token == actual_next;
        for (self.predictive_nodes.items) |id| {
            const idx: usize = @intCast(id);
            var neuron = &self.neurons.items[idx];
            const kind = neuron.kind;
            if (kind != .memory_short and kind != .memory_long) continue;

            if (was_correct) {
                neuron.utility = @min(@as(i16, 64), neuron.utility + 1);
                neuron.support +|= 1;
                neuron.wins +|= 1;
                const reward: i32 = if (neuron.role == .bridge) 3 else 2;
                neuron.reputation = clampI16(@as(i32, neuron.reputation) + reward);
                self.updateSynapseReputation(id, self.output_ids.items[actual_next], 2);
                self.adjustIncomingSynapseReputation(id, 1);
                if (neuron.role == .bridge and neuron.secondary_region != cfg.invalid_region) {
                    const primary_error = self.regionErrorPpm(neuron.region);
                    const secondary_error = self.regionErrorPpm(neuron.secondary_region);
                    if (secondary_error + self.config.bridge_retire_error_slack_ppm < primary_error) {
                        neuron.utility = @max(@as(i16, -64), neuron.utility - 1);
                        neuron.reputation = clampI16(@as(i32, neuron.reputation) - 1);
                    }
                }
            } else if (prediction.actual_rank <= 5) {
                neuron.support +|= 1;
                if (self.config.use_reputation) neuron.reputation = clampI16(@as(i32, neuron.reputation) + 1);
                self.updateSynapseReputation(id, self.output_ids.items[actual_next], 1);
                self.adjustIncomingSynapseReputation(id, 1);
            } else {
                neuron.utility = @max(@as(i16, -64), neuron.utility - 1);
                neuron.losses +|= 1;
                const penalty: i32 = if (kind == .memory_long) 3 else 2;
                const extra_penalty: i32 = if (neuron.role == .bridge) 1 else 0;
                neuron.reputation = clampI16(@as(i32, neuron.reputation) - penalty - extra_penalty);
                self.adjustIncomingSynapseReputation(id, -1);
                if (prediction.token != actual_next) {
                    self.updateSynapseReputation(id, self.output_ids.items[prediction.token], -2);
                }
            }
            neuron.last_active_step = self.step_index;
        }
    }

    fn promoteMemory(self: *Network, id: u32) void {
        const idx: usize = @intCast(id);
        var neuron = &self.neurons.items[idx];
        if (neuron.kind != .memory_short) return;
        if (!self.config.enable_long_term) return;
        if (self.alive_long_memories >= self.config.max_long_memories) return;
        neuron.kind = .memory_long;
        neuron.threshold = @divTrunc(neuron.threshold * @as(i32, self.config.long_term_threshold_discount_ppm), 1000);
        neuron.utility = @min(@as(i16, 64), neuron.utility + 2);
        self.alive_short_memories -= 1;
        self.alive_long_memories += 1;
        self.regions.items[neuron.region].live_short -= 1;
        self.regions.items[neuron.region].live_long += 1;
        self.promotions += 1;
        for (neuron.outgoing.items) |*synapse| {
            synapse.permanence = @max(synapse.permanence, @min(self.config.synapse_max_permanence, self.config.synapse_init_permanence + 4));
            if (self.config.use_reputation) synapse.reputation = clampI16(@as(i32, synapse.reputation) + 2);
        }
    }

    fn demoteMemory(self: *Network, id: u32) void {
        const idx: usize = @intCast(id);
        var neuron = &self.neurons.items[idx];
        if (neuron.kind != .memory_long) return;
        neuron.kind = .memory_short;
        neuron.threshold = maxIntI32(cfg.score_scale * 2, @divTrunc(neuron.threshold * 11, 10));
        if (self.alive_long_memories > 0) self.alive_long_memories -= 1;
        self.alive_short_memories += 1;
        self.regions.items[neuron.region].live_long -= 1;
        self.regions.items[neuron.region].live_short += 1;
        self.demotions += 1;
    }

    fn maybePromoteOrDemote(self: *Network) void {
        for (self.predictive_nodes.items) |id| {
            const idx: usize = @intCast(id);
            const neuron = self.neurons.items[idx];
            const precision = self.precisionPpm(neuron);
            switch (neuron.kind) {
                .memory_short => {
                    if (!self.config.enable_long_term) continue;
                    if (neuron.support < self.config.promotion_support) continue;
                    if (self.config.use_reputation and neuron.reputation < self.config.promotion_reputation) continue;
                    const promotion_gate: u16 = self.config.promotion_precision_ppm + @as(u16, if (neuron.role == .bridge) 40 else 0);
                    if (precision < promotion_gate) continue;
                    if (neuron.wins + 2 < neuron.losses) continue;
                    self.promoteMemory(id);
                },
                .memory_long => {
                    if (self.config.use_reputation and neuron.reputation <= self.config.demotion_reputation and precision <= self.config.demotion_precision_ppm) {
                        self.demoteMemory(id);
                    }
                },
                else => continue,
            }
        }
    }

    fn refreshCarryMemories(self: *Network) !void {
        var previous: [128]u32 = undefined;
        var previous_count: usize = 0;
        for (self.carry_memories.items) |id| {
            if (previous_count >= previous.len) break;
            previous[previous_count] = id;
            previous_count += 1;
        }
        self.carry_memories.clearRetainingCapacity();
        var candidates: [128]Candidate = undefined;
        var candidate_count: usize = 0;
        for (self.predictive_nodes.items) |id| {
            const idx: usize = @intCast(id);
            const neuron = self.neurons.items[idx];
            if (neuron.kind != .memory_short and neuron.kind != .memory_long) continue;
            if (candidate_count < candidates.len) {
                const precision = self.precisionPpm(neuron);
                var score = neuron.last_activation + @as(i32, neuron.utility) * 8 + @as(i32, neuron.support) * self.config.carry_support_bonus;
                if (self.config.use_reputation) score += @as(i32, neuron.reputation) * 4;
                score += self.longMemorySelectionBonus(neuron);
                if (precision >= self.config.carry_precision_gate_ppm) {
                    score += @divTrunc(@as(i32, precision - self.config.carry_precision_gate_ppm), 8);
                } else {
                    score -= self.config.carry_low_precision_penalty;
                }
                const win_balance_raw: i32 = @as(i32, neuron.wins) - @as(i32, neuron.losses);
                const win_balance = if (win_balance_raw > 16) 16 else if (win_balance_raw < -8) -8 else win_balance_raw;
                score += @divTrunc(win_balance * self.config.carry_quality_bonus, 2);
                if (neuron.role == .bridge) score += 16;
                for (previous[0..previous_count]) |prev_id| {
                    if (prev_id == id) {
                        score += self.config.carry_persistence_bonus;
                        break;
                    }
                }
                candidates[candidate_count] = .{ .id = id, .score = score };
                candidate_count += 1;
            }
        }
        sortCandidatesDesc(candidates[0..candidate_count]);
        const keep = @min(candidate_count, @as(usize, self.config.max_carry_memories));
        var region_taken: [32]bool = [_]bool{false} ** 32;
        var signature_taken: [128]u64 = [_]u64{0} ** 128;
        var signature_count: usize = 0;
        var selected: usize = 0;
        for (candidates[0..candidate_count]) |candidate| {
            if (selected >= keep) break;
            const region = self.nodeRegion(candidate.id);
            if (region >= region_taken.len or region_taken[region]) continue;
            const neuron = self.neurons.items[@intCast(candidate.id)];
            if (self.config.carry_signature_diversity and neuron.signature != 0) {
                var duplicate = false;
                for (signature_taken[0..signature_count]) |seen| {
                    if (seen == neuron.signature) {
                        duplicate = true;
                        break;
                    }
                }
                if (duplicate) continue;
                signature_taken[signature_count] = neuron.signature;
                signature_count += 1;
            }
            region_taken[region] = true;
            try self.carry_memories.append(self.allocator, candidate.id);
            selected += 1;
        }
        if (selected < keep) {
            outer: for (candidates[0..candidate_count]) |candidate| {
                for (self.carry_memories.items) |existing| {
                    if (existing == candidate.id) continue :outer;
                }
                const neuron = self.neurons.items[@intCast(candidate.id)];
                if (self.config.carry_signature_diversity and neuron.signature != 0) {
                    for (signature_taken[0..signature_count]) |seen| {
                        if (seen == neuron.signature) continue :outer;
                    }
                    if (signature_count < signature_taken.len) {
                        signature_taken[signature_count] = neuron.signature;
                        signature_count += 1;
                    }
                }
                try self.carry_memories.append(self.allocator, candidate.id);
                selected += 1;
                if (selected >= keep) break;
            }
        }
    }

    fn pushHistory(self: *Network, current_token: u8) void {
        if (self.recent_tokens.len == 0) return;
        if (self.recent_len < self.recent_tokens.len) self.recent_len += 1;
        var idx = self.recent_len - 1;
        while (idx > 0) : (idx -= 1) {
            self.recent_tokens[idx] = self.recent_tokens[idx - 1];
        }
        self.recent_tokens[0] = current_token;
    }

    fn killMemory(self: *Network, id: u32) void {
        const idx: usize = @intCast(id);
        var neuron = &self.neurons.items[idx];
        if (neuron.kind != .memory_short and neuron.kind != .memory_long) return;
        if (self.signature_map.get(neuron.signature)) |mapped_id| {
            if (mapped_id == id) {
                _ = self.signature_map.remove(neuron.signature);
            }
        }
        if (neuron.kind == .memory_short and self.alive_short_memories > 0) {
            self.alive_short_memories -= 1;
            self.regions.items[neuron.region].live_short -= 1;
        } else if (neuron.kind == .memory_long and self.alive_long_memories > 0) {
            self.alive_long_memories -= 1;
            self.regions.items[neuron.region].live_long -= 1;
        }
        if (neuron.role == .bridge and self.regions.items[neuron.region].live_bridge > 0) {
            self.regions.items[neuron.region].live_bridge -= 1;
        }
        neuron.outgoing.deinit(self.allocator);
        neuron.outgoing = .empty;
        neuron.reset(.dead, 0);
        self.markNumericCudaNeuronDirty(id);
        self.free_memory_ids.append(self.allocator, id) catch {};
        self.pruned_neurons += 1;
    }

    fn protectionScore(self: *const Network, neuron: Neuron) i32 {
        var score = @as(i32, neuron.support) * 16 + @as(i32, neuron.utility) * 12 + @divTrunc(@as(i32, neuron.last_activation), 4);
        if (self.config.use_reputation) score += @as(i32, neuron.reputation) * 8;
        if (neuron.kind == .memory_long) score += 128;
        const idle_penalty: i32 = @intCast((self.step_index - neuron.last_active_step) / 512);
        return score - idle_penalty;
    }

    fn collectProtected(self: *Network) !void {
        self.protected_memories.clearRetainingCapacity();
        if (!self.config.use_homeostasis) return;

        var short_candidates: [512]Candidate = undefined;
        var short_count: usize = 0;
        var long_candidates: [256]Candidate = undefined;
        var long_count: usize = 0;
        for (self.neurons.items, 0..) |neuron, idx| {
            switch (neuron.kind) {
                .memory_short => {
                    if (short_count < short_candidates.len) {
                        short_candidates[short_count] = .{ .id = @intCast(idx), .score = self.protectionScore(neuron) };
                        short_count += 1;
                    }
                },
                .memory_long => {
                    if (long_count < long_candidates.len) {
                        long_candidates[long_count] = .{ .id = @intCast(idx), .score = self.protectionScore(neuron) };
                        long_count += 1;
                    }
                },
                else => {},
            }
        }
        sortCandidatesDesc(short_candidates[0..short_count]);
        sortCandidatesDesc(long_candidates[0..long_count]);
        const short_keep = @min(short_count, @as(usize, self.config.min_short_survivors));
        const long_keep = @min(long_count, @as(usize, self.config.min_long_survivors));
        try self.protected_memories.ensureUnusedCapacity(self.allocator, short_keep + long_keep);
        for (short_candidates[0..short_keep]) |candidate| try self.protected_memories.append(self.allocator, candidate.id);
        for (long_candidates[0..long_keep]) |candidate| try self.protected_memories.append(self.allocator, candidate.id);
    }

    fn isProtectedMemory(self: *const Network, id: u32) bool {
        for (self.protected_memories.items) |protected_id| {
            if (protected_id == id) return true;
        }
        return false;
    }

    fn prune(self: *Network) !void {
        try self.collectProtected();
        const short_over_target = self.alive_short_memories > self.global_short_target;
        for (self.neurons.items, 0..) |*neuron, idx| {
            if (neuron.kind == .memory_short or neuron.kind == .memory_long) {
                const idle = self.step_index - neuron.last_active_step;
                const is_long = neuron.kind == .memory_long;
                const idle_limit = if (is_long) self.config.long_idle_prune else self.config.short_idle_prune;
                const reputation_floor = if (is_long) self.config.long_min_reputation else self.config.short_min_reputation;
                const protected = self.isProtectedMemory(@intCast(idx));
                const global_alive = if (is_long) self.alive_long_memories else self.alive_short_memories;
                const global_floor = if (is_long) self.config.min_long_survivors else self.config.min_short_survivors;
                const region_alive = self.regionMemoryCount(neuron.region);
                const low_rep = self.config.use_reputation and neuron.reputation < reputation_floor;
                const low_utility = neuron.utility < self.config.neuron_min_utility;
                const over_idle = idle > idle_limit;
                const low_precision = neuron.support >= self.config.promotion_support and self.precisionPpm(neuron.*) < self.config.demotion_precision_ppm;
                const pressured = over_idle or low_rep or ((short_over_target or is_long) and (low_utility or low_precision));
                if (!protected and global_alive > global_floor and region_alive > self.config.region_min_survivors and pressured) {
                    if (is_long and self.config.enable_long_term and (self.precisionPpm(neuron.*) > self.config.demotion_precision_ppm + 40 or (!self.config.use_reputation or neuron.reputation > self.config.long_min_reputation - 8))) {
                        self.demoteMemory(@intCast(idx));
                    } else {
                        self.killMemory(@intCast(idx));
                        continue;
                    }
                }
            }
            if (neuron.kind == .dead) continue;
            const min_keep = if (neuron.kind == .memory_long) @max(@as(usize, self.config.min_outgoing_to_keep), 4) else @as(usize, self.config.min_outgoing_to_keep);
            const original_len = neuron.outgoing.items.len;
            var write_index: usize = 0;
            for (neuron.outgoing.items, 0..) |synapse, syn_idx| {
                const target_idx: usize = @intCast(synapse.target);
                if (target_idx >= self.neurons.items.len or self.neurons.items[target_idx].kind == .dead) {
                    self.pruned_synapses += 1;
                    continue;
                }
                var kept = synapse;
                const age = self.step_index - kept.last_touched;
                if (age > self.config.prune_interval and kept.permanence > 0) {
                    const decay: u8 = if (neuron.kind == .memory_long) 0 else 1;
                    if (kept.permanence > decay) kept.permanence -= decay else kept.permanence = 0;
                }
                if (self.config.use_reputation and age > self.config.prune_interval) {
                    if (kept.reputation > 0) {
                        kept.reputation -= 1;
                    } else if (kept.reputation < 0) {
                        kept.reputation += 1;
                    }
                }
                const remain_if_drop = write_index + (original_len - syn_idx - 1);
                const must_keep = remain_if_drop < min_keep;
                const bad_rep = self.config.use_reputation and kept.reputation < self.config.synapse_bad_reputation and age > self.config.prune_interval * 2;
                if (!must_keep and (kept.permanence == 0 or bad_rep)) {
                    self.pruned_synapses += 1;
                    continue;
                }
                neuron.outgoing.items[write_index] = kept;
                write_index += 1;
            }
            neuron.outgoing.items.len = write_index;
        }
    }

    pub fn scoringBackendUsedLabel(self: *const Network) []const u8 {
        return self.last_score_backend_used.label();
    }

    pub fn configuredScoringBackendLabel(self: *const Network) []const u8 {
        return self.config.numeric_backend.label();
    }

    pub fn numericCudaEnabled(self: *const Network) bool {
        return self.numeric_cuda_runtime != null;
    }

    pub fn numericCudaDeviceLabel(self: *const Network) ?[]const u8 {
        if (self.numeric_cuda_runtime) |runtime| return runtime.device_name;
        return null;
    }

    pub fn countAliveShortMemories(self: *const Network) usize {
        return self.alive_short_memories;
    }

    pub fn countAliveLongMemories(self: *const Network) usize {
        return self.alive_long_memories;
    }

    pub fn countAliveBridgeMemories(self: *const Network) usize {
        var total: usize = 0;
        for (self.regions.items[0..self.open_region_count]) |region| total += region.live_bridge;
        return total;
    }

    pub fn countLiveRegions(self: *const Network) usize {
        var total: usize = 0;
        for (self.regions.items[0..self.open_region_count]) |region| {
            if (region.live_short + region.live_long > 0) total += 1;
        }
        return total;
    }

    pub fn currentShortTarget(self: *const Network) usize {
        return self.global_short_target;
    }

    pub fn countAliveMemories(self: *const Network) usize {
        return self.alive_short_memories + self.alive_long_memories;
    }

    pub fn countAliveSynapses(self: *const Network) usize {
        var count: usize = 0;
        for (self.neurons.items) |neuron| {
            if (neuron.kind == .dead) continue;
            count += neuron.outgoing.items.len;
        }
        return count;
    }

    pub fn stepGenerated(self: *Network, current_token: u8) !Prediction {
        try self.seedFromHistory(current_token);
        try self.propagateMemories();
        var prediction = self.scoreOutputs(current_token, current_token);
        const actual_next = prediction.token;
        prediction.actual_rank = 1;
        prediction.actual_score = prediction.top_score;
        const surprise_like = prediction.margin <= self.config.birth_margin;
        const confident_like = prediction.margin >= cfg.score_scale / 2;
        prediction.surprise = surprise_like;

        for (self.predictive_nodes.items) |src_id| {
            const idx: usize = @intCast(src_id);
            const kind = self.neurons.items[idx].kind;
            if (kind == .dead or kind == .output) continue;
            const role = self.neurons.items[idx].role;
            const strong_positive = (kind == .memory_short or kind == .memory_long) and (surprise_like or (role == .bridge and prediction.actual_rank > 4));
            try self.touchOrCreateSynapse(src_id, self.output_ids.items[actual_next], true, strong_positive);
            self.neurons.items[idx].last_active_step = self.step_index;
        }

        if (surprise_like) {
            try self.spawnMemory(current_token, actual_next, prediction);
        }
        self.updateUtilities(prediction, actual_next);
        self.maybePromoteOrDemote();
        try self.refreshCarryMemories();
        try self.updateSequenceExperts(current_token, actual_next);
        self.recordElasticityStep(true, surprise_like, confident_like);
        self.pushHistory(current_token);
        if (self.step_index % self.config.elasticity_interval == 0) {
            self.adjustElasticity();
        }
        if (self.step_index % self.config.prune_interval == 0) {
            try self.prune();
        }
        return prediction;
    }

    fn runStep(self: *Network, current_token: u8, actual_next: u8, profile: ?*StepProfile, profile_io: ?std.Io) !Prediction {
        const profile_enabled = profile != null;
        var phase_start_ns: u64 = 0;
        var seed_elapsed_ns: u64 = 0;
        var propagate_elapsed_ns: u64 = 0;
        var score_elapsed_ns: u64 = 0;
        var output_update_elapsed_ns: u64 = 0;
        var plasticity_elapsed_ns: u64 = 0;
        var expert_update_elapsed_ns: u64 = 0;
        if (profile_enabled) phase_start_ns = @intCast(std.Io.Clock.awake.now(profile_io.?).nanoseconds);
        try self.seedFromHistory(current_token);
        if (profile_enabled) {
            const now_ns: u64 = @intCast(std.Io.Clock.awake.now(profile_io.?).nanoseconds);
            seed_elapsed_ns = now_ns - phase_start_ns;
            phase_start_ns = now_ns;
        }
        try self.propagateMemories();
        if (profile_enabled) {
            const now_ns: u64 = @intCast(std.Io.Clock.awake.now(profile_io.?).nanoseconds);
            propagate_elapsed_ns = now_ns - phase_start_ns;
            phase_start_ns = now_ns;
        }
        var prediction = self.scoreOutputs(current_token, actual_next);
        const backend_used = self.last_score_backend_used;
        if (profile_enabled) {
            const now_ns: u64 = @intCast(std.Io.Clock.awake.now(profile_io.?).nanoseconds);
            score_elapsed_ns = now_ns - phase_start_ns;
            phase_start_ns = now_ns;
        }
        const was_correct = prediction.token == actual_next;
        const surprise_like = !was_correct or prediction.margin <= self.config.birth_margin;
        const confident_like = was_correct and prediction.actual_rank == 1 and prediction.margin >= cfg.score_scale / 2;
        prediction.surprise = surprise_like;

        for (self.predictive_nodes.items) |src_id| {
            const idx: usize = @intCast(src_id);
            const kind = self.neurons.items[idx].kind;
            if (kind == .dead or kind == .output) continue;
            const role = self.neurons.items[idx].role;
            const strong_positive = (kind == .memory_short or kind == .memory_long) and (surprise_like or (role == .bridge and prediction.actual_rank > 4));
            try self.touchOrCreateSynapse(src_id, self.output_ids.items[actual_next], true, strong_positive);
            if (!was_correct and prediction.top_score > 0 and (kind == .memory_short or kind == .memory_long) and prediction.token != actual_next) {
                const strong_negative = kind == .memory_long or role == .bridge;
                try self.touchOrCreateSynapse(src_id, self.output_ids.items[prediction.token], false, strong_negative);
            }
            self.neurons.items[idx].last_active_step = self.step_index;
        }
        if (profile_enabled) {
            const now_ns: u64 = @intCast(std.Io.Clock.awake.now(profile_io.?).nanoseconds);
            output_update_elapsed_ns = now_ns - phase_start_ns;
            phase_start_ns = now_ns;
        }

        if (surprise_like) {
            try self.spawnMemory(current_token, actual_next, prediction);
        }
        self.updateUtilities(prediction, actual_next);
        self.maybePromoteOrDemote();
        try self.refreshCarryMemories();
        if (profile_enabled) {
            const now_ns: u64 = @intCast(std.Io.Clock.awake.now(profile_io.?).nanoseconds);
            plasticity_elapsed_ns = now_ns - phase_start_ns;
            phase_start_ns = now_ns;
        }
        try self.updateSequenceExperts(current_token, actual_next);
        self.updateHybridExpertWeights(actual_next);
        if (profile_enabled) {
            const now_ns: u64 = @intCast(std.Io.Clock.awake.now(profile_io.?).nanoseconds);
            expert_update_elapsed_ns = now_ns - phase_start_ns;
            phase_start_ns = now_ns;
        }
        self.recordElasticityStep(was_correct, surprise_like, confident_like);
        self.pushHistory(current_token);
        if (self.step_index % self.config.elasticity_interval == 0) {
            self.adjustElasticity();
        }
        if (self.step_index % self.config.prune_interval == 0) {
            try self.prune();
        }
        if (profile) |profile_out| {
            const end_ns: u64 = @intCast(std.Io.Clock.awake.now(profile_io.?).nanoseconds);
            const housekeeping_elapsed_ns = end_ns - phase_start_ns;
            profile_out.* = .{
                .prediction = prediction,
                .seed_ns = seed_elapsed_ns,
                .propagate_ns = propagate_elapsed_ns,
                .score_ns = score_elapsed_ns,
                .output_update_ns = output_update_elapsed_ns,
                .plasticity_ns = plasticity_elapsed_ns,
                .expert_update_ns = expert_update_elapsed_ns,
                .housekeeping_ns = housekeeping_elapsed_ns,
                .maintenance_ns = plasticity_elapsed_ns + expert_update_elapsed_ns + housekeeping_elapsed_ns,
                .adapt_ns = output_update_elapsed_ns + plasticity_elapsed_ns + expert_update_elapsed_ns + housekeeping_elapsed_ns,
                .backend_used = backend_used,
            };
        }
        return prediction;
    }

    pub fn step(self: *Network, current_token: u8, actual_next: u8) !Prediction {
        return self.runStep(current_token, actual_next, null, null);
    }

    pub fn stepProfile(self: *Network, io: std.Io, current_token: u8, actual_next: u8) !StepProfile {
        var profile: StepProfile = undefined;
        _ = try self.runStep(current_token, actual_next, &profile, io);
        return profile;
    }
};

test "scaled values stay bounded across bit widths" {
    const allocator = std.testing.allocator;
    var net = try Network.init(allocator, .{ .weight_bits = 8 });
    defer net.deinit();
    try std.testing.expectEqual(@as(i32, cfg.score_scale), net.scaledValue(net.maxQuant()));
    try std.testing.expectEqual(@as(i32, -cfg.score_scale), net.scaledValue(-net.maxQuant()));
}

test "births occur under repeated surprise" {
    const allocator = std.testing.allocator;
    var net = try Network.init(allocator, .{ .weight_bits = 4, .history_lags = 4, .max_short_memories = 2048 });
    defer net.deinit();
    _ = try net.step(0, 1);
    _ = try net.step(1, 2);
    _ = try net.step(2, 3);
    try std.testing.expect(net.births > 0);
}

test "memory slots recycle after prune" {
    const allocator = std.testing.allocator;
    var net = try Network.init(allocator, .{
        .weight_bits = 4,
        .history_lags = 4,
        .max_short_memories = 8,
        .prune_interval = 4,
        .short_idle_prune = 1,
        .min_short_survivors = 0,
        .use_homeostasis = false,
    });
    defer net.deinit();
    _ = try net.step(0, 1);
    _ = try net.step(1, 2);
    _ = try net.step(2, 3);
    _ = try net.step(4, 5);
    const before_free = net.free_memory_ids.items.len;
    // Force more steps to prune old memories.
    _ = try net.step(7, 8);
    _ = try net.step(9, 10);
    _ = try net.step(11, 12);
    _ = try net.step(13, 14);
    try std.testing.expect(net.free_memory_ids.items.len >= before_free);
}

test "parallel output scoring matches single-thread scoring" {
    const allocator = std.testing.allocator;
    var base_config = cfg.configForVariant(4, .default);
    base_config.history_lags = 8;
    base_config.max_short_memories = 4096;
    base_config.max_long_memories = 256;
    base_config.numeric_backend = .cpu;
    base_config.score_threads = 1;

    var parallel_config = base_config;
    parallel_config.numeric_backend = .cpu_mt;
    parallel_config.score_threads = 4;
    parallel_config.parallel_score_min_predictive_nodes = 1;

    var serial_net = try Network.init(allocator, base_config);
    defer serial_net.deinit();
    var parallel_net = try Network.init(allocator, parallel_config);
    defer parallel_net.deinit();

    const corpus = "SBAN parallel score check. " ** 96;
    for (0..corpus.len - 1) |idx| {
        const serial_prediction = try serial_net.step(corpus[idx], corpus[idx + 1]);
        const parallel_prediction = try parallel_net.step(corpus[idx], corpus[idx + 1]);
        try std.testing.expectEqualDeep(serial_prediction, parallel_prediction);
    }

    try std.testing.expectEqual(serial_net.births, parallel_net.births);
    try std.testing.expectEqual(serial_net.bridge_births, parallel_net.bridge_births);
    try std.testing.expectEqual(serial_net.promotions, parallel_net.promotions);
    try std.testing.expectEqual(serial_net.recycled_slots, parallel_net.recycled_slots);
    try std.testing.expectEqual(serial_net.countAliveShortMemories(), parallel_net.countAliveShortMemories());
    try std.testing.expectEqual(serial_net.countAliveLongMemories(), parallel_net.countAliveLongMemories());
    try std.testing.expectEqual(serial_net.countAliveSynapses(), parallel_net.countAliveSynapses());
}

test "cuda output scoring matches single-thread scoring when available" {
    const allocator = std.testing.allocator;
    var base_config = cfg.configForVariant(4, .default);
    base_config.history_lags = 8;
    base_config.max_short_memories = 4096;
    base_config.max_long_memories = 256;
    base_config.numeric_backend = .cpu;

    var cuda_config = base_config;
    cuda_config.numeric_backend = .cuda;
    cuda_config.cuda_min_scoring_edges = 1;

    var serial_net = try Network.init(allocator, base_config);
    defer serial_net.deinit();
    var cuda_net = try Network.init(allocator, cuda_config);
    defer cuda_net.deinit();

    if (!cuda_net.numericCudaEnabled()) return;

    const corpus = "SBAN cuda score parity check. " ** 96;
    for (0..corpus.len - 1) |idx| {
        const serial_prediction = try serial_net.step(corpus[idx], corpus[idx + 1]);
        const cuda_prediction = try cuda_net.step(corpus[idx], corpus[idx + 1]);
        try std.testing.expectEqualDeep(serial_prediction, cuda_prediction);
    }

    try std.testing.expectEqualStrings("cuda", cuda_net.scoringBackendUsedLabel());
    try std.testing.expectEqual(serial_net.births, cuda_net.births);
    try std.testing.expectEqual(serial_net.bridge_births, cuda_net.bridge_births);
    try std.testing.expectEqual(serial_net.promotions, cuda_net.promotions);
    try std.testing.expectEqual(serial_net.recycled_slots, cuda_net.recycled_slots);
    try std.testing.expectEqual(serial_net.countAliveShortMemories(), cuda_net.countAliveShortMemories());
    try std.testing.expectEqual(serial_net.countAliveLongMemories(), cuda_net.countAliveLongMemories());
    try std.testing.expectEqual(serial_net.countAliveSynapses(), cuda_net.countAliveSynapses());
}
