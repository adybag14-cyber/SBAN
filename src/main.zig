const std = @import("std");
const Io = std.Io;
const sban = @import("zig_sban");

const DialogueExample = struct {
    user: []const u8,
    assistant: []const u8,
};

const ChatOptions = struct {
    seed_path: []const u8 = "data/sban_dialogue_seed_v18.txt",
    mode: enum { anchor, free, hybrid } = .hybrid,
    max_bytes: usize = 96,
    continue_bytes: usize = 0,
    net_config: sban.config.NetworkConfig = blk: {
        const config = sban.config.v18ReleaseConfig(4);
        break :blk config;
    },
};

fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\SBAN v18 - seeded higher-order hybrid sequence experts with sparse order-4 and order-5 routing
        \\Usage:
        \\  zig build run -- eval-enwik [dataset_path] [json_output_path] [prefix|drift] [segment_len] [checkpoint_interval] [rolling_window]
        \\  zig build run -- eval-ablations [dataset_path] [json_output_path] [prefix|drift] [bits] [segment_len] [checkpoint_interval] [rolling_window]
        \\  zig build run -- eval-variant [dataset_path] [json_output_path] [prefix|drift] [bits] [variant] [segment_len] [checkpoint_interval] [rolling_window] [key=value ...]
        \\  zig build run -- chat-demo [prompt] [max_bytes] [key=value ...]
        \\  zig build run -- chat-eval [prompt_file_path] [key=value ...]
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
    try writer.print("SBAN v18 experiment {s} ({s})\n", .{ data.meta.name, data.meta.protocol });
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

fn readWholeFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 20));
}

fn trainBytes(net: *sban.network.Network, bytes: []const u8) !void {
    if (bytes.len < 2) return;
    var idx: usize = 0;
    while (idx + 1 < bytes.len) : (idx += 1) {
        _ = try net.step(bytes[idx], bytes[idx + 1]);
    }
}

fn isWordChar(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or std.ascii.isDigit(byte);
}

fn trimLine(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, "\r\n \t");
}

fn parseDialogueExamples(allocator: std.mem.Allocator, seed_bytes: []const u8) !std.ArrayList(DialogueExample) {
    var examples = std.ArrayList(DialogueExample).empty;
    var current_user: ?[]const u8 = null;
    var iter = std.mem.splitScalar(u8, seed_bytes, '\n');
    while (iter.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "User:")) {
            current_user = trimLine(line[5..]);
        } else if (std.mem.startsWith(u8, line, "Assistant:")) {
            if (current_user) |user| {
                try examples.append(allocator, .{ .user = user, .assistant = trimLine(line[10..]) });
                current_user = null;
            }
        }
    }
    return examples;
}

fn containsTokenIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return false;
    var idx: usize = 0;
    while (idx < haystack.len) {
        while (idx < haystack.len and !isWordChar(haystack[idx])) : (idx += 1) {}
        const start = idx;
        while (idx < haystack.len and isWordChar(haystack[idx])) : (idx += 1) {}
        if (idx > start) {
            const token = haystack[start..idx];
            if (std.ascii.eqlIgnoreCase(token, needle)) return true;
        }
    }
    return false;
}

fn promptSimilarity(prompt: []const u8, candidate: []const u8) u32 {
    if (std.ascii.eqlIgnoreCase(prompt, candidate)) return 10_000 + @as(u32, @intCast(candidate.len));

    var score: u32 = 0;
    if (std.mem.indexOf(u8, candidate, prompt) != null or std.mem.indexOf(u8, prompt, candidate) != null) {
        score += 200;
    }

    var idx: usize = 0;
    while (idx < prompt.len) {
        while (idx < prompt.len and !isWordChar(prompt[idx])) : (idx += 1) {}
        const start = idx;
        while (idx < prompt.len and isWordChar(prompt[idx])) : (idx += 1) {}
        if (idx <= start) continue;
        const token = prompt[start..idx];
        if (token.len <= 1) continue;
        if (containsTokenIgnoreCase(candidate, token)) {
            score += @as(u32, @intCast(token.len * token.len));
        }
    }
    return score;
}

fn selectDialogueAnchor(prompt: []const u8, examples: []const DialogueExample) ?DialogueExample {
    var best: ?DialogueExample = null;
    var best_score: u32 = 0;
    for (examples) |example| {
        const score = promptSimilarity(prompt, example.user);
        if (score > best_score) {
            best_score = score;
            best = example;
        }
    }
    if (best_score < 16) return null;
    return best;
}

fn selectDialogueSupport(prompt: []const u8, examples: []const DialogueExample) ?DialogueExample {
    var best: ?DialogueExample = null;
    var best_score: u32 = 0;
    for (examples) |example| {
        const score = promptSimilarity(prompt, example.user);
        if (score > best_score) {
            best_score = score;
            best = example;
        }
    }
    if (best_score < 8) return null;
    return best;
}

