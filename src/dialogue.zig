const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const cfg = @import("config.zig");
const netmod = @import("network.zig");

const feature_dim = 128;
const session_magic = "SBAN_SESSION_V22";
const legacy_session_magic = "SBAN_SESSION_V21";
const max_top_candidates = 16;

const ChatMode = enum { anchor, free, hybrid };
const AccelBackend = enum { auto, cpu, gpu };

pub const DialogueExample = struct {
    user: []const u8,
    assistant: []const u8,
};

pub const ChatResult = struct {
    mode_label: []const u8,
    matched_prompt: ?[]const u8 = null,
    response: []const u8,
    anchored: bool = false,
    retrieved: bool = false,
    symbolic: bool = false,
};

pub const ChatOptions = struct {
    seed_path: []const u8 = "data/sban_dialogue_seed_v22.txt",
    session_path: ?[]const u8 = null,
    mode: ChatMode = .hybrid,
    backend: AccelBackend = .auto,
    max_bytes: usize = 160,
    continue_bytes: usize = 0,
    allow_generation: bool = false,
    net_config: cfg.NetworkConfig = blk: {
        const config = cfg.v22ReleaseConfig(4);
        break :blk config;
    },
};

const SessionTurn = struct {
    user: []const u8,
    assistant: []const u8,
};

const SessionFact = struct {
    key: []const u8,
    value: []const u8,
};

const SessionState = struct {
    turns: std.ArrayList(SessionTurn) = .empty,
    facts: std.ArrayList(SessionFact) = .empty,

    fn deinit(self: *SessionState, allocator: std.mem.Allocator) void {
        for (self.turns.items) |turn| {
            allocator.free(turn.user);
            allocator.free(turn.assistant);
        }
        for (self.facts.items) |fact| {
            allocator.free(fact.key);
            allocator.free(fact.value);
        }
        self.turns.deinit(allocator);
        self.facts.deinit(allocator);
    }

    fn rememberFact(self: *SessionState, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        const normalized_key = try normalizeFactKey(allocator, key);
        const normalized_value = try sanitizeTurnText(allocator, value);
        for (self.facts.items) |*fact| {
            if (std.ascii.eqlIgnoreCase(fact.key, normalized_key)) {
                allocator.free(normalized_key);
                allocator.free(fact.value);
                fact.value = normalized_value;
                return;
            }
        }
        try self.facts.append(allocator, .{ .key = normalized_key, .value = normalized_value });
    }

    fn lookupFact(self: *const SessionState, key: []const u8) ?SessionFact {
        var idx = self.facts.items.len;
        while (idx > 0) {
            idx -= 1;
            const fact = self.facts.items[idx];
            if (std.ascii.eqlIgnoreCase(fact.key, key)) return fact;
        }
        return null;
    }

    fn appendTurn(self: *SessionState, allocator: std.mem.Allocator, user: []const u8, assistant: []const u8) !void {
        try self.turns.append(allocator, .{
            .user = try sanitizeTurnText(allocator, user),
            .assistant = try sanitizeTurnText(allocator, assistant),
        });
    }
};

const IntentKind = enum {
    what,
    how,
    why,
    explain,
    compare,
    should,
    can,
    where,
    other,
};

const TokenizedText = struct {
    normalized: []u8,
    token_hashes: std.ArrayList(u64) = .empty,
    bigram_hashes: std.ArrayList(u64) = .empty,
    intent: IntentKind = .other,
    vector: [feature_dim]u16 = [_]u16{0} ** feature_dim,

    fn deinit(self: *TokenizedText, allocator: std.mem.Allocator) void {
        allocator.free(self.normalized);
        self.token_hashes.deinit(allocator);
        self.bigram_hashes.deinit(allocator);
    }
};

const PreparedExample = struct {
    example: DialogueExample,
    vector: [feature_dim]u16,
};

const PreparedCorpus = struct {
    items: std.ArrayList(PreparedExample) = .empty,

    fn deinit(self: *PreparedCorpus, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }
};

const ApproxScore = struct {
    index: usize,
    score: u32,
};

const LexicalScore = struct {
    score: i32,
    overlap: usize,
    bigram_overlap: usize,
    prompt_cov_ppm: u32,
    candidate_cov_ppm: u32,
    exact: bool,
    intent_match: bool,
};

const FactCandidate = struct {
    key: []const u8,
    value: []const u8,
};

const MathOutcome = struct {
    response: []const u8,
    explicit_error: bool = false,
};

const OpenClUnavailable = error{
    NoOpenClLoader,
    NoGpuDevice,
    InvalidKernel,
    OpenClFailure,
};

const cl_int = i32;
const cl_uint = u32;
const cl_bool = cl_uint;
const cl_ulong = u64;
const cl_bitfield = cl_ulong;
const cl_device_type = cl_bitfield;
const cl_mem_flags = cl_bitfield;
const cl_platform_info = cl_uint;
const cl_device_info = cl_uint;
const cl_program_build_info = cl_uint;
const cl_command_queue_properties = cl_bitfield;
const cl_platform_id = ?*anyopaque;
const cl_device_id = ?*anyopaque;
const cl_context = ?*anyopaque;
const cl_command_queue = ?*anyopaque;
const cl_program = ?*anyopaque;
const cl_kernel = ?*anyopaque;
const cl_mem = ?*anyopaque;

const cl_success: cl_int = 0;
const cl_device_not_found: cl_int = -1;
const cl_true: cl_bool = 1;
const cl_device_type_gpu: cl_device_type = 1 << 2;
const cl_mem_read_only: cl_mem_flags = 1 << 2;
const cl_mem_write_only: cl_mem_flags = 1 << 1;
const cl_mem_copy_host_ptr: cl_mem_flags = 1 << 5;
const cl_platform_name: cl_platform_info = 0x0902;
const cl_device_name: cl_device_info = 0x102B;
const cl_program_build_log: cl_program_build_info = 0x1183;

const ClGetPlatformIDsFn = *const fn(cl_uint, ?[*]cl_platform_id, *cl_uint) callconv(.c) cl_int;
const ClGetPlatformInfoFn = *const fn(cl_platform_id, cl_platform_info, usize, ?*anyopaque, *usize) callconv(.c) cl_int;
const ClGetDeviceIDsFn = *const fn(cl_platform_id, cl_device_type, cl_uint, ?[*]cl_device_id, *cl_uint) callconv(.c) cl_int;
const ClGetDeviceInfoFn = *const fn(cl_device_id, cl_device_info, usize, ?*anyopaque, *usize) callconv(.c) cl_int;
const ClCreateContextFn = *const fn(?[*]const isize, cl_uint, [*]const cl_device_id, ?*const fn([*:0]const u8, ?*const anyopaque, usize, ?*anyopaque) callconv(.c) void, ?*anyopaque, *cl_int) callconv(.c) cl_context;
const ClCreateCommandQueueFn = *const fn(cl_context, cl_device_id, cl_command_queue_properties, *cl_int) callconv(.c) cl_command_queue;
const ClCreateProgramWithSourceFn = *const fn(cl_context, cl_uint, [*]const [*:0]const u8, [*]const usize, *cl_int) callconv(.c) cl_program;
const ClBuildProgramFn = *const fn(cl_program, cl_uint, ?[*]const cl_device_id, ?[*:0]const u8, ?*const fn(cl_program, ?*anyopaque) callconv(.c) void, ?*anyopaque) callconv(.c) cl_int;
const ClGetProgramBuildInfoFn = *const fn(cl_program, cl_device_id, cl_program_build_info, usize, ?*anyopaque, *usize) callconv(.c) cl_int;
const ClCreateKernelFn = *const fn(cl_program, [*:0]const u8, *cl_int) callconv(.c) cl_kernel;
const ClCreateBufferFn = *const fn(cl_context, cl_mem_flags, usize, ?*anyopaque, *cl_int) callconv(.c) cl_mem;
const ClSetKernelArgFn = *const fn(cl_kernel, cl_uint, usize, ?*const anyopaque) callconv(.c) cl_int;
const ClEnqueueWriteBufferFn = *const fn(cl_command_queue, cl_mem, cl_bool, usize, usize, ?*const anyopaque, cl_uint, ?*const anyopaque, ?*anyopaque) callconv(.c) cl_int;
const ClEnqueueNDRangeKernelFn = *const fn(cl_command_queue, cl_kernel, cl_uint, ?[*]const usize, [*]const usize, ?[*]const usize, cl_uint, ?*const anyopaque, ?*anyopaque) callconv(.c) cl_int;
const ClEnqueueReadBufferFn = *const fn(cl_command_queue, cl_mem, cl_bool, usize, usize, ?*anyopaque, cl_uint, ?*const anyopaque, ?*anyopaque) callconv(.c) cl_int;
const ClFinishFn = *const fn(cl_command_queue) callconv(.c) cl_int;
const ClReleaseMemObjectFn = *const fn(cl_mem) callconv(.c) cl_int;
const ClReleaseKernelFn = *const fn(cl_kernel) callconv(.c) cl_int;
const ClReleaseProgramFn = *const fn(cl_program) callconv(.c) cl_int;
const ClReleaseCommandQueueFn = *const fn(cl_command_queue) callconv(.c) cl_int;
const ClReleaseContextFn = *const fn(cl_context) callconv(.c) cl_int;

const OpenClApi = struct {
    get_platform_ids: ClGetPlatformIDsFn,
    get_platform_info: ClGetPlatformInfoFn,
    get_device_ids: ClGetDeviceIDsFn,
    get_device_info: ClGetDeviceInfoFn,
    create_context: ClCreateContextFn,
    create_command_queue: ClCreateCommandQueueFn,
    create_program_with_source: ClCreateProgramWithSourceFn,
    build_program: ClBuildProgramFn,
    get_program_build_info: ClGetProgramBuildInfoFn,
    create_kernel: ClCreateKernelFn,
    create_buffer: ClCreateBufferFn,
    set_kernel_arg: ClSetKernelArgFn,
    enqueue_write_buffer: ClEnqueueWriteBufferFn,
    enqueue_nd_range_kernel: ClEnqueueNDRangeKernelFn,
    enqueue_read_buffer: ClEnqueueReadBufferFn,
    finish: ClFinishFn,
    release_mem_object: ClReleaseMemObjectFn,
    release_kernel: ClReleaseKernelFn,
    release_program: ClReleaseProgramFn,
    release_command_queue: ClReleaseCommandQueueFn,
    release_context: ClReleaseContextFn,
};

const DynamicLibrary = if (builtin.os.tag == .windows) WindowsDynamicLibrary else PosixDynamicLibrary;

