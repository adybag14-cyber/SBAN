const std = @import("std");
const Io = std.Io;
const sban = @import("zig_sban");

const DialogueExample = struct {
    user: []const u8,
    assistant: []const u8,
};

const MathExpression = struct {
    lhs: u64,
    rhs: u64,
    op: u8,
};

const ChatResult = struct {
    mode_label: []const u8,
    matched_prompt: ?[]const u8 = null,
    response: []const u8,
    anchored: bool = false,
    retrieved: bool = false,
    symbolic: bool = false,
};

const ChatOptions = struct {
    seed_path: []const u8 = "data/sban_dialogue_seed_v20.txt",
    session_path: ?[]const u8 = null,
    mode: enum { anchor, free, hybrid } = .hybrid,
    max_bytes: usize = 96,
    continue_bytes: usize = 0,
    net_config: sban.config.NetworkConfig = blk: {
        const config = sban.config.v20ReleaseConfig(4);
        break :blk config;
    },
};

fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\SBAN v20 - stable release health, persistent chat sessions, and stronger real-world usability
        \\Usage:
        \\  zig build run -- eval-enwik [dataset_path] [json_output_path] [prefix|drift] [segment_len] [checkpoint_interval] [rolling_window]
        \\  zig build run -- eval-ablations [dataset_path] [json_output_path] [prefix|drift] [bits] [segment_len] [checkpoint_interval] [rolling_window]
        \\  zig build run -- eval-variant [dataset_path] [json_output_path] [prefix|drift] [bits] [variant] [segment_len] [checkpoint_interval] [rolling_window] [key=value ...]
        \\  zig build run -- chat-demo [prompt] [max_bytes] [key=value ...]
        \\  zig build run -- chat-eval [prompt_file_path] [key=value ...]
        \\  zig build run -- chat-session-eval [script_file_path] [key=value ...]
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
    try writer.print("SBAN v20 experiment {s} ({s})\n", .{ data.meta.name, data.meta.protocol });
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

