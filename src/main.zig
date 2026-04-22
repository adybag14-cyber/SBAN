const std = @import("std");
const Io = std.Io;
const sban = @import("zig_sban");
const dialogue = sban.dialogue;

fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\SBAN v22.5 - grounded dialogue plus CUDA, cpu-mt, and technical backend validation
        \\Usage:
        \\  zig build run -- eval-enwik [dataset_path] [json_output_path] [prefix|drift] [segment_len] [checkpoint_interval] [rolling_window]
        \\  zig build run -- eval-ablations [dataset_path] [json_output_path] [prefix|drift] [bits] [segment_len] [checkpoint_interval] [rolling_window]
        \\  zig build run -- eval-variant [dataset_path] [json_output_path] [prefix|drift] [bits] [variant] [segment_len] [checkpoint_interval] [rolling_window] [key=value ...]
    );
    try dialogue.printUsage(writer);
    try writer.writeAll(
        \\
        \\  zig build run -- inspect
    );
}

fn writeExperimentFile(io: std.Io, path: []const u8, data: *sban.experiment.ExperimentData) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var file_writer: Io.File.Writer = .init(file, io, &buffer);
    try data.writeJson(&file_writer.interface);
    try file_writer.interface.flush();
}

fn parseVariant(name: []const u8) ?sban.config.NetworkVariant {
    if (std.mem.eql(u8, name, "default")) return .default;
    if (std.mem.eql(u8, name, "no_bridge")) return .no_bridge;
    if (std.mem.eql(u8, name, "fixed_capacity")) return .fixed_capacity;
    if (std.mem.eql(u8, name, "single_region")) return .single_region;
    if (std.mem.eql(u8, name, "no_reputation")) return .no_reputation;
    return null;
}

fn buildCustomLabel(allocator: std.mem.Allocator, base: []const u8, label_override: ?[]const u8) ![]const u8 {
    if (label_override) |label| return label;
    return try std.fmt.allocPrint(allocator, "{s}_tuned", .{base});
}

fn printExperimentSummary(writer: *Io.Writer, data: *const sban.experiment.ExperimentData) !void {
    try writer.print("SBAN v22.5 experiment {s} ({s})\n", .{ data.meta.name, data.meta.protocol });
    for (data.reports.items) |report| {
        const accuracy = if (report.summary.total_predictions == 0) 0.0 else @as(f64, @floatFromInt(report.summary.total_correct)) / @as(f64, @floatFromInt(report.summary.total_predictions));
        const top5 = if (report.summary.total_predictions == 0) 0.0 else @as(f64, @floatFromInt(report.summary.top5_correct)) / @as(f64, @floatFromInt(report.summary.total_predictions));
        try writer.print(
            "- {s}: acc={d:.4} top5={d:.4} births={d} bridge_births={d} short={d} long={d} bridge={d} regions={d} synapses={d} promotions={d} recycled={d}\n",
            .{
                report.summary.name,
                accuracy,
                top5,
                report.summary.births,
                report.summary.bridge_births,
                report.summary.final_short_memories,
                report.summary.final_long_memories,
                report.summary.final_bridge_memories,
                report.summary.final_regions,
                report.summary.final_synapses,
                report.summary.promotions,
                report.summary.recycled_slots,
            },
        );
    }
}

fn parseCorpusArgs(args: []const []const u8, corpus_cfg: *sban.config.CorpusConfig, start_idx: usize) !usize {
    var next_idx = start_idx;
    if (args.len > next_idx and std.mem.indexOfScalar(u8, args[next_idx], '=') == null) {
        corpus_cfg.segment_len = try std.fmt.parseInt(usize, args[next_idx], 10);
        next_idx += 1;
    }
    if (args.len > next_idx and std.mem.indexOfScalar(u8, args[next_idx], '=') == null) {
        corpus_cfg.checkpoint_interval = try std.fmt.parseInt(usize, args[next_idx], 10);
        next_idx += 1;
    }
    if (args.len > next_idx and std.mem.indexOfScalar(u8, args[next_idx], '=') == null) {
        corpus_cfg.rolling_window = try std.fmt.parseInt(usize, args[next_idx], 10);
        next_idx += 1;
    }
    return next_idx;
}