const WindowsDynamicLibrary = struct {
    handle: ?*anyopaque,

    extern "kernel32" fn LoadLibraryA(path: [*:0]const u8) callconv(.c) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(handle: ?*anyopaque, name: [*:0]const u8) callconv(.c) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(handle: ?*anyopaque) callconv(.c) i32;

    fn open(path: [:0]const u8) !WindowsDynamicLibrary {
        const handle = LoadLibraryA(path.ptr) orelse return OpenClUnavailable.NoOpenClLoader;
        return .{ .handle = handle };
    }

    fn close(self: *WindowsDynamicLibrary) void {
        if (self.handle != null) _ = FreeLibrary(self.handle);
        self.handle = null;
    }

    fn lookup(self: *WindowsDynamicLibrary, comptime T: type, name: [:0]const u8) ?T {
        const addr = GetProcAddress(self.handle, name.ptr) orelse return null;
        return @as(T, @ptrCast(addr));
    }
};

const PosixDynamicLibrary = struct {
    inner: std.DynLib,

    fn open(path: [:0]const u8) !PosixDynamicLibrary {
        return .{ .inner = try std.DynLib.open(path) };
    }

    fn close(self: *PosixDynamicLibrary) void {
        self.inner.close();
    }

    fn lookup(self: *PosixDynamicLibrary, comptime T: type, name: [:0]const u8) ?T {
        return self.inner.lookup(T, name);
    }
};

const OpenClScorer = struct {
    allocator: std.mem.Allocator,
    lib: DynamicLibrary,
    api: OpenClApi,
    context: cl_context,
    queue: cl_command_queue,
    program: cl_program,
    kernel: cl_kernel,
    example_buffer: cl_mem,
    prompt_buffer: cl_mem,
    output_buffer: cl_mem,
    example_count: usize,
    device: cl_device_id,
    device_name: []u8,
    platform_name: []u8,

    fn init(allocator: std.mem.Allocator, flat_matrix: []const u16, example_count: usize) !OpenClScorer {
        var lib = try openOpenClLibrary();
        errdefer lib.close();
        const api = try loadOpenClApi(&lib);

        const platform = try chooseGpuPlatform(api);
        const device = try chooseGpuDevice(api, platform);
        const platform_name_bytes = try queryInfoString(allocator, api.get_platform_info, platform, cl_platform_name);
        errdefer allocator.free(platform_name_bytes);
        const device_name_bytes = try queryInfoString(allocator, api.get_device_info, device, cl_device_name);
        errdefer allocator.free(device_name_bytes);

        var errcode: cl_int = 0;
        const devices = [_]cl_device_id{device};
        const context = api.create_context(null, 1, &devices, null, null, &errcode);
        try checkCl(errcode);
        errdefer _ = api.release_context(context);

        const queue = api.create_command_queue(context, device, 0, &errcode);
        try checkCl(errcode);
        errdefer _ = api.release_command_queue(queue);

        const source: [*:0]const u8 = kernel_source;
        const sources = [_][*:0]const u8{source};
        const lengths = [_]usize{kernel_source.len};
        const program = api.create_program_with_source(context, 1, &sources, &lengths, &errcode);
        try checkCl(errcode);
        errdefer _ = api.release_program(program);

        errcode = api.build_program(program, 1, &devices, null, null, null);
        if (errcode != cl_success) {
            const log = queryProgramBuildLog(allocator, api, program, device) catch "unknown OpenCL build failure";
            std.log.err("OpenCL kernel build failed: {s}", .{log});
            return OpenClUnavailable.InvalidKernel;
        }

        const kernel = api.create_kernel(program, "score_examples", &errcode);
        try checkCl(errcode);
        errdefer _ = api.release_kernel(kernel);

        const example_bytes = flat_matrix.len * @sizeOf(u16);
        const example_buffer = api.create_buffer(context, cl_mem_read_only | cl_mem_copy_host_ptr, example_bytes, @constCast(@ptrCast(flat_matrix.ptr)), &errcode);
        try checkCl(errcode);
        errdefer _ = api.release_mem_object(example_buffer);

        const prompt_buffer = api.create_buffer(context, cl_mem_read_only, feature_dim * @sizeOf(u16), null, &errcode);
        try checkCl(errcode);
        errdefer _ = api.release_mem_object(prompt_buffer);

        const output_buffer = api.create_buffer(context, cl_mem_write_only, example_count * @sizeOf(u32), null, &errcode);
        try checkCl(errcode);
        errdefer _ = api.release_mem_object(output_buffer);

        return .{
            .allocator = allocator,
            .lib = lib,
            .api = api,
            .context = context,
            .queue = queue,
            .program = program,
            .kernel = kernel,
            .example_buffer = example_buffer,
            .prompt_buffer = prompt_buffer,
            .output_buffer = output_buffer,
            .example_count = example_count,
            .device = device,
            .device_name = device_name_bytes,
            .platform_name = platform_name_bytes,
        };
    }

    fn deinit(self: *OpenClScorer) void {
        _ = self.api.release_mem_object(self.output_buffer);
        _ = self.api.release_mem_object(self.prompt_buffer);
        _ = self.api.release_mem_object(self.example_buffer);
        _ = self.api.release_kernel(self.kernel);
        _ = self.api.release_program(self.program);
        _ = self.api.release_command_queue(self.queue);
        _ = self.api.release_context(self.context);
        self.lib.close();
        self.allocator.free(self.device_name);
        self.allocator.free(self.platform_name);
    }

    fn score(self: *OpenClScorer, prompt_vector: *const [feature_dim]u16, output: []u32) !void {
        if (output.len != self.example_count) return error.InvalidArgument;

        try checkCl(self.api.enqueue_write_buffer(
            self.queue,
            self.prompt_buffer,
            cl_true,
            0,
            feature_dim * @sizeOf(u16),
            @ptrCast(prompt_vector),
            0,
            null,
            null,
        ));

        try checkCl(self.api.set_kernel_arg(self.kernel, 0, @sizeOf(cl_mem), @ptrCast(&self.prompt_buffer)));
        try checkCl(self.api.set_kernel_arg(self.kernel, 1, @sizeOf(cl_mem), @ptrCast(&self.example_buffer)));
        try checkCl(self.api.set_kernel_arg(self.kernel, 2, @sizeOf(cl_mem), @ptrCast(&self.output_buffer)));
        const dim_value: cl_uint = feature_dim;
        try checkCl(self.api.set_kernel_arg(self.kernel, 3, @sizeOf(cl_uint), @ptrCast(&dim_value)));

        const global = [_]usize{self.example_count};
        try checkCl(self.api.enqueue_nd_range_kernel(self.queue, self.kernel, 1, null, &global, null, 0, null, null));
        try checkCl(self.api.finish(self.queue));
        try checkCl(self.api.enqueue_read_buffer(
            self.queue,
            self.output_buffer,
            cl_true,
            0,
            output.len * @sizeOf(u32),
            output.ptr,
            0,
            null,
            null,
        ));
    }
};

const ApproximateScorer = struct {
    backend_used: enum { cpu, gpu },
    gpu: ?OpenClScorer = null,

    fn init(allocator: std.mem.Allocator, preference: AccelBackend, corpus: *const PreparedCorpus) !ApproximateScorer {
        switch (preference) {
            .cpu => return .{ .backend_used = .cpu, .gpu = null },
            .gpu => return .{ .backend_used = .gpu, .gpu = try initGpuScorer(allocator, corpus) },
            .auto => {
                const gpu = initGpuScorer(allocator, corpus) catch {
                    return .{ .backend_used = .cpu, .gpu = null };
                };
                return .{ .backend_used = .gpu, .gpu = gpu };
            },
        }
    }

    fn deinit(self: *ApproximateScorer) void {
        if (self.gpu) |*gpu| gpu.deinit();
    }

    fn backendLabel(self: *const ApproximateScorer) []const u8 {
        return switch (self.backend_used) {
            .cpu => "cpu",
            .gpu => "gpu",
        };
    }

    fn score(self: *ApproximateScorer, corpus: *const PreparedCorpus, prompt_vector: *const [feature_dim]u16, output: []u32) !void {
        if (self.gpu) |*gpu| {
            return gpu.score(prompt_vector, output);
        }
        for (corpus.items.items, 0..) |item, idx| {
            output[idx] = dotProduct(prompt_vector, &item.vector);
        }
    }
};

pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\  zig build run -- chat-demo [prompt] [max_bytes] [key=value ...]
        \\  zig build run -- chat-eval [prompt_file_path] [key=value ...]
        \\  zig build run -- chat-session-eval [script_file_path] [key=value ...]
        \\  zig build run -- accel-info [key=value ...]
    );
}

pub fn runAccelInfo(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, args: []const []const u8) !void {
    var options = ChatOptions{};
    parseChatOptions(writer, args, 2, &options) catch {
        try writer.flush();
        return;
    };

    const seed_bytes = readWholeFileFriendly(allocator, io, writer, options.seed_path, "seed_path") orelse return;
    defer allocator.free(seed_bytes);
    var examples = parseDialogueExamples(allocator, seed_bytes) catch {
        try writer.writeAll("error=invalid_seed_format\n");
        try writer.flush();
        return;
    };
    defer examples.deinit(allocator);
    var corpus = try prepareCorpus(allocator, examples.items);
    defer corpus.deinit(allocator);

    var scorer = ApproximateScorer.init(allocator, options.backend, &corpus) catch |err| {
        try writer.print("backend=cpu\nreason={s}\n", .{@errorName(err)});
        return;
    };
    defer scorer.deinit();

    if (scorer.gpu) |*gpu| {
        try writer.print("backend=gpu\nplatform={s}\ndevice={s}\n", .{ gpu.platform_name, gpu.device_name });
    } else {
        try writer.writeAll("backend=cpu\nreason=no_gpu_accelerator\n");
    }
}

pub fn runChatDemo(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try writer.writeAll("error=missing_prompt\n");
        try writer.flush();
        return;
    }

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

    const prompt = try sanitizeTurnText(allocator, args[2]);
    defer allocator.free(prompt);
    const seed_bytes = readWholeFileFriendly(allocator, io, writer, options.seed_path, "seed_path") orelse return;
    defer allocator.free(seed_bytes);
    var examples = parseDialogueExamples(allocator, seed_bytes) catch {
        try writer.writeAll("error=invalid_seed_format\n");
        try writer.flush();
        return;
    };
    defer examples.deinit(allocator);
    var corpus = try prepareCorpus(allocator, examples.items);
    defer corpus.deinit(allocator);

    var scorer = ApproximateScorer.init(allocator, options.backend, &corpus) catch |err| {
        try writer.print("error=accelerator_init_failed detail={s}\n", .{@errorName(err)});
        try writer.flush();
        return;
    };
    defer scorer.deinit();

    var session = loadSessionState(allocator, io, options.session_path) catch SessionState{};
    defer session.deinit(allocator);

    const result = answerPrompt(allocator, prompt, seed_bytes, examples.items, &corpus, &session, &scorer, options) catch |err| {
        try writer.print("error=chat_failed detail={s}\n", .{@errorName(err)});
        try writer.flush();
        return;
    };

    try printChatResult(allocator, writer, prompt, result, scorer.backendLabel());
    try session.appendTurn(allocator, prompt, result.response);
    saveSessionState(io, options.session_path, &session) catch |err| {
        try writer.print("warning=session_save_failed detail={s}\n", .{@errorName(err)});
    };
}