fn readOptionalWholeFile(allocator: std.mem.Allocator, io: std.Io, path: ?[]const u8) ![]u8 {
    const actual_path = path orelse return try allocator.alloc(u8, 0);
    return readWholeFile(allocator, io, actual_path) catch |err| switch (err) {
        error.FileNotFound => try allocator.alloc(u8, 0),
        else => return err,
    };
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

fn trimInlineValue(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, "\r\n \t.,!?;:\"'`()[]{}");
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

fn appendDialogueExamples(allocator: std.mem.Allocator, examples: *std.ArrayList(DialogueExample), bytes: []const u8) !void {
    if (bytes.len == 0) return;
    var extra = try parseDialogueExamples(allocator, bytes);
    defer extra.deinit(allocator);
    try examples.appendSlice(allocator, extra.items);
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

fn containsPhraseIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;
    var idx: usize = 0;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return true;
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

fn formatDisplayName(allocator: std.mem.Allocator, raw_name: []const u8) ![]u8 {
    var display = try allocator.dupe(u8, trimInlineValue(raw_name));
    var capitalize = true;
    var idx: usize = 0;
    while (idx < display.len) : (idx += 1) {
        const ch = display[idx];
        if (std.ascii.isAlphabetic(ch)) {
            display[idx] = if (capitalize) std.ascii.toUpper(ch) else std.ascii.toLower(ch);
            capitalize = false;
        } else {
            capitalize = ch == ' ' or ch == '-';
        }
    }
    return display;
}

fn takeLeadingNameCandidate(input: []const u8) ?[]const u8 {
    const trimmed = trimLine(input);
    if (trimmed.len == 0) return null;

    var idx: usize = 0;
    var end: usize = 0;
    var token_count: usize = 0;
    var in_token = false;
    while (idx < trimmed.len) : (idx += 1) {
        const ch = trimmed[idx];
        if (std.ascii.isAlphabetic(ch) or ch == '\'' or ch == '-') {
            if (!in_token) {
                token_count += 1;
                if (token_count > 3) break;
                in_token = true;
            }
            end = idx + 1;
        } else if (ch == ' ') {
            if (end == 0) break;
            in_token = false;
        } else {
            break;
        }
    }

    const candidate = trimInlineValue(trimmed[0..end]);
    if (candidate.len == 0) return null;
    if (containsTokenIgnoreCase(candidate, "and") or containsTokenIgnoreCase(candidate, "for") or containsTokenIgnoreCase(candidate, "help")) return null;
    return candidate;
}

fn extractNameFromPrompt(prompt: []const u8) ?[]const u8 {
    const markers = [_][]const u8{
        "my name is ",
        "call me ",
        "hi i'm ",
        "hi im ",
        "hi i am ",
        "hello i'm ",
        "hello im ",
        "hello i am ",
        "hey i'm ",
        "hey im ",
        "hey i am ",
    };

    for (markers) |marker| {
        if (std.mem.indexOf(u8, prompt, marker)) |idx| {
            return takeLeadingNameCandidate(prompt[idx + marker.len ..]);
        }
        if (containsPhraseIgnoreCase(prompt, marker)) {
            var start: usize = 0;
            while (start + marker.len <= prompt.len) : (start += 1) {
                if (std.ascii.eqlIgnoreCase(prompt[start .. start + marker.len], marker)) {
                    return takeLeadingNameCandidate(prompt[start + marker.len ..]);
                }
            }
        }
    }
    return null;
}

fn extractLatestRememberedName(dialogue_bytes: []const u8) ?[]const u8 {
    var latest: ?[]const u8 = null;
    var iter = std.mem.splitScalar(u8, dialogue_bytes, '\n');
    while (iter.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (!std.mem.startsWith(u8, line, "User:")) continue;
        const prompt = trimLine(line[5..]);
        if (extractNameFromPrompt(prompt)) |name| {
            latest = name;
        }
    }
    return latest;
}

fn isNameRecallPrompt(prompt: []const u8) bool {
    const markers = [_][]const u8{
        "recall my name",
        "remember my name",
        "what is my name",
        "what's my name",
        "who am i",
        "tell me my name",
        "say my name",
    };
    for (markers) |marker| {
        if (containsPhraseIgnoreCase(prompt, marker)) return true;
    }
    return false;
}

fn parseUnsignedInt(bytes: []const u8, start: usize) ?struct { value: u64, next_idx: usize } {
    if (start >= bytes.len or !std.ascii.isDigit(bytes[start])) return null;
    var idx = start;
    var value: u64 = 0;
    while (idx < bytes.len and std.ascii.isDigit(bytes[idx])) : (idx += 1) {
        value = value * 10 + (bytes[idx] - '0');
    }
    return .{ .value = value, .next_idx = idx };
}

fn extractSimpleMathExpression(prompt: []const u8) ?MathExpression {
    var idx: usize = 0;
    while (idx < prompt.len) : (idx += 1) {
        const lhs = parseUnsignedInt(prompt, idx) orelse continue;
        var mid = lhs.next_idx;
        while (mid < prompt.len and std.ascii.isWhitespace(prompt[mid])) : (mid += 1) {}
        if (mid >= prompt.len) {
            idx = lhs.next_idx;
            continue;
        }
        const op = prompt[mid];
        if (op != '+' and op != '-' and op != '*' and op != '/') {
            idx = lhs.next_idx;
            continue;
        }
        mid += 1;
        while (mid < prompt.len and std.ascii.isWhitespace(prompt[mid])) : (mid += 1) {}
        const rhs = parseUnsignedInt(prompt, mid) orelse {
            idx = lhs.next_idx;
            continue;
        };
        return .{ .lhs = lhs.value, .rhs = rhs.value, .op = op };
    }
    return null;
}

fn solveSimpleMath(allocator: std.mem.Allocator, prompt: []const u8) !?[]const u8 {
    const expr = extractSimpleMathExpression(prompt) orelse return null;
    return switch (expr.op) {
        '+' => try std.fmt.allocPrint(allocator, "{d} + {d} = {d}.", .{ expr.lhs, expr.rhs, expr.lhs + expr.rhs }),
        '-' => if (expr.lhs >= expr.rhs)
            try std.fmt.allocPrint(allocator, "{d} - {d} = {d}.", .{ expr.lhs, expr.rhs, expr.lhs - expr.rhs })
        else
            try std.fmt.allocPrint(allocator, "{d} - {d} = -{d}.", .{ expr.lhs, expr.rhs, expr.rhs - expr.lhs }),
        '*' => try std.fmt.allocPrint(allocator, "{d} * {d} = {d}.", .{ expr.lhs, expr.rhs, expr.lhs * expr.rhs }),
        '/' => if (expr.rhs == 0)
            try allocator.dupe(u8, "I cannot divide by zero.")
        else if (expr.lhs % expr.rhs == 0)
            try std.fmt.allocPrint(allocator, "{d} / {d} = {d}.", .{ expr.lhs, expr.rhs, @divTrunc(expr.lhs, expr.rhs) })
        else
            try std.fmt.allocPrint(allocator, "{d} / {d} = {d:.3}.", .{ expr.lhs, expr.rhs, @as(f64, @floatFromInt(expr.lhs)) / @as(f64, @floatFromInt(expr.rhs)) }),
        else => null,
    };
}

fn buildNameAcknowledgement(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const display = try formatDisplayName(allocator, name);
    return try std.fmt.allocPrint(allocator, "Hi {s}. I will remember your name for this session.", .{display});
}

fn buildNameRecall(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const display = try formatDisplayName(allocator, name);
    return try std.fmt.allocPrint(allocator, "Your name is {s}.", .{display});
}

fn buildFreeFallback(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "help") or containsPhraseIgnoreCase(prompt, "what can you do")) {
        return try allocator.dupe(u8, "I can answer release questions, continue a session, remember facts you tell me in this chat, and handle simple arithmetic prompts.");
    }
    return try allocator.dupe(u8, "I do not have a grounded answer yet. Ask about SBAN v20, tell me your name, or try a short factual prompt.");
}