fn sanitizeGeneratedResponse(bytes: []const u8) []const u8 {
    var trimmed = std.mem.trim(u8, bytes, "\r\n \t");
    if (std.mem.indexOf(u8, trimmed, "\nUser:")) |idx| {
        trimmed = trimLine(trimmed[0..idx]);
    }
    if (std.mem.indexOf(u8, trimmed, "\nAssistant:")) |idx| {
        trimmed = trimLine(trimmed[0..idx]);
    }
    return trimmed;
}

fn generateFreeResponse(allocator: std.mem.Allocator, net: *sban.network.Network, prompt: []const u8, max_bytes: usize) ![]const u8 {
    const prompt_block = try std.fmt.allocPrint(allocator, "User: {s}\nAssistant:", .{prompt});
    try trainBytes(net, prompt_block);

    const response_start = if (prompt_block.len > 0) prompt_block[prompt_block.len - 1] else @as(u8, ':');
    var current = response_start;
    var generated = std.ArrayList(u8).empty;
    defer generated.deinit(allocator);

    var idx: usize = 0;
    while (idx < max_bytes) : (idx += 1) {
        const prediction = try net.stepGenerated(current);
        const next_byte = prediction.token;
        if (next_byte == 0) break;
        try generated.append(allocator, next_byte);
        current = next_byte;
        if (generated.items.len >= 2 and generated.items[generated.items.len - 1] == '\n' and generated.items[generated.items.len - 2] == '\n') break;
    }
    const trimmed = sanitizeGeneratedResponse(generated.items);
    return try allocator.dupe(u8, trimmed);
}

fn generateAnchoredResponse(allocator: std.mem.Allocator, net: *sban.network.Network, prompt: []const u8, anchor: DialogueExample, continue_bytes: usize) ![]const u8 {
    const prompt_block = try std.fmt.allocPrint(allocator, "User: {s}\nAssistant:", .{prompt});
    try trainBytes(net, prompt_block);
    try trainBytes(net, anchor.assistant);

    if (continue_bytes == 0) {
        return anchor.assistant;
    }

    var response = std.ArrayList(u8).empty;
    defer response.deinit(allocator);
    try response.appendSlice(allocator, anchor.assistant);
    var current: u8 = if (anchor.assistant.len > 0) anchor.assistant[anchor.assistant.len - 1] else @as(u8, '.');
    var idx: usize = 0;
    while (idx < continue_bytes) : (idx += 1) {
        const prediction = try net.stepGenerated(current);
        const next_byte = prediction.token;
        if (next_byte == 0) break;
        try response.append(allocator, next_byte);
        current = next_byte;
        if (response.items.len >= 2 and response.items[response.items.len - 1] == '\n' and response.items[response.items.len - 2] == '\n') break;
    }
    const trimmed = sanitizeGeneratedResponse(response.items);
    return try allocator.dupe(u8, trimmed);
}

fn parseChatOptions(writer: *Io.Writer, args: []const []const u8, start_idx: usize, options: *ChatOptions) !void {
    for (args[start_idx..]) |arg| {
        const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse {
            try writer.print("invalid_override={s}\n", .{arg});
            return error.InvalidOverride;
        };
        const key = arg[0..eq_idx];
        const value = arg[eq_idx + 1 ..];
        if (std.mem.eql(u8, key, "seed_path")) {
            options.seed_path = value;
        } else if (std.mem.eql(u8, key, "mode")) {
            if (std.mem.eql(u8, value, "anchor")) options.mode = .anchor else if (std.mem.eql(u8, value, "free")) options.mode = .free else if (std.mem.eql(u8, value, "hybrid")) options.mode = .hybrid else {
                try writer.print("invalid_mode={s}\n", .{value});
                return error.InvalidOverride;
            }
        } else if (std.mem.eql(u8, key, "continue_bytes")) {
            options.continue_bytes = try std.fmt.parseInt(usize, value, 10);
        } else {
            sban.config.applyOverride(&options.net_config, key, value) catch |err| {
                try writer.print("invalid_override={s} err={s}\n", .{ arg, @errorName(err) });
                return error.InvalidOverride;
            };
        }
    }
}