pub fn runChatEval(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try writer.writeAll("error=missing_prompt_file\n");
        try writer.flush();
        return;
    }

    var options = ChatOptions{};
    parseChatOptions(writer, args, 3, &options) catch {
        try writer.flush();
        return;
    };

    const seed_bytes = readWholeFileFriendly(allocator, io, writer, options.seed_path, "seed_path") orelse return;
    defer allocator.free(seed_bytes);
    const prompt_bytes = readWholeFileFriendly(allocator, io, writer, args[2], "prompt_path") orelse return;
    defer allocator.free(prompt_bytes);
    var examples = parseDialogueExamples(allocator, seed_bytes) catch {
        try writer.writeAll("error=invalid_seed_format\n");
        try writer.flush();
        return;
    };
    defer examples.deinit(allocator);
    var corpus = try prepareCorpus(allocator, examples.items);
    defer corpus.deinit(allocator);
    var scorer = ApproximateScorer.init(allocator, options.backend, &corpus) catch |err| {
        try writer.print("error=accelerator_init_failed detail={s}\n", .{@errorName(err)});
        try writer.flush();
        return;
    };
    defer scorer.deinit();

    var total: usize = 0;
    var anchored: usize = 0;
    var retrieved: usize = 0;
    var symbolic: usize = 0;
    var nonempty: usize = 0;
    var iter = std.mem.splitScalar(u8, prompt_bytes, '\n');
    while (iter.next()) |raw_line| {
        const prompt = try sanitizeTurnText(allocator, trimLine(raw_line));
        if (prompt.len == 0 or prompt[0] == '#') continue;
        total += 1;
        var session: SessionState = .{};
        defer session.deinit(allocator);
        const result = try answerPrompt(allocator, prompt, seed_bytes, examples.items, &corpus, &session, &scorer, options);
        if (result.response.len > 0) nonempty += 1;
        if (result.anchored) anchored += 1;
        if (result.retrieved) retrieved += 1;
        if (result.symbolic) symbolic += 1;
        try writer.print("[{d}] ", .{total});
        try printChatResult(allocator, writer, prompt, result, scorer.backendLabel());
        try writer.writeAll("\n");
    }
    try writer.print("summary turns={d} anchored={d} retrieved={d} symbolic={d} nonempty={d}\n", .{ total, anchored, retrieved, symbolic, nonempty });
}

pub fn runChatSessionEval(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try writer.writeAll("error=missing_script_file\n");
        try writer.flush();
        return;
    }

    var options = ChatOptions{};
    parseChatOptions(writer, args, 3, &options) catch {
        try writer.flush();
        return;
    };

    const seed_bytes = readWholeFileFriendly(allocator, io, writer, options.seed_path, "seed_path") orelse return;
    defer allocator.free(seed_bytes);
    const script_bytes = readWholeFileFriendly(allocator, io, writer, args[2], "script_path") orelse return;
    defer allocator.free(script_bytes);
    var examples = parseDialogueExamples(allocator, seed_bytes) catch {
        try writer.writeAll("error=invalid_seed_format\n");
        try writer.flush();
        return;
    };
    defer examples.deinit(allocator);
    var corpus = try prepareCorpus(allocator, examples.items);
    defer corpus.deinit(allocator);
    var scorer = ApproximateScorer.init(allocator, options.backend, &corpus) catch |err| {
        try writer.print("error=accelerator_init_failed detail={s}\n", .{@errorName(err)});
        try writer.flush();
        return;
    };
    defer scorer.deinit();

    var session: SessionState = .{};
    defer session.deinit(allocator);
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
            const prompt = try sanitizeTurnText(allocator, trimLine(line[5..]));
            turns += 1;
            const result = try answerPrompt(allocator, prompt, seed_bytes, examples.items, &corpus, &session, &scorer, options);
            if (result.response.len > 0) nonempty += 1;
            if (result.anchored) anchored += 1;
            if (result.retrieved) retrieved += 1;
            if (result.symbolic) symbolic += 1;
            try writer.print("[{d}] ", .{turns});
            try printChatResult(allocator, writer, prompt, result, scorer.backendLabel());
            try writer.writeAll("\n");
            try session.appendTurn(allocator, prompt, result.response);
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

fn answerPrompt(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    seed_bytes: []const u8,
    _: []const DialogueExample,
    corpus: *const PreparedCorpus,
    session: *SessionState,
    scorer: *ApproximateScorer,
    options: ChatOptions,
) !ChatResult {
    if (try extractMemoryCapabilityQuery(allocator, prompt)) |fact_key| {
        defer allocator.free(fact_key);
        return .{
            .mode_label = "session-memory-capability",
            .response = try buildFactCapabilityResponse(allocator, fact_key),
            .symbolic = true,
        };
    }

    if (try extractFactQuery(allocator, prompt)) |fact_key| {
        defer allocator.free(fact_key);
        if (session.lookupFact(fact_key)) |fact| {
            return .{
                .mode_label = "session-recall",
                .response = try buildFactRecallResponse(allocator, fact),
                .symbolic = true,
            };
        }
        return .{
            .mode_label = "session-recall-miss",
            .response = try buildFactRecallMiss(allocator, fact_key),
            .symbolic = true,
        };
    }

    if (try solveMath(allocator, prompt)) |math| {
        return .{
            .mode_label = if (math.explicit_error) "symbolic-math-error" else "symbolic-math",
            .response = math.response,
            .symbolic = true,
        };
    }

    const maybe_fact = try extractFactCandidate(allocator, prompt);
    const wants_help = isHelpPrompt(prompt);
    if (maybe_fact) |fact| {
        defer allocator.free(fact.key);
        defer allocator.free(fact.value);
        try session.rememberFact(allocator, fact.key, fact.value);
        if (wants_help) {
            return .{
                .mode_label = "session-fact-help",
                .response = try buildFactHelpResponse(allocator, fact),
                .symbolic = true,
            };
        }
        return .{
            .mode_label = "session-fact-store",
            .response = try buildFactStoredResponse(allocator, fact),
            .symbolic = true,
        };
    }

    if (wants_help) {
        return .{
            .mode_label = "symbolic-help",
            .response = try buildHelpResponse(allocator),
            .symbolic = true,
        };
    }

    var prompt_tokens = try tokenizeText(allocator, prompt);
    defer prompt_tokens.deinit(allocator);

    if (options.mode == .anchor or options.mode == .hybrid) {
        if (try selectGroundedMatch(allocator, prompt, &prompt_tokens, corpus, scorer, .anchor)) |match| {
            const response = try maybeGroundedContinuation(allocator, seed_bytes, prompt, match.example, session, options);
            return .{
                .mode_label = if (options.mode == .hybrid) "hybrid-anchor" else "anchor",
                .matched_prompt = match.example.user,
                .response = response,
                .anchored = true,
            };
        }
    }

    if (options.mode == .hybrid or options.mode == .free) {
        if (try selectGroundedMatch(allocator, prompt, &prompt_tokens, corpus, scorer, .retrieval)) |match| {
            return .{
                .mode_label = if (options.mode == .hybrid) "hybrid-retrieved" else "free-retrieved",
                .matched_prompt = match.example.user,
                .response = match.example.assistant,
                .retrieved = true,
            };
        }
    }

    if (options.allow_generation and isDomainPrompt(prompt)) {
        const transcript = try renderSessionTranscript(allocator, session);
        defer allocator.free(transcript);
        const response = try generateFreeResponse(allocator, seed_bytes, transcript, prompt, options);
        if (response.len > 0) {
            return .{
                .mode_label = "generated",
                .response = response,
            };
        }
    }

    return .{
        .mode_label = "uncertain",
        .response = try buildUncertaintyResponse(allocator, prompt),
    };
}

const MatchRequest = enum { anchor, retrieval };

const SelectedMatch = struct {
    example: DialogueExample,
    exact_score: i32,
};

fn selectGroundedMatch(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    prompt_tokens: *const TokenizedText,
    corpus: *const PreparedCorpus,
    scorer: *ApproximateScorer,
    request: MatchRequest,
) !?SelectedMatch {
    if (prompt_tokens.token_hashes.items.len == 0) return null;

    const approx_scores = try allocator.alloc(u32, corpus.items.items.len);
    defer allocator.free(approx_scores);
    try scorer.score(corpus, &prompt_tokens.vector, approx_scores);

    var top: [max_top_candidates]ApproxScore = undefined;
    var top_len: usize = 0;
    for (approx_scores, 0..) |score, idx| {
        if (score == 0) continue;
        if (top_len < top.len) {
            top[top_len] = .{ .index = idx, .score = score };
            top_len += 1;
            continue;
        }
        var min_index: usize = 0;
        var min_score = top[0].score;
        for (top[0..top_len], 0..) |candidate, candidate_idx| {
            if (candidate.score < min_score) {
                min_index = candidate_idx;
                min_score = candidate.score;
            }
        }
        if (score > min_score) {
            top[min_index] = .{ .index = idx, .score = score };
        }
    }

    var best: ?SelectedMatch = null;
    var best_score: i32 = -1;
    for (top[0..top_len]) |candidate| {
        const example = corpus.items.items[candidate.index].example;
        const lexical = try scoreLexicalMatch(allocator, prompt, prompt_tokens, example.user, candidate.score);
        if (lexical == null) continue;
        const scored = lexical.?;
        switch (request) {
            .anchor => {
                if (!scored.exact and !(scored.prompt_cov_ppm >= 850 and scored.candidate_cov_ppm >= 700 and scored.overlap >= 2)) continue;
            },
            .retrieval => {
                if (!scored.exact and !(scored.overlap >= 2 and (scored.prompt_cov_ppm >= 500 or scored.bigram_overlap >= 1) and scored.candidate_cov_ppm >= 250)) continue;
            },
        }
        if (scored.score > best_score) {
            best_score = scored.score;
            best = .{ .example = example, .exact_score = scored.score };
        }
    }

    return best;
}