fn isHelpPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "help") or
        containsPhraseIgnoreCase(prompt, "what can you do") or
        containsPhraseIgnoreCase(prompt, "what can i ask first");
}

fn appendSessionTurn(allocator: std.mem.Allocator, existing_session: []const u8, prompt: []const u8, response: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}User: {s}\nAssistant: {s}\n\n", .{ existing_session, prompt, response });
}

fn persistSessionBytes(io: std.Io, session_path: []const u8, session_bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = session_path, .data = session_bytes });
}

fn runSingleChatTurn(
    allocator: std.mem.Allocator,
    seed_bytes: []const u8,
    session_bytes: []const u8,
    prompt: []const u8,
    options: ChatOptions,
) !ChatResult {
    var examples = try parseDialogueExamples(allocator, seed_bytes);
    defer examples.deinit(allocator);
    try appendDialogueExamples(allocator, &examples, session_bytes);

    var net = try sban.network.Network.init(allocator, options.net_config);
    defer net.deinit();
    try trainBytes(&net, seed_bytes);
    try trainBytes(&net, session_bytes);

    if (extractNameFromPrompt(prompt)) |name| {
        const response = try buildNameAcknowledgement(allocator, name);
        return .{
            .mode_label = "session-memory",
            .response = response,
            .symbolic = true,
        };
    }

    if (isNameRecallPrompt(prompt)) {
        if (extractLatestRememberedName(session_bytes)) |name| {
            const response = try buildNameRecall(allocator, name);
            return .{
                .mode_label = "session-recall",
                .response = response,
                .symbolic = true,
            };
        }
        return .{
            .mode_label = "session-recall-miss",
            .response = try allocator.dupe(u8, "I do not know your name yet. Tell me with 'my name is ...' and I will remember it for this session."),
            .symbolic = true,
        };
    }

    if (try solveSimpleMath(allocator, prompt)) |response| {
        return .{
            .mode_label = "symbolic-math",
            .response = response,
            .symbolic = true,
        };
    }

    if (isHelpPrompt(prompt)) {
        return .{
            .mode_label = "symbolic-help",
            .response = try buildFreeFallback(allocator, prompt),
            .symbolic = true,
        };
    }

    if (options.mode == .anchor or options.mode == .hybrid) {
        if (selectDialogueAnchor(prompt, examples.items)) |anchor| {
            const response = try generateAnchoredResponse(allocator, &net, prompt, anchor, options.continue_bytes);
            const mode_label = if (options.mode == .hybrid) "hybrid-anchor" else "anchor";
            return .{
                .mode_label = mode_label,
                .matched_prompt = anchor.user,
                .response = response,
                .anchored = true,
            };
        }
        if (options.mode == .hybrid) {
            if (selectDialogueSupport(prompt, examples.items)) |support| {
                return .{
                    .mode_label = "hybrid-retrieved",
                    .matched_prompt = support.user,
                    .response = support.assistant,
                    .retrieved = true,
                };
            }
        }
    }

    if (options.mode == .free) {
        if (selectDialogueSupport(prompt, examples.items)) |support| {
            return .{
                .mode_label = "free-retrieved",
                .matched_prompt = support.user,
                .response = support.assistant,
                .retrieved = true,
            };
        }
    }

    const response = try generateFreeResponse(allocator, &net, prompt, options.max_bytes);
    if (response.len > 0) {
        const mode_label = if (options.mode == .hybrid) "hybrid-free" else "free";
        return .{
            .mode_label = mode_label,
            .response = response,
        };
    }

    return .{
        .mode_label = "free-fallback",
        .response = try buildFreeFallback(allocator, prompt),
    };
}