fn parseEvalBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes") or std.ascii.eqlIgnoreCase(value, "on")) return true;
    if (std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "no") or std.ascii.eqlIgnoreCase(value, "off")) return false;
    return error.InvalidOverride;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    if (args.len < 2) {
        try printUsage(writer);
        try writer.flush();
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "eval-enwik")) {
        if (args.len < 5) {
            try printUsage(writer);
            try writer.flush();
            return;
        }
        var corpus_cfg = sban.config.CorpusConfig{
            .dataset_path = args[2],
            .mode = if (std.mem.eql(u8, args[4], "drift")) .drift else .prefix,
        };
        _ = try parseCorpusArgs(args, &corpus_cfg, 5);

        var data = try sban.experiment.runCorpus(io, arena, corpus_cfg);
        defer data.deinit();

        try writeExperimentFile(io, args[3], &data);
        try printExperimentSummary(writer, &data);
        try writer.print("wrote_json={s}\n", .{args[3]});
    } else if (std.mem.eql(u8, command, "eval-ablations")) {
        if (args.len < 6) {
            try printUsage(writer);
            try writer.flush();
            return;
        }
        const bits = try std.fmt.parseInt(u8, args[5], 10);
        var corpus_cfg = sban.config.CorpusConfig{
            .dataset_path = args[2],
            .mode = if (std.mem.eql(u8, args[4], "drift")) .drift else .prefix,
        };
        _ = try parseCorpusArgs(args, &corpus_cfg, 6);

        var data = try sban.experiment.runAblations(io, arena, corpus_cfg, bits);
        defer data.deinit();

        try writeExperimentFile(io, args[3], &data);
        try printExperimentSummary(writer, &data);
        try writer.print("wrote_json={s}\n", .{args[3]});
    } else if (std.mem.eql(u8, command, "eval-variant")) {
        if (args.len < 7) {
            try printUsage(writer);
            try writer.flush();
            return;
        }
        const bits = try std.fmt.parseInt(u8, args[5], 10);
        const variant = parseVariant(args[6]) orelse {
            try writer.print("unknown_variant={s}\n", .{args[6]});
            try writer.flush();
            return;
        };
        var corpus_cfg = sban.config.CorpusConfig{
            .dataset_path = args[2],
            .mode = if (std.mem.eql(u8, args[4], "drift")) .drift else .prefix,
        };
        const override_start = try parseCorpusArgs(args, &corpus_cfg, 7);

        var net_config = sban.config.configForVariant(bits, variant);
        var label_override: ?[]const u8 = null;
        var include_baseline = true;
        for (args[override_start..]) |arg| {
            const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse {
                try writer.print("invalid_override={s}\n", .{arg});
                try writer.flush();
                return;
            };
            const key = arg[0..eq_idx];
            const value = arg[eq_idx + 1 ..];
            if (std.mem.eql(u8, key, "label")) {
                label_override = value;
            } else if (std.mem.eql(u8, key, "include_baseline")) {
                include_baseline = try parseEvalBool(value);
            } else if (std.mem.eql(u8, key, "reset_on_segment_boundary")) {
                corpus_cfg.reset_on_segment_boundary = try parseEvalBool(value);
            } else if (std.mem.eql(u8, key, "sequence_seed_path")) {
                corpus_cfg.sequence_seed_path = value;
            } else if (std.mem.eql(u8, key, "sequence_seed_offset")) {
                corpus_cfg.sequence_seed_offset = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.eql(u8, key, "sequence_seed_length")) {
                corpus_cfg.sequence_seed_length = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.eql(u8, key, "sequence_seed_on_reset")) {
                corpus_cfg.sequence_seed_on_reset = try parseEvalBool(value);
            } else if (std.mem.eql(u8, key, "sequence_seed_align_to_segment")) {
                corpus_cfg.sequence_seed_align_to_segment = try parseEvalBool(value);
            } else if (std.mem.eql(u8, key, "sequence_seed_from_segment_end")) {
                corpus_cfg.sequence_seed_from_segment_end = try parseEvalBool(value);
            } else if (std.mem.eql(u8, key, "sequence_seed_replace_on_reset")) {
                corpus_cfg.sequence_seed_replace_on_reset = try parseEvalBool(value);
            } else {
                sban.config.applyOverride(&net_config, key, value) catch |err| {
                    try writer.print("invalid_override={s} err={s}\n", .{ arg, @errorName(err) });
                    try writer.flush();
                    return;
                };
            }
        }

        const model_name = try buildCustomLabel(arena, sban.config.sbanVariantLabel(bits, variant), label_override);
        var data = if (override_start < args.len)
            try sban.experiment.runSingleCustomDetailed(io, arena, corpus_cfg, model_name, variant.label(), net_config, include_baseline)
        else
            try sban.experiment.runSingleVariantDetailed(io, arena, corpus_cfg, bits, variant, include_baseline);
        defer data.deinit();

        try writeExperimentFile(io, args[3], &data);
        try printExperimentSummary(writer, &data);
        try writer.print("wrote_json={s}\n", .{args[3]});
    } else if (std.mem.eql(u8, command, "chat-demo")) {
        try dialogue.runChatDemo(arena, io, writer, args);
    } else if (std.mem.eql(u8, command, "chat-eval")) {
        try dialogue.runChatEval(arena, io, writer, args);
    } else if (std.mem.eql(u8, command, "chat-session-eval")) {
        try dialogue.runChatSessionEval(arena, io, writer, args);
    } else if (std.mem.eql(u8, command, "accel-info")) {
        try dialogue.runAccelInfo(arena, io, writer, args);
    } else if (std.mem.eql(u8, command, "accel-bench")) {
        try dialogue.runAccelBench(arena, io, writer, args);
    } else if (std.mem.eql(u8, command, "inspect")) {
        var net = try sban.network.Network.init(arena, sban.config.configForVariant(4, .default));
        defer net.deinit();
        _ = try net.step('t', 'h');
        _ = try net.step('h', 'e');
        _ = try net.step('e', ' ');
        try writer.print(
            "births={d} bridge_births={d} short={d} long={d} bridge={d} regions={d} synapses={d} promotions={d} recycled={d}\n",
            .{ net.births, net.bridge_births, net.countAliveShortMemories(), net.countAliveLongMemories(), net.countAliveBridgeMemories(), net.countLiveRegions(), net.countAliveSynapses(), net.promotions, net.recycled_slots },
        );
    } else {
        try printUsage(writer);
    }

    try writer.flush();
}