fn scoreLexicalMatch(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    prompt_tokens: *const TokenizedText,
    candidate: []const u8,
    approx_score: u32,
) !?LexicalScore {
    var candidate_tokens = try tokenizeText(allocator, candidate);
    defer candidate_tokens.deinit(allocator);

    if (candidate_tokens.token_hashes.items.len == 0) return null;
    if (hasConflictingVersionToken(prompt, candidate)) return null;

    var overlap: usize = 0;
    for (prompt_tokens.token_hashes.items) |hash| {
        if (containsHash(candidate_tokens.token_hashes.items, hash)) overlap += 1;
    }
    if (overlap == 0) return null;

    var bigram_overlap: usize = 0;
    for (prompt_tokens.bigram_hashes.items) |hash| {
        if (containsHash(candidate_tokens.bigram_hashes.items, hash)) bigram_overlap += 1;
    }

    const prompt_count = prompt_tokens.token_hashes.items.len;
    const candidate_count = candidate_tokens.token_hashes.items.len;
    const prompt_cov_ppm: u32 = @intCast(@divTrunc(overlap * 1000, prompt_count));
    const candidate_cov_ppm: u32 = @intCast(@divTrunc(overlap * 1000, candidate_count));
    const exact = std.ascii.eqlIgnoreCase(prompt, candidate);
    const intent_match = prompt_tokens.intent == .other or candidate_tokens.intent == .other or prompt_tokens.intent == candidate_tokens.intent;

    if (!exact) {
        if (prompt_count >= 2 and overlap < 2 and bigram_overlap == 0) return null;
        if (prompt_count >= 3 and prompt_cov_ppm < 450 and bigram_overlap == 0) return null;
        if (candidate_count >= 3 and candidate_cov_ppm < 250 and bigram_overlap == 0) return null;
    }

    var score: i32 = @intCast(@min(approx_score, 4000));
    score += @as(i32, @intCast(overlap * 140));
    score += @as(i32, @intCast(bigram_overlap * 260));
    score += @as(i32, @intCast(@divTrunc(prompt_cov_ppm, 3)));
    score += @as(i32, @intCast(@divTrunc(candidate_cov_ppm, 6)));
    if (exact) score += 10_000;
    if (intent_match) score += 40 else score -= 80;
    return .{
        .score = score,
        .overlap = overlap,
        .bigram_overlap = bigram_overlap,
        .prompt_cov_ppm = prompt_cov_ppm,
        .candidate_cov_ppm = candidate_cov_ppm,
        .exact = exact,
        .intent_match = intent_match,
    };
}

fn maybeGroundedContinuation(
    allocator: std.mem.Allocator,
    seed_bytes: []const u8,
    prompt: []const u8,
    example: DialogueExample,
    session: *const SessionState,
    options: ChatOptions,
) ![]const u8 {
    if (options.continue_bytes == 0 or !options.allow_generation) return example.assistant;
    const transcript = try renderSessionTranscript(allocator, session);
    defer allocator.free(transcript);
    return generateAnchoredResponse(allocator, seed_bytes, transcript, prompt, example.assistant, options);
}

fn buildHelpResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, and short math.");
}

fn buildFactStoredResponse(allocator: std.mem.Allocator, fact: FactCandidate) ![]const u8 {
    if (std.ascii.eqlIgnoreCase(fact.key, "name")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Hi {s}. I will remember your name for this session.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "location")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Noted. You live in {s}, and I will remember that for this session.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "lab")) {
        return std.fmt.allocPrint(allocator, "Noted. Your lab is {s}, and I will remember that for this session.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "role")) {
        return std.fmt.allocPrint(allocator, "Noted. Your role is {s}, and I will remember that for this session.", .{fact.value});
    }
    return std.fmt.allocPrint(allocator, "Noted. Your {s} is {s}, and I will remember that for this session.", .{ fact.key, fact.value });
}

fn buildFactHelpResponse(allocator: std.mem.Allocator, fact: FactCandidate) ![]const u8 {
    if (std.ascii.eqlIgnoreCase(fact.key, "name")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Hi {s}. I will remember your name for this session. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, and short math.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "location")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Noted. You live in {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, and short math.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "lab")) {
        return std.fmt.allocPrint(allocator, "Noted. Your lab is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, and short math.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "role")) {
        return std.fmt.allocPrint(allocator, "Noted. Your role is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, and short math.", .{fact.value});
    }
    return std.fmt.allocPrint(allocator, "Noted. Your {s} is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, and short math.", .{ fact.key, fact.value });
}

fn buildFactRecallResponse(allocator: std.mem.Allocator, fact: SessionFact) ![]const u8 {
    if (std.ascii.eqlIgnoreCase(fact.key, "name")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Your name is {s}.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "location")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "You live in {s}.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "lab")) {
        return std.fmt.allocPrint(allocator, "Your lab is {s}.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "role")) {
        return std.fmt.allocPrint(allocator, "Your role is {s}.", .{fact.value});
    }
    return std.fmt.allocPrint(allocator, "Your {s} is {s}.", .{ fact.key, fact.value });
}

fn buildFactRecallMiss(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    if (std.ascii.eqlIgnoreCase(key, "name")) {
        return allocator.dupe(u8, "I do not know your name yet. Tell me with 'my name is ...' or 'hi I am ...' and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "location")) {
        return allocator.dupe(u8, "I do not know where you live yet. Tell me with 'I live in ...' and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "lab")) {
        return allocator.dupe(u8, "I do not know your lab yet. Tell me with 'our lab is ...' or 'my lab is ...' and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "role")) {
        return allocator.dupe(u8, "I do not know your role yet. Tell me with 'my role is ...' or 'I work as ...' and I will remember it for this session.");
    }
    return std.fmt.allocPrint(allocator, "I do not know your {s} yet. Tell me and I will remember it for this session.", .{key});
}

fn buildFactCapabilityResponse(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    if (std.ascii.eqlIgnoreCase(key, "name")) {
        return allocator.dupe(u8, "Yes. Tell me your name and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "location")) {
        return allocator.dupe(u8, "Yes. Tell me where you live and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "lab")) {
        return allocator.dupe(u8, "Yes. Tell me your lab and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "role")) {
        return allocator.dupe(u8, "Yes. Tell me your role and I will remember it for this session.");
    }
    return std.fmt.allocPrint(allocator, "Yes. Tell me your {s} and I will remember it for this session.", .{key});
}

fn buildUncertaintyResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (isDomainPrompt(prompt)) {
        return allocator.dupe(u8, "I am not sure enough to answer that from the grounded SBAN v22 knowledge yet.");
    }
    return allocator.dupe(u8, "I am not sure. I only answer when I have grounded support or session facts, and I do not know that one yet.");
}

fn isDomainPrompt(prompt: []const u8) bool {
    const markers = [_][]const u8{
        "sban",
        "transformer",
        "bridge-adaptive",
        "architecture",
        "benchmark",
        "release",
        "demo",
        "session",
        "memory",
        "paper",
        "summary",
        "repo",
        "ci",
        "gpu",
        "opencl",
    };
    for (markers) |marker| {
        if (containsPhraseIgnoreCase(prompt, marker)) return true;
    }
    return false;
}

fn readWholeFileFriendly(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, path: []const u8, label: []const u8) ?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 << 20)) catch |err| {
        switch (err) {
            error.FileNotFound => writer.print("error=missing_file label={s} path={s}\n", .{ label, path }) catch {},
            else => writer.print("error=file_read_failed label={s} path={s} detail={s}\n", .{ label, path, @errorName(err) }) catch {},
        }
        writer.flush() catch {};
        return null;
    };
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
        } else if (std.mem.eql(u8, key, "backend")) {
            if (std.mem.eql(u8, value, "auto")) options.backend = .auto else if (std.mem.eql(u8, value, "cpu")) options.backend = .cpu else if (std.mem.eql(u8, value, "gpu")) options.backend = .gpu else {
                try writer.print("invalid_backend={s}\n", .{value});
                return error.InvalidOverride;
            }
        } else if (std.mem.eql(u8, key, "continue_bytes")) {
            options.continue_bytes = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "allow_generation")) {
            options.allow_generation = try parseBool(value);
        } else {
            cfg.applyOverride(&options.net_config, key, value) catch |err| {
                try writer.print("invalid_override={s} err={s}\n", .{ arg, @errorName(err) });
                return error.InvalidOverride;
            };
        }
    }
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes") or std.ascii.eqlIgnoreCase(value, "on")) return true;
    if (std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "no") or std.ascii.eqlIgnoreCase(value, "off")) return false;
    return error.InvalidBooleanOverride;
}

fn prepareCorpus(allocator: std.mem.Allocator, examples: []const DialogueExample) !PreparedCorpus {
    var corpus: PreparedCorpus = .{};
    for (examples) |example| {
        var tokenized = try tokenizeText(allocator, example.user);
        defer tokenized.deinit(allocator);
        try corpus.items.append(allocator, .{
            .example = example,
            .vector = tokenized.vector,
        });
    }
    return corpus;
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

fn tokenizeText(allocator: std.mem.Allocator, text: []const u8) !TokenizedText {
    var tokenized: TokenizedText = .{
        .normalized = try allocator.alloc(u8, text.len),
        .intent = classifyIntent(text),
    };

    for (text, 0..) |byte, idx| {
        tokenized.normalized[idx] = if (isWordChar(byte)) std.ascii.toLower(byte) else ' ';
    }

    var prev_hash: ?u64 = null;
    var idx: usize = 0;
    while (idx < tokenized.normalized.len) {
        while (idx < tokenized.normalized.len and tokenized.normalized[idx] == ' ') : (idx += 1) {}
        const start = idx;
        while (idx < tokenized.normalized.len and tokenized.normalized[idx] != ' ') : (idx += 1) {}
        if (idx <= start) continue;
        const token = tokenized.normalized[start..idx];
        if (token.len <= 1 and !std.ascii.isDigit(token[0])) continue;
        if (isStopword(token)) continue;
        var token_buffer: [64]u8 = undefined;
        const canonical = canonicalToken(token, &token_buffer);
        const hash = std.hash.Wyhash.hash(0, canonical);
        try appendUniqueHash(allocator, &tokenized.token_hashes, hash);
        addFeature(&tokenized.vector, hash, @intCast(@min(canonical.len + 1, 12)));
        if (!std.mem.eql(u8, canonical, token)) {
            const raw_hash = std.hash.Wyhash.hash(0, token);
            try appendUniqueHash(allocator, &tokenized.token_hashes, raw_hash);
            addFeature(&tokenized.vector, raw_hash, 2);
        }
        if (prev_hash) |prev| {
            const bigram_hash = prev ^ (hash *% 0x9e3779b97f4a7c15);
            try appendUniqueHash(allocator, &tokenized.bigram_hashes, bigram_hash);
            addFeature(&tokenized.vector, bigram_hash ^ 0x517cc1b727220a95, 4);
        }
        prev_hash = hash;
    }
    return tokenized;
}

fn classifyIntent(text: []const u8) IntentKind {
    const trimmed = trimLine(text);
    if (startsWithWordIgnoreCase(trimmed, "what")) return .what;
    if (startsWithWordIgnoreCase(trimmed, "how")) return .how;
    if (startsWithWordIgnoreCase(trimmed, "why")) return .why;
    if (startsWithWordIgnoreCase(trimmed, "explain")) return .explain;
    if (startsWithWordIgnoreCase(trimmed, "compare")) return .compare;
    if (startsWithWordIgnoreCase(trimmed, "should")) return .should;
    if (startsWithWordIgnoreCase(trimmed, "can")) return .can;
    if (startsWithWordIgnoreCase(trimmed, "where")) return .where;
    return .other;
}

fn addFeature(vector: *[feature_dim]u16, hash: u64, weight: u16) void {
    const idx: usize = @intCast(hash % feature_dim);
    const current = vector[idx];
    vector[idx] = if (current > std.math.maxInt(u16) - weight) std.math.maxInt(u16) else current + weight;
}

fn appendUniqueHash(allocator: std.mem.Allocator, list: *std.ArrayList(u64), hash: u64) !void {
    if (containsHash(list.items, hash)) return;
    try list.append(allocator, hash);
}

fn containsHash(hashes: []const u64, needle: u64) bool {
    for (hashes) |hash| {
        if (hash == needle) return true;
    }
    return false;
}

fn hasConflictingVersionToken(prompt: []const u8, candidate: []const u8) bool {
    const prompt_version = findVersionToken(prompt) orelse return false;
    const candidate_version = findVersionToken(candidate) orelse return false;
    return !std.ascii.eqlIgnoreCase(prompt_version, candidate_version);
}

fn findVersionToken(text: []const u8) ?[]const u8 {
    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        if ((text[idx] == 'v' or text[idx] == 'V') and idx + 1 < text.len and std.ascii.isDigit(text[idx + 1])) {
            if (idx > 0 and isWordChar(text[idx - 1])) continue;
            var end = idx + 2;
            while (end < text.len and std.ascii.isDigit(text[end])) : (end += 1) {}
            return text[idx..end];
        }
    }
    return null;
}