fn printChatResult(writer: *Io.Writer, prompt: []const u8, result: ChatResult) !void {
    if (result.matched_prompt) |matched_prompt| {
        try writer.print("prompt={s}\nmode={s}\nmatched_prompt={s}\nresponse={s}\n", .{ prompt, result.mode_label, matched_prompt, result.response });
    } else {
        try writer.print("prompt={s}\nmode={s}\nresponse={s}\n", .{ prompt, result.mode_label, result.response });
    }
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
        } else if (std.mem.eql(u8, key, "session_path")) {
            options.session_path = value;
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
    const session_bytes = try readOptionalWholeFile(allocator, io, options.session_path);
    const result = try runSingleChatTurn(allocator, seed_bytes, session_bytes, prompt, options);
    try printChatResult(writer, prompt, result);

    if (options.session_path) |session_path| {
        const updated_session = try appendSessionTurn(allocator, session_bytes, prompt, result.response);
        try persistSessionBytes(io, session_path, updated_session);
    }
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

    var total: usize = 0;
    var anchored: usize = 0;
    var retrieved: usize = 0;
    var symbolic: usize = 0;
    var nonempty: usize = 0;
    var iter = std.mem.splitScalar(u8, prompt_bytes, '\n');
    while (iter.next()) |raw_line| {
        const prompt = trimLine(raw_line);
        if (prompt.len == 0 or prompt[0] == '#') continue;
        total += 1;
        const result = try runSingleChatTurn(allocator, seed_bytes, "", prompt, options);
        if (result.response.len > 0) nonempty += 1;
        if (result.anchored) anchored += 1;
        if (result.retrieved) retrieved += 1;
        if (result.symbolic) symbolic += 1;
        try writer.print("[{d}] ", .{total});
        try printChatResult(writer, prompt, result);
        try writer.writeAll("\n");
    }
    try writer.print("summary turns={d} anchored={d} retrieved={d} symbolic={d} nonempty={d}\n", .{ total, anchored, retrieved, symbolic, nonempty });
}

fn runChatSessionEval(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try printUsage(writer);
        try writer.flush();
        return;
    }

    const script_path = args[2];
    var options = ChatOptions{};
    parseChatOptions(writer, args, 3, &options) catch {
        try writer.flush();
        return;
    };

    const seed_bytes = try readWholeFile(allocator, io, options.seed_path);
    const script_bytes = try readWholeFile(allocator, io, script_path);

    var session_bytes: []const u8 = try allocator.alloc(u8, 0);
    var turns: usize = 0;
    var anchored: usize = 0;
    var retrieved: usize = 0;
    var symbolic: usize = 0;
    var nonempty: usize = 0;
    var expectations: usize = 0;
    var passed: usize = 0;
    var last_response: []const u8 = "";

    var iter = std.mem.splitScalar(u8, script_bytes, '\n');
    while (iter.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "User:")) {
            const prompt = trimLine(line[5..]);
            turns += 1;
            const result = try runSingleChatTurn(allocator, seed_bytes, session_bytes, prompt, options);
            if (result.response.len > 0) nonempty += 1;
            if (result.anchored) anchored += 1;
            if (result.retrieved) retrieved += 1;
            if (result.symbolic) symbolic += 1;
            try writer.print("[{d}] ", .{turns});
            try printChatResult(writer, prompt, result);
            try writer.writeAll("\n");
            session_bytes = try appendSessionTurn(allocator, session_bytes, prompt, result.response);
            last_response = result.response;
        } else if (std.mem.startsWith(u8, line, "Expect:")) {
            const expected = trimLine(line[7..]);
            expectations += 1;
            const ok = containsPhraseIgnoreCase(last_response, expected);
            if (ok) passed += 1;
            try writer.print("expect_contains={s}\nexpect_pass={s}\n\n", .{ expected, if (ok) "true" else "false" });
        }
    }

    try writer.print(
        "summary turns={d} anchored={d} retrieved={d} symbolic={d} nonempty={d} expectations={d} passed={d}\n",
        .{ turns, anchored, retrieved, symbolic, nonempty, expectations, passed },
    );
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
    } else if (std.mem.eql(u8, command, "chat-session-eval")) {
        try runChatSessionEval(arena, io, writer, args);
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

test "extract name from prompt" {
    try std.testing.expectEqualStrings("tom", extractNameFromPrompt("hi im tom").?);
    try std.testing.expectEqualStrings("Ada Lovelace", extractNameFromPrompt("my name is Ada Lovelace").?);
}

test "extract latest remembered name" {
    const dialogue =
        \\User: hello
        \\Assistant: hi
        \\
        \\User: hi im tom
        \\Assistant: Hello Tom.
        \\
        \\User: thank you
        \\Assistant: You are welcome.
    ;
    try std.testing.expectEqualStrings("tom", extractLatestRememberedName(dialogue).?);
}

test "detect name recall prompt" {
    try std.testing.expect(isNameRecallPrompt("can you recall my name"));
    try std.testing.expect(isNameRecallPrompt("what is my name"));
    try std.testing.expect(!isNameRecallPrompt("my name is tom"));
}

test "extract simple math expression" {
    const expr = extractSimpleMathExpression("what is 2 + 2").?;
    try std.testing.expectEqual(@as(u64, 2), expr.lhs);
    try std.testing.expectEqual(@as(u64, 2), expr.rhs);
    try std.testing.expectEqual(@as(u8, '+'), expr.op);
}
