const std = @import("std");
const Io = std.Io;
const sban = @import("zig_sban");

fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\SBAN v4 - elastic parallel region-bridge birth/death assembly network
        \\Usage:
        \\  zig build run -- eval-enwik [dataset_path] [json_output_path] [prefix|drift] [segment_len] [checkpoint_interval] [rolling_window]
        \\  zig build run -- eval-ablations [dataset_path] [json_output_path] [prefix|drift] [bits] [segment_len] [checkpoint_interval] [rolling_window]
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

fn printExperimentSummary(writer: *Io.Writer, data: *const sban.experiment.ExperimentData) !void {
    try writer.print("SBAN v4 experiment {s} ({s})\n", .{ data.meta.name, data.meta.protocol });
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
        if (args.len >= 6) corpus_cfg.segment_len = try std.fmt.parseInt(usize, args[5], 10);
        if (args.len >= 7) corpus_cfg.checkpoint_interval = try std.fmt.parseInt(usize, args[6], 10);
        if (args.len >= 8) corpus_cfg.rolling_window = try std.fmt.parseInt(usize, args[7], 10);

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
        if (args.len >= 7) corpus_cfg.segment_len = try std.fmt.parseInt(usize, args[6], 10);
        if (args.len >= 8) corpus_cfg.checkpoint_interval = try std.fmt.parseInt(usize, args[7], 10);
        if (args.len >= 9) corpus_cfg.rolling_window = try std.fmt.parseInt(usize, args[8], 10);

        var data = try sban.experiment.runAblations(io, arena, corpus_cfg, bits);
        defer data.deinit();

        try writeExperimentFile(io, args[3], &data);
        try printExperimentSummary(writer, &data);
        try writer.print("wrote_json={s}\n", .{args[3]});
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