fn isStopword(token: []const u8) bool {
    const stopwords = [_][]const u8{
        "a", "an", "and", "are", "be", "can", "do", "does", "for", "from", "how", "i", "im", "in", "is", "it", "me", "my",
        "of", "on", "or", "our", "please", "tell", "that", "the", "this", "to", "us", "was", "what", "when", "where", "who",
        "why", "with", "would", "your",
    };
    for (stopwords) |stopword| {
        if (std.mem.eql(u8, token, stopword)) return true;
    }
    return false;
}

fn canonicalToken(token: []const u8, scratch: *[64]u8) []const u8 {
    if (std.mem.eql(u8, token, "different") or
        std.mem.eql(u8, token, "difference") or
        std.mem.eql(u8, token, "changed") or
        std.mem.eql(u8, token, "changes") or
        std.mem.eql(u8, token, "improved") or
        std.mem.eql(u8, token, "improve") or
        std.mem.eql(u8, token, "upgraded") or
        std.mem.eql(u8, token, "upgrade"))
    {
        return "change";
    }
    if (std.mem.eql(u8, token, "launch") or
        std.mem.eql(u8, token, "launching") or
        std.mem.eql(u8, token, "start") or
        std.mem.eql(u8, token, "starting") or
        std.mem.eql(u8, token, "open") or
        std.mem.eql(u8, token, "run") or
        std.mem.eql(u8, token, "running"))
    {
        return "launch";
    }
    if (std.mem.eql(u8, token, "supports") or
        std.mem.eql(u8, token, "supported") or
        std.mem.eql(u8, token, "supporting"))
    {
        return "support";
    }
    if (std.mem.eql(u8, token, "cuda") or std.mem.eql(u8, token, "opencl")) {
        return "gpu";
    }
    if (token.len > 4 and token.len <= scratch.len and std.mem.endsWith(u8, token, "ies")) {
        @memcpy(scratch[0 .. token.len - 3], token[0 .. token.len - 3]);
        scratch[token.len - 3] = 'y';
        return scratch[0 .. token.len - 2];
    }
    if (token.len > 3 and std.mem.endsWith(u8, token, "s") and !std.mem.endsWith(u8, token, "ss")) {
        return token[0 .. token.len - 1];
    }
    return token;
}

fn startsWithWordIgnoreCase(text: []const u8, word: []const u8) bool {
    if (text.len < word.len) return false;
    if (!std.ascii.eqlIgnoreCase(text[0..word.len], word)) return false;
    return text.len == word.len or !isWordChar(text[word.len]);
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

fn containsPhraseIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;
    var idx: usize = 0;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return true;
    }
    return false;
}

fn indexOfPhraseIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var idx: usize = 0;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return idx;
    }
    return null;
}

fn sanitizeTurnText(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var last_space = true;
    for (text) |byte| {
        const mapped: u8 = switch (byte) {
            '\r', '\n', '\t' => ' ',
            else => byte,
        };
        if (std.ascii.isWhitespace(mapped)) {
            if (!last_space) {
                try out.append(allocator, ' ');
                last_space = true;
            }
        } else {
            try out.append(allocator, mapped);
            last_space = false;
        }
    }
    return allocator.dupe(u8, trimLine(out.items));
}

fn escapeForDisplay(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (text) |byte| {
        switch (byte) {
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => {},
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, byte),
        }
    }
    return allocator.dupe(u8, out.items);
}

fn titleCaseCopy(allocator: std.mem.Allocator, raw_text: []const u8) ![]u8 {
    var copy = try allocator.dupe(u8, trimInlineValue(raw_text));
    var capitalize = true;
    for (copy, 0..) |byte, idx| {
        if (std.ascii.isAlphabetic(byte)) {
            copy[idx] = if (capitalize) std.ascii.toUpper(byte) else std.ascii.toLower(byte);
            capitalize = false;
        } else {
            capitalize = byte == ' ' or byte == '-';
        }
    }
    return copy;
}

fn normalizeFactKey(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    const sanitized = try sanitizeTurnText(allocator, key);
    defer allocator.free(sanitized);
    const copy = try allocator.dupe(u8, trimInlineValue(sanitized));
    for (copy) |*byte| {
        byte.* = std.ascii.toLower(byte.*);
    }
    if (std.mem.eql(u8, copy, "favorite colour")) {
        allocator.free(copy);
        return allocator.dupe(u8, "favorite color");
    }
    if (std.mem.eql(u8, copy, "colour")) {
        allocator.free(copy);
        return allocator.dupe(u8, "color");
    }
    if (std.mem.eql(u8, copy, "city") or std.mem.eql(u8, copy, "home city") or std.mem.eql(u8, copy, "where i live") or std.mem.eql(u8, copy, "where i am based")) {
        allocator.free(copy);
        return allocator.dupe(u8, "location");
    }
    if (std.mem.eql(u8, copy, "lab name") or std.mem.eql(u8, copy, "research lab")) {
        allocator.free(copy);
        return allocator.dupe(u8, "lab");
    }
    if (std.mem.eql(u8, copy, "job") or std.mem.eql(u8, copy, "title")) {
        allocator.free(copy);
        return allocator.dupe(u8, "role");
    }
    return copy;
}

fn isHelpPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "help") or
        containsPhraseIgnoreCase(prompt, "what can you do") or
        containsPhraseIgnoreCase(prompt, "what can i ask") or
        containsPhraseIgnoreCase(prompt, "i need help");
}