fn runChatDemo(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try printUsage(writer);
        try writer.flush();
        return;
    }
    const prompt = args[2];
    var options = ChatOptions{};
    var override_start: usize = 3;
    if (args.len > 3 and std.mem.indexOfScalar(u8, args[3], '=') == null) {
        options.max_bytes = try std.fmt.parseInt(usize, args[3], 10);
        override_start = 4;
    }
    parseChatOptions(writer, args, override_start, &options) catch {
        try writer.flush();
        return;
    };

    const seed_bytes = try readWholeFile(allocator, io, options.seed_path);
    var examples = try parseDialogueExamples(allocator, seed_bytes);
    defer examples.deinit(allocator);

    var net = try sban.network.Network.init(allocator, options.net_config);
    defer net.deinit();
    try trainBytes(&net, seed_bytes);

    if (options.mode == .anchor or options.mode == .hybrid) {
        if (selectDialogueAnchor(prompt, examples.items)) |anchor| {
            const response = try generateAnchoredResponse(allocator, &net, prompt, anchor, options.continue_bytes);
            const mode_label = if (options.mode == .hybrid) "hybrid-anchor" else "anchor";
            try writer.print("prompt={s}\nmode={s}\nmatched_prompt={s}\nresponse={s}\n", .{ prompt, mode_label, anchor.user, response });
            return;
        }
        if (options.mode == .hybrid) {
            if (selectDialogueSupport(prompt, examples.items)) |support| {
                try writer.print("prompt={s}\nmode=hybrid-retrieved\nmatched_prompt={s}\nresponse={s}\n", .{ prompt, support.user, support.assistant });
                return;
            }
        }
    }

    const response = try generateFreeResponse(allocator, &net, prompt, options.max_bytes);
    const mode_label = if (options.mode == .hybrid) "hybrid-free" else "free";
    try writer.print("prompt={s}\nmode={s}\nresponse={s}\n", .{ prompt, mode_label, response });
}

fn runChatEval(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try printUsage(writer);
        try writer.flush();
        return;
    }

    const prompt_path = args[2];
    var options = ChatOptions{};
    parseChatOptions(writer, args, 3, &options) catch {
        try writer.flush();
        return;
    };

    const seed_bytes = try readWholeFile(allocator, io, options.seed_path);
    const prompt_bytes = try readWholeFile(allocator, io, prompt_path);
    var examples = try parseDialogueExamples(allocator, seed_bytes);
    defer examples.deinit(allocator);

    var net = try sban.network.Network.init(allocator, options.net_config);
    defer net.deinit();
    try trainBytes(&net, seed_bytes);

    var total: usize = 0;
    var anchored: usize = 0;
    var retrieved: usize = 0;
    var nonempty: usize = 0;
    var iter = std.mem.splitScalar(u8, prompt_bytes, '\n');
    while (iter.next()) |raw_line| {
        const prompt = trimLine(raw_line);
        if (prompt.len == 0 or prompt[0] == '#') continue;
        total += 1;
        if (options.mode == .anchor or options.mode == .hybrid) {
            if (selectDialogueAnchor(prompt, examples.items)) |anchor| {
                const response = try generateAnchoredResponse(allocator, &net, prompt, anchor, options.continue_bytes);
                if (response.len > 0) nonempty += 1;
                anchored += 1;
                const mode_label = if (options.mode == .hybrid) "hybrid-anchor" else "anchor";
                try writer.print("[{d}] prompt={s}\nmode={s}\nmatched_prompt={s}\nresponse={s}\n\n", .{ total, prompt, mode_label, anchor.user, response });
                continue;
            }
            if (options.mode == .hybrid) {
                if (selectDialogueSupport(prompt, examples.items)) |support| {
                    if (support.assistant.len > 0) nonempty += 1;
                    retrieved += 1;
                    try writer.print("[{d}] prompt={s}\nmode=hybrid-retrieved\nmatched_prompt={s}\nresponse={s}\n\n", .{ total, prompt, support.user, support.assistant });
                    continue;
                }
            }
        }
        const response = try generateFreeResponse(allocator, &net, prompt, options.max_bytes);
        if (response.len > 0) nonempty += 1;
        const mode_label = if (options.mode == .hybrid) "hybrid-free" else "free";
        try writer.print("[{d}] prompt={s}\nmode={s}\nresponse={s}\n\n", .{ total, prompt, mode_label, response });
    }
    try writer.print("summary turns={d} anchored={d} retrieved={d} nonempty={d}\n", .{ total, anchored, retrieved, nonempty });
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
            } else if (std.mem.eql(u8, key, "sequence_seed_path")) {
                corpus_cfg.sequence_seed_path = value;
            } else if (std.mem.eql(u8, key, "sequence_seed_offset")) {
                corpus_cfg.sequence_seed_offset = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.eql(u8, key, "sequence_seed_length")) {
                corpus_cfg.sequence_seed_length = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.eql(u8, key, "sequence_seed_on_reset")) {
                corpus_cfg.sequence_seed_on_reset = try parseEvalBool(value);
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
            try sban.experiment.runSingleCustom(io, arena, corpus_cfg, model_name, variant.label(), net_config)
        else
            try sban.experiment.runSingleVariant(io, arena, corpus_cfg, bits, variant);
        defer data.deinit();

        try writeExperimentFile(io, args[3], &data);
        try printExperimentSummary(writer, &data);
        try writer.print("wrote_json={s}\n", .{args[3]});
    } else if (std.mem.eql(u8, command, "chat-demo")) {
        try runChatDemo(arena, io, writer, args);
    } else if (std.mem.eql(u8, command, "chat-eval")) {
        try runChatEval(arena, io, writer, args);
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