fn extractFactCandidate(allocator: std.mem.Allocator, prompt: []const u8) !?FactCandidate {
    if (extractNameCandidate(prompt)) |name| {
        return .{ .key = try allocator.dupe(u8, "name"), .value = try sanitizeTurnText(allocator, name) };
    }

    if (extractFixedFactValue(prompt, "i live in ")) |value| {
        return .{ .key = try allocator.dupe(u8, "location"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i am based in ")) |value| {
        return .{ .key = try allocator.dupe(u8, "location"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "our lab is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "lab"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "my lab is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "lab"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "my role is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "role"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i work as ")) |value| {
        return .{ .key = try allocator.dupe(u8, "role"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i am a ")) |value| {
        return .{ .key = try allocator.dupe(u8, "role"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i am an ")) |value| {
        return .{ .key = try allocator.dupe(u8, "role"), .value = try sanitizeTurnText(allocator, value) };
    }

    if (indexOfPhraseIgnoreCase(prompt, "my ")) |my_idx| {
        const separators = [_][]const u8{ " is ", " are " };
        for (separators) |separator| {
            if (indexOfPhraseIgnoreCase(prompt[my_idx + 3 ..], separator)) |relative_sep| {
                const sep_idx = my_idx + 3 + relative_sep;
                const key = trimInlineValue(prompt[my_idx + 3 .. sep_idx]);
                const value = trimInlineValue(takeValueUntilBoundary(prompt[sep_idx + separator.len ..]));
                if (key.len > 0 and value.len > 0) {
                    return .{ .key = try normalizeFactKey(allocator, key), .value = try sanitizeTurnText(allocator, value) };
                }
            }
        }
    }

    if (indexOfPhraseIgnoreCase(prompt, "i prefer ")) |idx| {
        const value = trimInlineValue(takeValueUntilBoundary(prompt[idx + "i prefer ".len ..]));
        if (value.len > 0) return .{ .key = try allocator.dupe(u8, "preference"), .value = try sanitizeTurnText(allocator, value) };
    }

    if (indexOfPhraseIgnoreCase(prompt, "i like ")) |idx| {
        const value = trimInlineValue(takeValueUntilBoundary(prompt[idx + "i like ".len ..]));
        if (value.len > 0) return .{ .key = try allocator.dupe(u8, "likes"), .value = try sanitizeTurnText(allocator, value) };
    }

    return null;
}

fn extractFactQuery(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (containsPhraseIgnoreCase(prompt, "if i tell you") or containsPhraseIgnoreCase(prompt, "if i say")) return null;

    if (containsPhraseIgnoreCase(prompt, "where do i live") or
        containsPhraseIgnoreCase(prompt, "what city do i live in") or
        containsPhraseIgnoreCase(prompt, "where am i based"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "location"));
    }
    if (containsPhraseIgnoreCase(prompt, "what is our lab") or
        containsPhraseIgnoreCase(prompt, "what's our lab") or
        containsPhraseIgnoreCase(prompt, "what is my lab") or
        containsPhraseIgnoreCase(prompt, "what's my lab"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "lab"));
    }
    if (containsPhraseIgnoreCase(prompt, "what is my role") or
        containsPhraseIgnoreCase(prompt, "what's my role") or
        containsPhraseIgnoreCase(prompt, "what role did i tell you"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "role"));
    }

    const markers = [_][]const u8{
        "what is my ",
        "what's my ",
        "can you recall my ",
        "do you remember my ",
        "remember my ",
        "what are my ",
    };
    for (markers) |marker| {
        if (indexOfPhraseIgnoreCase(prompt, marker)) |idx| {
            const key = trimInlineValue(takeValueUntilBoundary(prompt[idx + marker.len ..]));
            if (key.len > 0) return @as(?[]u8, try normalizeFactKey(allocator, key));
        }
    }

    if (containsPhraseIgnoreCase(prompt, "what do i prefer")) return @as(?[]u8, try allocator.dupe(u8, "preference"));
    if (containsPhraseIgnoreCase(prompt, "what do i like")) return @as(?[]u8, try allocator.dupe(u8, "likes"));
    return null;
}

fn extractMemoryCapabilityQuery(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (!(containsPhraseIgnoreCase(prompt, "if i tell you") or containsPhraseIgnoreCase(prompt, "if i say"))) return null;

    const markers = [_][]const u8{
        "can you remember my ",
        "will you remember my ",
        "can you remember our ",
        "will you remember our ",
    };
    for (markers) |marker| {
        if (indexOfPhraseIgnoreCase(prompt, marker)) |idx| {
            const tail = prompt[idx + marker.len ..];
            const end = if (indexOfPhraseIgnoreCase(tail, " if i tell you")) |end_idx| end_idx else if (indexOfPhraseIgnoreCase(tail, " if i say")) |end_idx| end_idx else tail.len;
            const key = trimInlineValue(tail[0..end]);
            if (key.len > 0) return @as(?[]u8, try normalizeFactKey(allocator, key));
        }
    }
    return null;
}

fn extractNameCandidate(prompt: []const u8) ?[]const u8 {
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
        "i am ",
    };
    for (markers) |marker| {
        if (indexOfPhraseIgnoreCase(prompt, marker)) |idx| {
            const tail = prompt[idx + marker.len ..];
            if (takeLeadingNameCandidate(tail)) |name| return name;
        }
    }
    return null;
}

fn takeLeadingNameCandidate(input: []const u8) ?[]const u8 {
    const trimmed = trimLine(input);
    if (trimmed.len == 0) return null;

    var idx: usize = 0;
    var end: usize = 0;
    var token_count: usize = 0;
    while (idx < trimmed.len) {
        while (idx < trimmed.len and std.ascii.isWhitespace(trimmed[idx])) : (idx += 1) {}
        const token_start = idx;
        while (idx < trimmed.len and (std.ascii.isAlphabetic(trimmed[idx]) or trimmed[idx] == '\'' or trimmed[idx] == '-')) : (idx += 1) {}
        if (idx <= token_start) break;
        const token = trimmed[token_start..idx];
        if (std.ascii.eqlIgnoreCase(token, "and") or std.ascii.eqlIgnoreCase(token, "but")) break;
        token_count += 1;
        end = idx;
        if (token_count >= 3) break;
    }
    if (end == 0) return null;
    const candidate = trimInlineValue(trimmed[0..end]);
    if (candidate.len == 0) return null;
    var token_iter = std.mem.splitScalar(u8, candidate, ' ');
    const first = token_iter.next() orelse return null;
    if (std.ascii.eqlIgnoreCase(first, "a") or std.ascii.eqlIgnoreCase(first, "an") or std.ascii.eqlIgnoreCase(first, "the")) return null;
    return candidate;
}

fn takeValueUntilBoundary(input: []const u8) []const u8 {
    var end = input.len;
    const boundaries = [_][]const u8{ " and ", " but ", " because ", " if ", " please ", " thanks " };
    for (boundaries) |boundary| {
        if (indexOfPhraseIgnoreCase(input, boundary)) |idx| {
            end = @min(end, idx);
        }
    }
    for (input, 0..) |byte, idx| {
        if (byte == '\n' or byte == '\r' or byte == '?' or byte == '!' or byte == ';' or byte == ',') {
            end = @min(end, idx);
            break;
        }
    }
    return trimInlineValue(input[0..end]);
}

fn extractFixedFactValue(prompt: []const u8, marker: []const u8) ?[]const u8 {
    if (indexOfPhraseIgnoreCase(prompt, marker)) |idx| {
        const value = trimInlineValue(takeValueUntilBoundary(prompt[idx + marker.len ..]));
        if (value.len > 0) return value;
    }
    return null;
}

fn renderSessionTranscript(allocator: std.mem.Allocator, session: *const SessionState) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (session.turns.items) |turn| {
        try out.print(allocator, "User: {s}\nAssistant: {s}\n\n", .{ turn.user, turn.assistant });
    }
    return allocator.dupe(u8, out.items);
}

fn loadSessionState(allocator: std.mem.Allocator, io: std.Io, path: ?[]const u8) !SessionState {
    const actual_path = path orelse return .{};
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, actual_path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer allocator.free(bytes);
    if (bytes.len == 0) return .{};

    if (std.mem.startsWith(u8, bytes, session_magic) or std.mem.startsWith(u8, bytes, legacy_session_magic)) {
        return parseSessionStateV21(allocator, bytes);
    }

    return parseLegacyTranscriptSession(allocator, bytes);
}

fn parseLegacyTranscriptSession(allocator: std.mem.Allocator, bytes: []const u8) !SessionState {
    var session: SessionState = .{};
    var current_user: ?[]const u8 = null;
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "User:")) {
            current_user = trimLine(line[5..]);
        } else if (std.mem.startsWith(u8, line, "Assistant:")) {
            if (current_user) |user| {
                try session.appendTurn(allocator, user, trimLine(line[10..]));
                current_user = null;
            }
        }
    }
    return session;
}

fn parseSessionStateV21(allocator: std.mem.Allocator, bytes: []const u8) !SessionState {
    var session: SessionState = .{};
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    _ = iter.next();
    while (iter.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const kind = fields.next() orelse continue;
        if (std.mem.eql(u8, kind, "turn")) {
            const user_b64 = fields.next() orelse continue;
            const assistant_b64 = fields.next() orelse continue;
            const user = try decodeField(allocator, user_b64);
            defer allocator.free(user);
            const assistant = try decodeField(allocator, assistant_b64);
            defer allocator.free(assistant);
            try session.appendTurn(allocator, user, assistant);
        } else if (std.mem.eql(u8, kind, "fact")) {
            const key_b64 = fields.next() orelse continue;
            const value_b64 = fields.next() orelse continue;
            const key = try decodeField(allocator, key_b64);
            defer allocator.free(key);
            const value = try decodeField(allocator, value_b64);
            defer allocator.free(value);
            try session.rememberFact(allocator, key, value);
        }
    }
    return session;
}

fn saveSessionState(io: std.Io, path: ?[]const u8, session: *const SessionState) !void {
    const actual_path = path orelse return;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.heap.page_allocator);
    try out.appendSlice(std.heap.page_allocator, session_magic);
    try out.append(std.heap.page_allocator, '\n');
    for (session.facts.items) |fact| {
        const key = try encodeField(std.heap.page_allocator, fact.key);
        const value = try encodeField(std.heap.page_allocator, fact.value);
        try out.print(std.heap.page_allocator, "fact\t{s}\t{s}\n", .{ key, value });
    }
    for (session.turns.items) |turn| {
        const user = try encodeField(std.heap.page_allocator, turn.user);
        const assistant = try encodeField(std.heap.page_allocator, turn.assistant);
        try out.print(std.heap.page_allocator, "turn\t{s}\t{s}\n", .{ user, assistant });
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = actual_path, .data = out.items });
}

fn encodeField(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const size = std.base64.url_safe_no_pad.Encoder.calcSize(value.len);
    const dest = try allocator.alloc(u8, size);
    _ = std.base64.url_safe_no_pad.Encoder.encode(dest, value);
    return dest;
}

fn decodeField(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const decoded_len = try std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(encoded);
    const decoded = try allocator.alloc(u8, decoded_len);
    try std.base64.url_safe_no_pad.Decoder.decode(decoded, encoded);
    return decoded;
}

fn initGpuScorer(allocator: std.mem.Allocator, corpus: *const PreparedCorpus) !OpenClScorer {
    if (corpus.items.items.len == 0) return OpenClUnavailable.NoGpuDevice;
    const flat = try allocator.alloc(u16, corpus.items.items.len * feature_dim);
    defer allocator.free(flat);
    for (corpus.items.items, 0..) |item, idx| {
        @memcpy(flat[idx * feature_dim .. (idx + 1) * feature_dim], item.vector[0..]);
    }
    return OpenClScorer.init(allocator, flat, corpus.items.items.len);
}

fn dotProduct(lhs: *const [feature_dim]u16, rhs: *const [feature_dim]u16) u32 {
    var total: u32 = 0;
    for (lhs, 0..) |left, idx| {
        total +%= @as(u32, left) * @as(u32, rhs[idx]);
    }
    return total;
}

fn openOpenClLibrary() !DynamicLibrary {
    if (builtin.os.tag == .windows) {
        return DynamicLibrary.open("OpenCL.dll");
    }
    return DynamicLibrary.open("libOpenCL.so.1") catch DynamicLibrary.open("libOpenCL.so");
}

fn loadOpenClApi(lib: *DynamicLibrary) !OpenClApi {
    return .{
        .get_platform_ids = lib.lookup(ClGetPlatformIDsFn, "clGetPlatformIDs") orelse return OpenClUnavailable.NoOpenClLoader,
        .get_platform_info = lib.lookup(ClGetPlatformInfoFn, "clGetPlatformInfo") orelse return OpenClUnavailable.NoOpenClLoader,
        .get_device_ids = lib.lookup(ClGetDeviceIDsFn, "clGetDeviceIDs") orelse return OpenClUnavailable.NoOpenClLoader,
        .get_device_info = lib.lookup(ClGetDeviceInfoFn, "clGetDeviceInfo") orelse return OpenClUnavailable.NoOpenClLoader,
        .create_context = lib.lookup(ClCreateContextFn, "clCreateContext") orelse return OpenClUnavailable.NoOpenClLoader,
        .create_command_queue = lib.lookup(ClCreateCommandQueueFn, "clCreateCommandQueue") orelse return OpenClUnavailable.NoOpenClLoader,
        .create_program_with_source = lib.lookup(ClCreateProgramWithSourceFn, "clCreateProgramWithSource") orelse return OpenClUnavailable.NoOpenClLoader,
        .build_program = lib.lookup(ClBuildProgramFn, "clBuildProgram") orelse return OpenClUnavailable.NoOpenClLoader,
        .get_program_build_info = lib.lookup(ClGetProgramBuildInfoFn, "clGetProgramBuildInfo") orelse return OpenClUnavailable.NoOpenClLoader,
        .create_kernel = lib.lookup(ClCreateKernelFn, "clCreateKernel") orelse return OpenClUnavailable.NoOpenClLoader,
        .create_buffer = lib.lookup(ClCreateBufferFn, "clCreateBuffer") orelse return OpenClUnavailable.NoOpenClLoader,
        .set_kernel_arg = lib.lookup(ClSetKernelArgFn, "clSetKernelArg") orelse return OpenClUnavailable.NoOpenClLoader,
        .enqueue_write_buffer = lib.lookup(ClEnqueueWriteBufferFn, "clEnqueueWriteBuffer") orelse return OpenClUnavailable.NoOpenClLoader,
        .enqueue_nd_range_kernel = lib.lookup(ClEnqueueNDRangeKernelFn, "clEnqueueNDRangeKernel") orelse return OpenClUnavailable.NoOpenClLoader,
        .enqueue_read_buffer = lib.lookup(ClEnqueueReadBufferFn, "clEnqueueReadBuffer") orelse return OpenClUnavailable.NoOpenClLoader,
        .finish = lib.lookup(ClFinishFn, "clFinish") orelse return OpenClUnavailable.NoOpenClLoader,
        .release_mem_object = lib.lookup(ClReleaseMemObjectFn, "clReleaseMemObject") orelse return OpenClUnavailable.NoOpenClLoader,
        .release_kernel = lib.lookup(ClReleaseKernelFn, "clReleaseKernel") orelse return OpenClUnavailable.NoOpenClLoader,
        .release_program = lib.lookup(ClReleaseProgramFn, "clReleaseProgram") orelse return OpenClUnavailable.NoOpenClLoader,
        .release_command_queue = lib.lookup(ClReleaseCommandQueueFn, "clReleaseCommandQueue") orelse return OpenClUnavailable.NoOpenClLoader,
        .release_context = lib.lookup(ClReleaseContextFn, "clReleaseContext") orelse return OpenClUnavailable.NoOpenClLoader,
    };
}

fn chooseGpuPlatform(api: OpenClApi) !cl_platform_id {
    var count: cl_uint = 0;
    try checkCl(api.get_platform_ids(0, null, &count));
    if (count == 0) return OpenClUnavailable.NoGpuDevice;
    var platforms: [8]cl_platform_id = [_]cl_platform_id{null} ** 8;
    const bounded = @min(count, platforms.len);
    try checkCl(api.get_platform_ids(@intCast(bounded), platforms[0..].ptr, &count));
    for (platforms[0..bounded]) |platform| {
        var device_count: cl_uint = 0;
        const err = api.get_device_ids(platform, cl_device_type_gpu, 0, null, &device_count);
        if (err == cl_success and device_count > 0) return platform;
    }
    return OpenClUnavailable.NoGpuDevice;
}

fn chooseGpuDevice(api: OpenClApi, platform: cl_platform_id) !cl_device_id {
    var count: cl_uint = 0;
    try checkCl(api.get_device_ids(platform, cl_device_type_gpu, 0, null, &count));
    if (count == 0) return OpenClUnavailable.NoGpuDevice;
    var devices: [8]cl_device_id = [_]cl_device_id{null} ** 8;
    const bounded = @min(count, devices.len);
    try checkCl(api.get_device_ids(platform, cl_device_type_gpu, @intCast(bounded), devices[0..].ptr, &count));
    return devices[0];
}

fn queryInfoString(
    allocator: std.mem.Allocator,
    func: anytype,
    object: anytype,
    param_name: anytype,
) ![]u8 {
    var size: usize = 0;
    try checkCl(func(object, param_name, 0, null, &size));
    if (size == 0) return allocator.alloc(u8, 0);
    const buffer = try allocator.alloc(u8, size);
    try checkCl(func(object, param_name, size, buffer.ptr, &size));
    if (size == 0) return buffer;
    return allocator.dupe(u8, std.mem.trim(u8, buffer[0..size], "\x00"));
}

fn queryProgramBuildLog(allocator: std.mem.Allocator, api: OpenClApi, program: cl_program, device: cl_device_id) ![]u8 {
    var size: usize = 0;
    try checkCl(api.get_program_build_info(program, device, cl_program_build_log, 0, null, &size));
    if (size == 0) return allocator.alloc(u8, 0);
    const buffer = try allocator.alloc(u8, size);
    try checkCl(api.get_program_build_info(program, device, cl_program_build_log, size, buffer.ptr, &size));
    if (size == 0) return buffer;
    return allocator.dupe(u8, std.mem.trim(u8, buffer[0..size], "\x00"));
}

fn checkCl(errcode: cl_int) !void {
    if (errcode == cl_success) return;
    if (errcode == cl_device_not_found) return OpenClUnavailable.NoGpuDevice;
    return OpenClUnavailable.OpenClFailure;
}

const kernel_source: [:0]const u8 =
    \\__kernel void score_examples(
    \\    __global const ushort* prompt,
    \\    __global const ushort* examples,
    \\    __global uint* out,
    \\    const uint feature_dim)
    \\{
    \\    const uint gid = get_global_id(0);
    \\    const uint base = gid * feature_dim;
    \\    uint sum = 0;
    \\    for (uint i = 0; i < feature_dim; i += 1) {
    \\        sum += (uint)prompt[i] * (uint)examples[base + i];
    \\    }
    \\    out[gid] = sum;
    \\}
;

fn generateFreeResponse(
    allocator: std.mem.Allocator,
    seed_bytes: []const u8,
    transcript_bytes: []const u8,
    prompt: []const u8,
    options: ChatOptions,
) ![]const u8 {
    var net = try netmod.Network.init(allocator, options.net_config);
    defer net.deinit();
    try trainBytes(&net, seed_bytes);
    try trainBytes(&net, transcript_bytes);
    const prompt_block = try std.fmt.allocPrint(allocator, "User: {s}\nAssistant:", .{prompt});
    defer allocator.free(prompt_block);
    try trainBytes(&net, prompt_block);
    var generated = std.ArrayList(u8).empty;
    defer generated.deinit(allocator);
    var current: u8 = if (prompt_block.len > 0) prompt_block[prompt_block.len - 1] else ':';
    var idx: usize = 0;
    while (idx < options.max_bytes) : (idx += 1) {
        const prediction = try net.stepGenerated(current);
        const next_byte = prediction.token;
        if (next_byte == 0) break;
        try generated.append(allocator, next_byte);
        current = next_byte;
        if (generated.items.len >= 2 and generated.items[generated.items.len - 1] == '\n' and generated.items[generated.items.len - 2] == '\n') break;
    }
    return allocator.dupe(u8, sanitizeGeneratedResponse(generated.items));
}

fn generateAnchoredResponse(
    allocator: std.mem.Allocator,
    seed_bytes: []const u8,
    transcript_bytes: []const u8,
    prompt: []const u8,
    anchor_assistant: []const u8,
    options: ChatOptions,
) ![]const u8 {
    var net = try netmod.Network.init(allocator, options.net_config);
    defer net.deinit();
    try trainBytes(&net, seed_bytes);
    try trainBytes(&net, transcript_bytes);
    const prompt_block = try std.fmt.allocPrint(allocator, "User: {s}\nAssistant:", .{prompt});
    defer allocator.free(prompt_block);
    try trainBytes(&net, prompt_block);
    try trainBytes(&net, anchor_assistant);

    var response = std.ArrayList(u8).empty;
    defer response.deinit(allocator);
    try response.appendSlice(allocator, anchor_assistant);
    var current: u8 = if (anchor_assistant.len > 0) anchor_assistant[anchor_assistant.len - 1] else '.';
    var idx: usize = 0;
    while (idx < options.continue_bytes) : (idx += 1) {
        const prediction = try net.stepGenerated(current);
        const next_byte = prediction.token;
        if (next_byte == 0) break;
        try response.append(allocator, next_byte);
        current = next_byte;
        if (response.items.len >= 2 and response.items[response.items.len - 1] == '\n' and response.items[response.items.len - 2] == '\n') break;
    }
    return allocator.dupe(u8, sanitizeGeneratedResponse(response.items));
}

fn sanitizeGeneratedResponse(bytes: []const u8) []const u8 {
    var trimmed = std.mem.trim(u8, bytes, "\r\n \t");
    if (std.mem.indexOf(u8, trimmed, "\nUser:")) |idx| trimmed = trimLine(trimmed[0..idx]);
    if (std.mem.indexOf(u8, trimmed, "\nAssistant:")) |idx| trimmed = trimLine(trimmed[0..idx]);
    return trimmed;
}

fn trainBytes(net: *netmod.Network, bytes: []const u8) !void {
    if (bytes.len < 2) return;
    var idx: usize = 0;
    while (idx + 1 < bytes.len) : (idx += 1) {
        _ = try net.step(bytes[idx], bytes[idx + 1]);
    }
}

const MathTokenTag = enum { number, plus, minus, star, slash, lparen, rparen };

const MathToken = struct {
    tag: MathTokenTag,
    value: f64 = 0.0,
};

fn solveMath(allocator: std.mem.Allocator, prompt: []const u8) !?MathOutcome {
    const expr = extractMathExpression(allocator, prompt) orelse return null;
    defer allocator.free(expr);
    var parser = MathParser.init(expr);
    const value = parser.parseExpression() catch |err| switch (err) {
        error.DivideByZero => {
            return .{
                .response = try std.fmt.allocPrint(allocator, "Division by zero is undefined, so I cannot evaluate {s}.", .{expr}),
                .explicit_error = true,
            };
        },
        else => return null,
    };
    if (!parser.atEnd()) return null;
    const formatted = try formatNumber(allocator, value);
    defer allocator.free(formatted);
    return .{
        .response = try std.fmt.allocPrint(allocator, "{s} = {s}.", .{ expr, formatted }),
    };
}

fn extractMathExpression(allocator: std.mem.Allocator, prompt: []const u8) ?[]u8 {
    const prefixes = [_][]const u8{ "what is ", "calculate ", "compute " };
    for (prefixes) |prefix| {
        if (indexOfPhraseIgnoreCase(prompt, prefix)) |idx| {
            const candidate = trimInlineValue(prompt[idx + prefix.len ..]);
            return normalizeMathExpression(allocator, candidate) catch null;
        }
    }
    return normalizeMathExpression(allocator, trimInlineValue(prompt)) catch null;
}

fn normalizeMathExpression(allocator: std.mem.Allocator, text: []const u8) !?[]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var idx: usize = 0;
    while (idx < text.len) {
        if (std.ascii.isWhitespace(text[idx])) {
            if (out.items.len > 0 and out.items[out.items.len - 1] != ' ') try out.append(allocator, ' ');
            idx += 1;
            continue;
        }

        if (std.mem.startsWith(u8, text[idx..], "plus")) {
            try out.appendSlice(allocator, "+ ");
            idx += 4;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "minus")) {
            try out.appendSlice(allocator, "- ");
            idx += 5;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "times")) {
            try out.appendSlice(allocator, "* ");
            idx += 5;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "divided by")) {
            try out.appendSlice(allocator, "/ ");
            idx += "divided by".len;
            continue;
        }

        const ch = text[idx];
        if (std.ascii.isDigit(ch) or ch == '.' or ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '(' or ch == ')') {
            try out.append(allocator, ch);
            idx += 1;
            continue;
        }

        return null;
    }

    const normalized = try allocator.dupe(u8, trimLine(out.items));
    if (normalized.len == 0) return null;
    var has_digit = false;
    var has_op = false;
    for (normalized) |ch| {
        if (std.ascii.isDigit(ch)) has_digit = true;
        if (ch == '+' or ch == '-' or ch == '*' or ch == '/') has_op = true;
    }
    if (!has_digit or !has_op) return null;
    return normalized;
}

const MathParser = struct {
    input: []const u8,
    index: usize = 0,

    const ParseError = error{
        UnexpectedEnd,
        ExpectedRParen,
        DivideByZero,
        ExpectedNumber,
    } || std.fmt.ParseFloatError;

    fn init(input: []const u8) MathParser {
        return .{ .input = input };
    }

    fn atEnd(self: *MathParser) bool {
        self.skipWhitespace();
        return self.index >= self.input.len;
    }

    fn skipWhitespace(self: *MathParser) void {
        while (self.index < self.input.len and std.ascii.isWhitespace(self.input[self.index])) : (self.index += 1) {}
    }

    fn parseExpression(self: *MathParser) ParseError!f64 {
        var value = try self.parseTerm();
        while (true) {
            self.skipWhitespace();
            if (self.index >= self.input.len) break;
            const op = self.input[self.index];
            if (op != '+' and op != '-') break;
            self.index += 1;
            const rhs = try self.parseTerm();
            value = if (op == '+') value + rhs else value - rhs;
        }
        return value;
    }

    fn parseTerm(self: *MathParser) ParseError!f64 {
        var value = try self.parseFactor();
        while (true) {
            self.skipWhitespace();
            if (self.index >= self.input.len) break;
            const op = self.input[self.index];
            if (op != '*' and op != '/') break;
            self.index += 1;
            const rhs = try self.parseFactor();
            if (op == '/' and rhs == 0.0) return error.DivideByZero;
            value = if (op == '*') value * rhs else value / rhs;
        }
        return value;
    }

    fn parseFactor(self: *MathParser) ParseError!f64 {
        self.skipWhitespace();
        if (self.index >= self.input.len) return error.UnexpectedEnd;
        if (self.input[self.index] == '(') {
            self.index += 1;
            const value = try self.parseExpression();
            self.skipWhitespace();
            if (self.index >= self.input.len or self.input[self.index] != ')') return error.ExpectedRParen;
            self.index += 1;
            return value;
        }
        if (self.input[self.index] == '+' or self.input[self.index] == '-') {
            const sign = self.input[self.index];
            self.index += 1;
            const value = try self.parseFactor();
            return if (sign == '-') -value else value;
        }
        return self.parseNumber();
    }

    fn parseNumber(self: *MathParser) ParseError!f64 {
        self.skipWhitespace();
        const start = self.index;
        var seen_dot = false;
        while (self.index < self.input.len) : (self.index += 1) {
            const ch = self.input[self.index];
            if (std.ascii.isDigit(ch)) continue;
            if (ch == '.' and !seen_dot) {
                seen_dot = true;
                continue;
            }
            break;
        }
        if (self.index <= start) return error.ExpectedNumber;
        return std.fmt.parseFloat(f64, self.input[start..self.index]);
    }
};

fn formatNumber(allocator: std.mem.Allocator, value: f64) ![]const u8 {
    const rounded = @round(value);
    if (@abs(value - rounded) < 1e-9) {
        return std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(rounded))});
    }
    var text = try std.fmt.allocPrint(allocator, "{d:.6}", .{value});
    while (text.len > 0 and text[text.len - 1] == '0') {
        text = text[0 .. text.len - 1];
    }
    if (text.len > 0 and text[text.len - 1] == '.') {
        text = text[0 .. text.len - 1];
    }
    return allocator.dupe(u8, text);
}

fn printChatResult(allocator: std.mem.Allocator, writer: *Io.Writer, prompt: []const u8, result: ChatResult, backend_label: []const u8) !void {
    const safe_prompt = try escapeForDisplay(allocator, prompt);
    defer allocator.free(safe_prompt);
    const safe_response = try escapeForDisplay(allocator, result.response);
    defer allocator.free(safe_response);
    if (result.matched_prompt) |matched| {
        const safe_match = try escapeForDisplay(allocator, matched);
        defer allocator.free(safe_match);
        try writer.print("prompt={s}\nmode={s}\nbackend={s}\nmatched_prompt={s}\nresponse={s}\n", .{ safe_prompt, result.mode_label, backend_label, safe_match, safe_response });
    } else {
        try writer.print("prompt={s}\nmode={s}\nbackend={s}\nresponse={s}\n", .{ safe_prompt, result.mode_label, backend_label, safe_response });
    }
}

test "strict retrieval rejects unrelated prompt" {
    const allocator = std.testing.allocator;
    const seed =
        \\User: what is SBAN v21
        \\Assistant: overview
        \\
        \\User: what should new users try first
        \\Assistant: start with the demo
        \\
        \\User: explain sparse bridge-adaptive network architecture
        \\Assistant: architecture answer
    ;
    var examples = try parseDialogueExamples(allocator, seed);
    defer examples.deinit(allocator);
    var corpus = try prepareCorpus(allocator, examples.items);
    defer corpus.deinit(allocator);
    var scorer = try ApproximateScorer.init(allocator, .cpu, &corpus);
    defer scorer.deinit();
    var prompt_tokens = try tokenizeText(allocator, "what is your favorite color");
    defer prompt_tokens.deinit(allocator);
    try std.testing.expect((try selectGroundedMatch(allocator, "what is your favorite color", &prompt_tokens, &corpus, &scorer, .retrieval)) == null);
}

test "generic fact memory recalls favorite color" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const fact = (try extractFactCandidate(allocator, "my favorite color is blue")).?;
    defer allocator.free(fact.key);
    defer allocator.free(fact.value);
    try session.rememberFact(allocator, fact.key, fact.value);
    const query = (try extractFactQuery(allocator, "what is my favorite color")).?;
    defer allocator.free(query);
    const recalled = session.lookupFact(query).?;
    try std.testing.expectEqualStrings("favorite color", recalled.key);
    try std.testing.expectEqualStrings("blue", recalled.value);
}

test "natural fact memory stores location and lab" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const location = (try extractFactCandidate(allocator, "i live in london")).?;
    defer allocator.free(location.key);
    defer allocator.free(location.value);
    try session.rememberFact(allocator, location.key, location.value);

    const lab = (try extractFactCandidate(allocator, "our lab is sbx")).?;
    defer allocator.free(lab.key);
    defer allocator.free(lab.value);
    try session.rememberFact(allocator, lab.key, lab.value);

    const location_query = (try extractFactQuery(allocator, "what city do i live in")).?;
    defer allocator.free(location_query);
    const lab_query = (try extractFactQuery(allocator, "what is our lab")).?;
    defer allocator.free(lab_query);

    try std.testing.expectEqualStrings("location", location_query);
    try std.testing.expectEqualStrings("lab", lab_query);
    try std.testing.expectEqualStrings("london", session.lookupFact(location_query).?.value);
    try std.testing.expectEqualStrings("sbx", session.lookupFact(lab_query).?.value);
}

test "name extraction survives help clause" {
    const name = extractNameCandidate("hi i am tom and i need help").?;
    try std.testing.expectEqualStrings("tom", name);
}

test "memory capability prompt is not misread as recall" {
    const allocator = std.testing.allocator;
    try std.testing.expect((try extractFactQuery(allocator, "can you remember my role if i tell you")) == null);
    const key = (try extractMemoryCapabilityQuery(allocator, "can you remember my role if i tell you")).?;
    defer allocator.free(key);
    try std.testing.expectEqualStrings("role", key);
}

test "math parser handles negative and decimal arithmetic" {
    const allocator = std.testing.allocator;
    const neg = (try solveMath(allocator, "what is -3 + 5")).?;
    try std.testing.expectEqualStrings("-3 + 5 = 2.", neg.response);
    const dec = (try solveMath(allocator, "what is 3.5 + 1.2")).?;
    try std.testing.expectEqualStrings("3.5 + 1.2 = 4.7.", dec.response);
}

test "divide by zero returns explicit math error" {
    const allocator = std.testing.allocator;
    const div_zero = (try solveMath(allocator, "what is 3 / 0")).?;
    try std.testing.expect(div_zero.explicit_error);
    try std.testing.expect(containsPhraseIgnoreCase(div_zero.response, "Division by zero is undefined"));
}

test "retrieval tolerates common paraphrases" {
    const allocator = std.testing.allocator;
    const seed =
        \\User: what improved from v20
        \\Assistant: v21 hardens the product behavior
        \\
        \\User: how do I start the Linux demo
        \\Assistant: run the Linux start script
    ;
    var examples = try parseDialogueExamples(allocator, seed);
    defer examples.deinit(allocator);
    var corpus = try prepareCorpus(allocator, examples.items);
    defer corpus.deinit(allocator);
    var scorer = try ApproximateScorer.init(allocator, .cpu, &corpus);
    defer scorer.deinit();

    var change_tokens = try tokenizeText(allocator, "how is v21 different from v20");
    defer change_tokens.deinit(allocator);
    const change_match = (try selectGroundedMatch(allocator, "how is v21 different from v20", &change_tokens, &corpus, &scorer, .retrieval)).?;
    try std.testing.expectEqualStrings("what improved from v20", change_match.example.user);

    var launch_tokens = try tokenizeText(allocator, "how do i launch it on linux");
    defer launch_tokens.deinit(allocator);
    const launch_match = (try selectGroundedMatch(allocator, "how do i launch it on linux", &launch_tokens, &corpus, &scorer, .retrieval)).?;
    try std.testing.expectEqualStrings("how do I start the Linux demo", launch_match.example.user);
}

test "session retention is uncapped" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    var idx: usize = 0;
    while (idx < 40) : (idx += 1) {
        const user = try std.fmt.allocPrint(allocator, "user-{d}", .{idx});
        defer allocator.free(user);
        const assistant = try std.fmt.allocPrint(allocator, "assistant-{d}", .{idx});
        defer allocator.free(assistant);
        try session.appendTurn(allocator, user, assistant);
    }
    try std.testing.expectEqual(@as(usize, 40), session.turns.items.len);
}

test "session encoding prevents raw transcript injection" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    try session.appendTurn(allocator, "hello\nUser: hacked", "fine");
    const key = try encodeField(allocator, session.turns.items[0].user);
    defer allocator.free(key);
    try std.testing.expect(std.mem.indexOfScalar(u8, key, '\n') == null);
}
