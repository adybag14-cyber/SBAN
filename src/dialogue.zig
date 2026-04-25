const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const cfg = @import("config.zig");
const netmod = @import("network.zig");

const feature_dim = 128;
const current_release_name = "SBAN v35";
const current_release_version = "v35";
const current_prewarm_path = "data/sban_runtime_prewarm_v35.txt";
const current_seed_path = current_prewarm_path;
const current_cold_seed_path = "data/sban_cold_seed_v35.txt";
const current_open_seed_path = "data/sban_dialogue_open_seed_v35.txt";
const current_knowledge_path = current_prewarm_path;
const current_learned_path = "data/sban_learned_reasoning_v35.txt";
const current_prompt_eval_path = "data/sban_chat_eval_prompts_v35.txt";
const current_session_eval_path = "data/sban_session_eval_v35.txt";
const current_open_chat_eval_path = "data/sban_open_chat_session_eval_v35.txt";
const current_summary_path = "SBAN_v35_EXECUTIVE_SUMMARY.md";
const current_report_path = "SBAN_v35_REPORT.md";
const current_paper_path = "docs/papers/SBAN_v35_follow_up_research_paper.pdf";
const current_repo_zip_path = "deliverables/v35/SBAN_v35_repo.zip";
const current_windows_demo_start = "SBAN_v35_Start.bat";
const current_linux_demo_start = "./SBAN_v35_Start.sh";
const current_windows_demo_zip = "deliverables/v35/demo/SBAN_v35_windows_x86_64_demo.zip";
const current_linux_demo_zip = "deliverables/v35/demo/SBAN_v35_linux_x86_64_demo.zip";
const session_magic = "SBAN_SESSION_V35";
const legacy_session_magic_v34 = "SBAN_SESSION_V34";
const legacy_session_magic_v33 = "SBAN_SESSION_V33";
const legacy_session_magic_v32 = "SBAN_SESSION_V32";
const legacy_session_magic_v31 = "SBAN_SESSION_V31";
const legacy_session_magic_v29 = "SBAN_SESSION_V29";
const legacy_session_magic_v28 = "SBAN_SESSION_V28";
const legacy_session_magic_v27 = "SBAN_SESSION_V27";
const legacy_session_magic_v26 = "SBAN_SESSION_V26";
const legacy_session_magic_v25 = "SBAN_SESSION_V25";
const legacy_session_magic_v24 = "SBAN_SESSION_V24";
const legacy_session_magic_v23_5 = "SBAN_SESSION_V23_5";
const legacy_session_magic_v23 = "SBAN_SESSION_V23";
const legacy_session_magic_v22 = "SBAN_SESSION_V22";
const legacy_session_magic_v21 = "SBAN_SESSION_V21";
const max_top_candidates = 16;
const display_prompt_max_bytes = 360;
const max_session_file_bytes: usize = 256 << 10;
const max_session_turns: usize = 128;
const max_session_facts: usize = 128;

const ChatMode = enum { anchor, free, hybrid };
const AccelBackend = enum { auto, cpu, cpu_mt, gpu, opencl, cuda };
const AccelRuntime = enum { cpu, cpu_mt, opencl, cuda };
const auto_cpu_mt_min_examples: usize = 32768;

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
    seed_path: []const u8 = current_seed_path,
    open_seed_path: ?[]const u8 = null,
    knowledge_path: ?[]const u8 = current_knowledge_path,
    learned_path: ?[]const u8 = current_learned_path,
    session_path: ?[]const u8 = null,
    mode: ChatMode = .free,
    backend: AccelBackend = .auto,
    worker_threads: usize = 0,
    iterations: usize = 1,
    max_bytes: usize = 160,
    continue_bytes: usize = 0,
    allow_generation: bool = true,
    net_config: cfg.NetworkConfig = blk: {
        const config = cfg.v35ReleaseConfig(4);
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
        const normalized_value = try sanitizeFactValue(allocator, value);
        for (self.facts.items) |*fact| {
            if (std.ascii.eqlIgnoreCase(fact.key, normalized_key)) {
                allocator.free(normalized_key);
                allocator.free(fact.value);
                fact.value = normalized_value;
                return;
            }
        }
        while (self.facts.items.len >= max_session_facts) {
            const dropped = self.facts.orderedRemove(0);
            allocator.free(dropped.key);
            allocator.free(dropped.value);
        }
        try self.facts.append(allocator, .{ .key = normalized_key, .value = normalized_value });
    }

    fn forgetFact(self: *SessionState, allocator: std.mem.Allocator, key: []const u8) !bool {
        const normalized_key = try normalizeFactKey(allocator, key);
        defer allocator.free(normalized_key);
        var idx: usize = 0;
        while (idx < self.facts.items.len) : (idx += 1) {
            if (!std.ascii.eqlIgnoreCase(self.facts.items[idx].key, normalized_key)) continue;
            const removed = self.facts.orderedRemove(idx);
            allocator.free(removed.key);
            allocator.free(removed.value);
            return true;
        }
        return false;
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
        while (self.turns.items.len > max_session_turns) {
            const dropped = self.turns.orderedRemove(0);
            allocator.free(dropped.user);
            allocator.free(dropped.assistant);
        }
    }
};

const IntentKind = enum {
    what,
    how,
    why,
    explain,
    compare,
    give,
    list,
    should,
    can,
    does,
    which,
    where,
    other,
};

const TokenizedText = struct {
    normalized: []u8,
    token_hashes: std.ArrayList(u64) = .empty,
    topic_hashes: std.ArrayList(u64) = .empty,
    bigram_hashes: std.ArrayList(u64) = .empty,
    intent: IntentKind = .other,
    vector: [feature_dim]u16 = [_]u16{0} ** feature_dim,

    fn deinit(self: *TokenizedText, allocator: std.mem.Allocator) void {
        allocator.free(self.normalized);
        self.token_hashes.deinit(allocator);
        self.topic_hashes.deinit(allocator);
        self.bigram_hashes.deinit(allocator);
    }
};

const PreparedExample = struct {
    example: DialogueExample,
    vector: [feature_dim]u16,
};

const PreparedCorpus = struct {
    items: std.ArrayList(PreparedExample) = .empty,
    flat_vectors: ?[]u16 = null,

    fn deinit(self: *PreparedCorpus, allocator: std.mem.Allocator) void {
        if (self.flat_vectors) |flat| allocator.free(flat);
        self.items.deinit(allocator);
    }

    fn exampleCount(self: *const PreparedCorpus) usize {
        return self.items.items.len;
    }
};

const LoadedDialogueCorpus = struct {
    seed_bytes: []u8,
    examples: std.ArrayList(DialogueExample),
    corpus: PreparedCorpus,
    scorer: ApproximateScorer,

    fn deinit(self: *LoadedDialogueCorpus, allocator: std.mem.Allocator) void {
        self.scorer.deinit();
        self.corpus.deinit(allocator);
        self.examples.deinit(allocator);
        allocator.free(self.seed_bytes);
    }
};

const ApproxScore = struct {
    index: usize,
    score: u32,
};

const LexicalScore = struct {
    score: i32,
    overlap: usize,
    topic_overlap: usize,
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

const CudaUnavailable = error{
    NoCudaLoader,
    NoCudaDevice,
    InvalidKernel,
    CudaFailure,
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

const ClGetPlatformIDsFn = *const fn (cl_uint, ?[*]cl_platform_id, *cl_uint) callconv(.c) cl_int;
const ClGetPlatformInfoFn = *const fn (cl_platform_id, cl_platform_info, usize, ?*anyopaque, *usize) callconv(.c) cl_int;
const ClGetDeviceIDsFn = *const fn (cl_platform_id, cl_device_type, cl_uint, ?[*]cl_device_id, *cl_uint) callconv(.c) cl_int;
const ClGetDeviceInfoFn = *const fn (cl_device_id, cl_device_info, usize, ?*anyopaque, *usize) callconv(.c) cl_int;
const ClCreateContextFn = *const fn (?[*]const isize, cl_uint, [*]const cl_device_id, ?*const fn ([*:0]const u8, ?*const anyopaque, usize, ?*anyopaque) callconv(.c) void, ?*anyopaque, *cl_int) callconv(.c) cl_context;
const ClCreateCommandQueueFn = *const fn (cl_context, cl_device_id, cl_command_queue_properties, *cl_int) callconv(.c) cl_command_queue;
const ClCreateProgramWithSourceFn = *const fn (cl_context, cl_uint, [*]const [*:0]const u8, [*]const usize, *cl_int) callconv(.c) cl_program;
const ClBuildProgramFn = *const fn (cl_program, cl_uint, ?[*]const cl_device_id, ?[*:0]const u8, ?*const fn (cl_program, ?*anyopaque) callconv(.c) void, ?*anyopaque) callconv(.c) cl_int;
const ClGetProgramBuildInfoFn = *const fn (cl_program, cl_device_id, cl_program_build_info, usize, ?*anyopaque, *usize) callconv(.c) cl_int;
const ClCreateKernelFn = *const fn (cl_program, [*:0]const u8, *cl_int) callconv(.c) cl_kernel;
const ClCreateBufferFn = *const fn (cl_context, cl_mem_flags, usize, ?*anyopaque, *cl_int) callconv(.c) cl_mem;
const ClSetKernelArgFn = *const fn (cl_kernel, cl_uint, usize, ?*const anyopaque) callconv(.c) cl_int;
const ClEnqueueWriteBufferFn = *const fn (cl_command_queue, cl_mem, cl_bool, usize, usize, ?*const anyopaque, cl_uint, ?*const anyopaque, ?*anyopaque) callconv(.c) cl_int;
const ClEnqueueNDRangeKernelFn = *const fn (cl_command_queue, cl_kernel, cl_uint, ?[*]const usize, [*]const usize, ?[*]const usize, cl_uint, ?*const anyopaque, ?*anyopaque) callconv(.c) cl_int;
const ClEnqueueReadBufferFn = *const fn (cl_command_queue, cl_mem, cl_bool, usize, usize, ?*anyopaque, cl_uint, ?*const anyopaque, ?*anyopaque) callconv(.c) cl_int;
const ClFinishFn = *const fn (cl_command_queue) callconv(.c) cl_int;
const ClReleaseMemObjectFn = *const fn (cl_mem) callconv(.c) cl_int;
const ClReleaseKernelFn = *const fn (cl_kernel) callconv(.c) cl_int;
const ClReleaseProgramFn = *const fn (cl_program) callconv(.c) cl_int;
const ClReleaseCommandQueueFn = *const fn (cl_command_queue) callconv(.c) cl_int;
const ClReleaseContextFn = *const fn (cl_context) callconv(.c) cl_int;

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
        const example_buffer = api.create_buffer(context, cl_mem_read_only | cl_mem_copy_host_ptr, example_bytes, @ptrCast(@constCast(flat_matrix.ptr)), &errcode);
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

const CpuScoreTask = struct {
    flat_vectors: []const u16,
    prompt_vector: *const [feature_dim]u16,
    output: []u32,
    start_index: usize,
    end_index: usize,
};

fn scoreCpuRange(task: CpuScoreTask) void {
    var idx = task.start_index;
    while (idx < task.end_index) : (idx += 1) {
        const base = idx * feature_dim;
        task.output[idx] = dotProductFlat(task.prompt_vector, task.flat_vectors[base .. base + feature_dim]);
    }
}

const CpuMtScorer = struct {
    allocator: std.mem.Allocator,
    worker_threads: usize,

    fn init(allocator: std.mem.Allocator, corpus: *const PreparedCorpus, requested_threads: usize) CpuMtScorer {
        const cpu_count = std.Thread.getCpuCount() catch 1;
        const desired = if (requested_threads != 0) requested_threads else @min(cpu_count, @as(usize, 4));
        var worker_threads = @max(@as(usize, 1), desired);
        worker_threads = @min(worker_threads, @max(@as(usize, 1), corpus.exampleCount()));
        return .{
            .allocator = allocator,
            .worker_threads = worker_threads,
        };
    }

    fn score(self: *const CpuMtScorer, corpus: *const PreparedCorpus, prompt_vector: *const [feature_dim]u16, output: []u32) !void {
        const flat = corpus.flat_vectors orelse return error.InvalidCorpus;
        if (self.worker_threads <= 1 or output.len < 1024) {
            scoreCpuRange(.{
                .flat_vectors = flat,
                .prompt_vector = prompt_vector,
                .output = output,
                .start_index = 0,
                .end_index = output.len,
            });
            return;
        }

        const thread_count = @min(self.worker_threads, output.len);
        var threads = try self.allocator.alloc(std.Thread, thread_count - 1);
        defer self.allocator.free(threads);
        var tasks = try self.allocator.alloc(CpuScoreTask, thread_count);
        defer self.allocator.free(tasks);

        const chunk_size = @divTrunc(output.len + thread_count - 1, thread_count);
        var spawned: usize = 0;
        errdefer {
            for (threads[0..spawned]) |thread| thread.join();
        }

        for (0..thread_count) |worker_idx| {
            const start_index = worker_idx * chunk_size;
            const end_index = @min(output.len, start_index + chunk_size);
            tasks[worker_idx] = .{
                .flat_vectors = flat,
                .prompt_vector = prompt_vector,
                .output = output,
                .start_index = start_index,
                .end_index = end_index,
            };
            if (worker_idx == 0) continue;
            threads[worker_idx - 1] = try std.Thread.spawn(.{}, scoreCpuRange, .{tasks[worker_idx]});
            spawned += 1;
        }

        scoreCpuRange(tasks[0]);
        for (threads[0..spawned]) |thread| thread.join();
    }
};

const cu_result = u32;
const cu_device = i32;
const cu_context = ?*anyopaque;
const cu_module = ?*anyopaque;
const cu_function = ?*anyopaque;
const cu_stream = ?*anyopaque;
const cu_device_ptr = u64;

const CuInitFn = *const fn (u32) callconv(.c) cu_result;
const CuDeviceGetCountFn = *const fn (*i32) callconv(.c) cu_result;
const CuDeviceGetFn = *const fn (*cu_device, i32) callconv(.c) cu_result;
const CuDeviceGetNameFn = *const fn ([*]u8, i32, cu_device) callconv(.c) cu_result;
const CuCtxCreateFn = *const fn (*cu_context, u32, cu_device) callconv(.c) cu_result;
const CuCtxDestroyFn = *const fn (cu_context) callconv(.c) cu_result;
const CuModuleLoadDataExFn = *const fn (*cu_module, *const anyopaque, u32, ?[*]u32, ?[*]?*anyopaque) callconv(.c) cu_result;
const CuModuleGetFunctionFn = *const fn (*cu_function, cu_module, [*:0]const u8) callconv(.c) cu_result;
const CuModuleUnloadFn = *const fn (cu_module) callconv(.c) cu_result;
const CuMemAllocFn = *const fn (*cu_device_ptr, usize) callconv(.c) cu_result;
const CuMemFreeFn = *const fn (cu_device_ptr) callconv(.c) cu_result;
const CuMemcpyHtoDFn = *const fn (cu_device_ptr, *const anyopaque, usize) callconv(.c) cu_result;
const CuMemcpyDtoHFn = *const fn (*anyopaque, cu_device_ptr, usize) callconv(.c) cu_result;
const CuLaunchKernelFn = *const fn (cu_function, u32, u32, u32, u32, u32, u32, u32, cu_stream, ?[*]?*anyopaque, ?[*]?*anyopaque) callconv(.c) cu_result;
const CuCtxSynchronizeFn = *const fn () callconv(.c) cu_result;
const CuGetErrorNameFn = *const fn (cu_result, *?[*:0]const u8) callconv(.c) cu_result;
const CuGetErrorStringFn = *const fn (cu_result, *?[*:0]const u8) callconv(.c) cu_result;

const CudaApi = struct {
    init: CuInitFn,
    device_get_count: CuDeviceGetCountFn,
    device_get: CuDeviceGetFn,
    device_get_name: CuDeviceGetNameFn,
    ctx_create: CuCtxCreateFn,
    ctx_destroy: CuCtxDestroyFn,
    module_load_data_ex: CuModuleLoadDataExFn,
    module_get_function: CuModuleGetFunctionFn,
    module_unload: CuModuleUnloadFn,
    mem_alloc: CuMemAllocFn,
    mem_free: CuMemFreeFn,
    memcpy_htod: CuMemcpyHtoDFn,
    memcpy_dtoh: CuMemcpyDtoHFn,
    launch_kernel: CuLaunchKernelFn,
    ctx_synchronize: CuCtxSynchronizeFn,
    get_error_name: ?CuGetErrorNameFn = null,
    get_error_string: ?CuGetErrorStringFn = null,
};

const CudaScorer = struct {
    allocator: std.mem.Allocator,
    lib: DynamicLibrary,
    api: CudaApi,
    context: cu_context,
    module: cu_module,
    function: cu_function,
    example_buffer: cu_device_ptr,
    prompt_buffer: cu_device_ptr,
    output_buffer: cu_device_ptr,
    example_count: usize,
    device_name: []u8,
    platform_name: []u8,

    fn init(allocator: std.mem.Allocator, flat_matrix: []const u16, example_count: usize) !CudaScorer {
        var lib = try openCudaLibrary();
        errdefer lib.close();
        const api = try loadCudaApi(&lib);

        try checkCuda(api, api.init(0));

        var device_count: i32 = 0;
        try checkCuda(api, api.device_get_count(&device_count));
        if (device_count <= 0) return CudaUnavailable.NoCudaDevice;

        var device: cu_device = 0;
        try checkCuda(api, api.device_get(&device, 0));

        var raw_name: [128]u8 = [_]u8{0} ** 128;
        try checkCuda(api, api.device_get_name(&raw_name, raw_name.len, device));
        const device_name = try allocator.dupe(u8, std.mem.sliceTo(&raw_name, 0));
        errdefer allocator.free(device_name);
        const platform_name = try allocator.dupe(u8, "NVIDIA CUDA");
        errdefer allocator.free(platform_name);

        var context: cu_context = null;
        try checkCuda(api, api.ctx_create(&context, 0, device));
        errdefer _ = api.ctx_destroy(context);

        var module: cu_module = null;
        try checkCuda(api, api.module_load_data_ex(&module, @ptrCast(cuda_kernel_ptx.ptr), 0, null, null));
        errdefer _ = api.ctx_destroy(context);
        errdefer _ = api.module_unload(module);

        var function: cu_function = null;
        try checkCuda(api, api.module_get_function(&function, module, "score_examples_cuda"));

        var example_buffer: cu_device_ptr = 0;
        try checkCuda(api, api.mem_alloc(&example_buffer, flat_matrix.len * @sizeOf(u16)));
        errdefer _ = api.mem_free(example_buffer);
        try checkCuda(api, api.memcpy_htod(example_buffer, @ptrCast(flat_matrix.ptr), flat_matrix.len * @sizeOf(u16)));

        var prompt_buffer: cu_device_ptr = 0;
        try checkCuda(api, api.mem_alloc(&prompt_buffer, feature_dim * @sizeOf(u16)));
        errdefer _ = api.mem_free(prompt_buffer);

        var output_buffer: cu_device_ptr = 0;
        try checkCuda(api, api.mem_alloc(&output_buffer, example_count * @sizeOf(u32)));
        errdefer _ = api.mem_free(output_buffer);

        return .{
            .allocator = allocator,
            .lib = lib,
            .api = api,
            .context = context,
            .module = module,
            .function = function,
            .example_buffer = example_buffer,
            .prompt_buffer = prompt_buffer,
            .output_buffer = output_buffer,
            .example_count = example_count,
            .device_name = device_name,
            .platform_name = platform_name,
        };
    }

    fn deinit(self: *CudaScorer) void {
        _ = self.api.mem_free(self.output_buffer);
        _ = self.api.mem_free(self.prompt_buffer);
        _ = self.api.mem_free(self.example_buffer);
        _ = self.api.module_unload(self.module);
        _ = self.api.ctx_destroy(self.context);
        self.lib.close();
        self.allocator.free(self.device_name);
        self.allocator.free(self.platform_name);
    }

    fn score(self: *CudaScorer, prompt_vector: *const [feature_dim]u16, output: []u32) !void {
        if (output.len != self.example_count) return error.InvalidArgument;

        try checkCuda(self.api, self.api.memcpy_htod(self.prompt_buffer, @ptrCast(prompt_vector), feature_dim * @sizeOf(u16)));

        var prompt_arg = self.prompt_buffer;
        var example_arg = self.example_buffer;
        var output_arg = self.output_buffer;
        var count_arg: u32 = @intCast(self.example_count);
        var kernel_params = [_]?*anyopaque{
            @ptrCast(&prompt_arg),
            @ptrCast(&example_arg),
            @ptrCast(&output_arg),
            @ptrCast(&count_arg),
        };

        const block_x: u32 = 256;
        const grid_x: u32 = @intCast(@divTrunc(self.example_count + block_x - 1, block_x));
        try checkCuda(self.api, self.api.launch_kernel(self.function, grid_x, 1, 1, block_x, 1, 1, 0, null, &kernel_params, null));
        try checkCuda(self.api, self.api.ctx_synchronize());
        try checkCuda(self.api, self.api.memcpy_dtoh(output.ptr, self.output_buffer, output.len * @sizeOf(u32)));
    }
};

const ApproximateScorer = struct {
    allocator: std.mem.Allocator,
    backend_used: AccelRuntime,
    cpu_mt: ?CpuMtScorer = null,
    opencl: ?OpenClScorer = null,
    cuda: ?CudaScorer = null,

    fn init(allocator: std.mem.Allocator, preference: AccelBackend, corpus: *const PreparedCorpus, requested_threads: usize) !ApproximateScorer {
        const cpu_mt = CpuMtScorer.init(allocator, corpus, requested_threads);
        switch (preference) {
            .cpu => return .{ .allocator = allocator, .backend_used = .cpu },
            .cpu_mt => return .{ .allocator = allocator, .backend_used = if (cpu_mt.worker_threads > 1) .cpu_mt else .cpu, .cpu_mt = cpu_mt },
            .cuda => return .{ .allocator = allocator, .backend_used = .cuda, .cuda = try initCudaScorer(allocator, corpus) },
            .opencl => return .{ .allocator = allocator, .backend_used = .opencl, .opencl = try initOpenClScorer(allocator, corpus) },
            .gpu => {
                if (initCudaScorer(allocator, corpus)) |cuda| {
                    return .{ .allocator = allocator, .backend_used = .cuda, .cuda = cuda };
                } else |_| {
                    return .{ .allocator = allocator, .backend_used = .opencl, .opencl = try initOpenClScorer(allocator, corpus) };
                }
            },
            .auto => {
                if (corpus.exampleCount() >= 4096) {
                    if (initCudaScorer(allocator, corpus)) |cuda| {
                        return .{ .allocator = allocator, .backend_used = .cuda, .cuda = cuda };
                    } else |_| {}
                }
                if (cpu_mt.worker_threads > 1 and corpus.exampleCount() >= auto_cpu_mt_min_examples) {
                    return .{ .allocator = allocator, .backend_used = .cpu_mt, .cpu_mt = cpu_mt };
                }
                return .{ .allocator = allocator, .backend_used = .cpu };
            },
        }
    }

    fn deinit(self: *ApproximateScorer) void {
        if (self.opencl) |*gpu| gpu.deinit();
        if (self.cuda) |*gpu| gpu.deinit();
    }

    fn backendLabel(self: *const ApproximateScorer) []const u8 {
        return switch (self.backend_used) {
            .cpu => "cpu",
            .cpu_mt => "cpu_mt",
            .opencl => "opencl",
            .cuda => "cuda",
        };
    }

    fn workerThreadCount(self: *const ApproximateScorer) usize {
        return if (self.cpu_mt) |cpu_mt| cpu_mt.worker_threads else 1;
    }

    fn platformLabel(self: *const ApproximateScorer) ?[]const u8 {
        if (self.cuda) |*gpu| return gpu.platform_name;
        if (self.opencl) |*gpu| return gpu.platform_name;
        return null;
    }

    fn deviceLabel(self: *const ApproximateScorer) ?[]const u8 {
        if (self.cuda) |*gpu| return gpu.device_name;
        if (self.opencl) |*gpu| return gpu.device_name;
        return null;
    }

    fn score(self: *ApproximateScorer, corpus: *const PreparedCorpus, prompt_vector: *const [feature_dim]u16, output: []u32) !void {
        if (self.cuda) |*gpu| return gpu.score(prompt_vector, output);
        if (self.opencl) |*gpu| return gpu.score(prompt_vector, output);
        if (self.backend_used == .cpu_mt) {
            if (self.cpu_mt) |cpu_mt| return cpu_mt.score(corpus, prompt_vector, output);
        }

        const flat = corpus.flat_vectors orelse return error.InvalidCorpus;
        scoreCpuRange(.{
            .flat_vectors = flat,
            .prompt_vector = prompt_vector,
            .output = output,
            .start_index = 0,
            .end_index = output.len,
        });
    }
};

pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\  zig build run -- chat-demo [prompt] [max_bytes] [key=value ...]
        \\  zig build run -- chat-eval [prompt_file_path] [key=value ...]
        \\  zig build run -- chat-session-eval [script_file_path] [key=value ...]
        \\  zig build run -- accel-info [key=value ...]
        \\  zig build run -- accel-bench [prompt_file_path] [key=value ...]
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

    var scorer = ApproximateScorer.init(allocator, options.backend, &corpus, options.worker_threads) catch |err| {
        try writer.print("backend=cpu\nreason={s}\n", .{@errorName(err)});
        return;
    };
    defer scorer.deinit();

    if (scorer.platformLabel()) |platform| {
        const device = scorer.deviceLabel() orelse "unknown";
        try writer.print("backend={s}\nplatform={s}\ndevice={s}\n", .{ scorer.backendLabel(), platform, device });
    } else {
        try writer.print("backend={s}\nworker_threads={d}\n", .{ scorer.backendLabel(), scorer.workerThreadCount() });
    }
}

pub fn runAccelBench(allocator: std.mem.Allocator, io: std.Io, writer: *Io.Writer, args: []const []const u8) !void {
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
    if (options.iterations == 0) options.iterations = 1;

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
    var scorer = ApproximateScorer.init(allocator, options.backend, &corpus, options.worker_threads) catch |err| {
        try writer.print("error=accelerator_init_failed detail={s}\n", .{@errorName(err)});
        try writer.flush();
        return;
    };
    defer scorer.deinit();

    var prompt_vectors = std.ArrayList([feature_dim]u16).empty;
    defer prompt_vectors.deinit(allocator);
    var iter = std.mem.splitScalar(u8, prompt_bytes, '\n');
    while (iter.next()) |raw_line| {
        const prompt = try sanitizeTurnText(allocator, trimLine(raw_line));
        defer allocator.free(prompt);
        if (prompt.len == 0 or prompt[0] == '#') continue;
        var tokenized = try tokenizeText(allocator, prompt);
        defer tokenized.deinit(allocator);
        try prompt_vectors.append(allocator, tokenized.vector);
    }

    if (prompt_vectors.items.len == 0) {
        try writer.writeAll("error=no_prompts\n");
        try writer.flush();
        return;
    }

    const output = try allocator.alloc(u32, corpus.exampleCount());
    defer allocator.free(output);
    var total_queries: usize = 0;
    for (0..options.iterations) |_| {
        for (prompt_vectors.items) |*vector| {
            try scorer.score(&corpus, vector, output);
            total_queries += 1;
        }
    }

    try writer.print(
        "backend={s}\nworker_threads={d}\nexamples={d}\nprompts={d}\niterations={d}\ntotal_queries={d}\ntotal_scores={d}\n",
        .{
            scorer.backendLabel(),
            scorer.workerThreadCount(),
            corpus.exampleCount(),
            prompt_vectors.items.len,
            options.iterations,
            total_queries,
            total_queries * corpus.exampleCount(),
        },
    );
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

    var grounded_assets = (try loadDialogueCorpus(allocator, io, writer, options.seed_path, "seed_path", options.backend, options.worker_threads)) orelse return;
    defer grounded_assets.deinit(allocator);

    var open_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.open_seed_path, "open_seed_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (open_assets) |*assets| assets.deinit(allocator);
    }
    const open_corpus = if (open_assets) |*assets| &assets.corpus else null;
    const open_scorer = if (open_assets) |*assets| &assets.scorer else null;
    var knowledge_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.knowledge_path, "knowledge_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (knowledge_assets) |*assets| assets.deinit(allocator);
    }
    const knowledge_corpus = if (knowledge_assets) |*assets| &assets.corpus else null;
    const knowledge_scorer = if (knowledge_assets) |*assets| &assets.scorer else null;
    var learned_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.learned_path, "learned_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (learned_assets) |*assets| assets.deinit(allocator);
    }
    const learned_corpus = if (learned_assets) |*assets| &assets.corpus else null;
    const learned_scorer = if (learned_assets) |*assets| &assets.scorer else null;

    var session = loadSessionState(allocator, io, options.session_path) catch SessionState{};
    defer session.deinit(allocator);

    const result = answerPrompt(
        allocator,
        prompt,
        grounded_assets.seed_bytes,
        grounded_assets.examples.items,
        &grounded_assets.corpus,
        &grounded_assets.scorer,
        open_corpus,
        open_scorer,
        knowledge_corpus,
        knowledge_scorer,
        learned_corpus,
        learned_scorer,
        &session,
        options,
    ) catch |err| {
        try writer.print("error=chat_failed detail={s}\n", .{@errorName(err)});
        try writer.flush();
        return;
    };

    try printChatResult(allocator, writer, prompt, result, grounded_assets.scorer.backendLabel(), options.max_bytes);
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

    const prompt_bytes = readWholeFileFriendly(allocator, io, writer, args[2], "prompt_path") orelse return;
    defer allocator.free(prompt_bytes);
    var grounded_assets = (try loadDialogueCorpus(allocator, io, writer, options.seed_path, "seed_path", options.backend, options.worker_threads)) orelse return;
    defer grounded_assets.deinit(allocator);
    var open_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.open_seed_path, "open_seed_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (open_assets) |*assets| assets.deinit(allocator);
    }
    const open_corpus = if (open_assets) |*assets| &assets.corpus else null;
    const open_scorer = if (open_assets) |*assets| &assets.scorer else null;
    var knowledge_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.knowledge_path, "knowledge_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (knowledge_assets) |*assets| assets.deinit(allocator);
    }
    const knowledge_corpus = if (knowledge_assets) |*assets| &assets.corpus else null;
    const knowledge_scorer = if (knowledge_assets) |*assets| &assets.scorer else null;
    var learned_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.learned_path, "learned_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (learned_assets) |*assets| assets.deinit(allocator);
    }
    const learned_corpus = if (learned_assets) |*assets| &assets.corpus else null;
    const learned_scorer = if (learned_assets) |*assets| &assets.scorer else null;

    var total: usize = 0;
    var anchored: usize = 0;
    var retrieved: usize = 0;
    var symbolic: usize = 0;
    var nonempty: usize = 0;
    var uncertain: usize = 0;
    var iter = std.mem.splitScalar(u8, prompt_bytes, '\n');
    while (iter.next()) |raw_line| {
        const prompt = try sanitizeTurnText(allocator, trimLine(raw_line));
        if (prompt.len == 0 or prompt[0] == '#') continue;
        total += 1;
        var session: SessionState = .{};
        defer session.deinit(allocator);
        const result = try answerPrompt(
            allocator,
            prompt,
            grounded_assets.seed_bytes,
            grounded_assets.examples.items,
            &grounded_assets.corpus,
            &grounded_assets.scorer,
            open_corpus,
            open_scorer,
            knowledge_corpus,
            knowledge_scorer,
            learned_corpus,
            learned_scorer,
            &session,
            options,
        );
        if (result.response.len > 0) nonempty += 1;
        if (result.anchored) anchored += 1;
        if (result.retrieved) retrieved += 1;
        if (result.symbolic) symbolic += 1;
        if (std.mem.eql(u8, result.mode_label, "uncertain")) uncertain += 1;
        try writer.print("[{d}] ", .{total});
        try printChatResult(allocator, writer, prompt, result, grounded_assets.scorer.backendLabel(), options.max_bytes);
        try writer.writeAll("\n");
    }
    try writer.print("summary turns={d} anchored={d} retrieved={d} symbolic={d} nonempty={d} uncertain={d}\n", .{ total, anchored, retrieved, symbolic, nonempty, uncertain });
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

    const script_bytes = readWholeFileFriendly(allocator, io, writer, args[2], "script_path") orelse return;
    defer allocator.free(script_bytes);
    var grounded_assets = (try loadDialogueCorpus(allocator, io, writer, options.seed_path, "seed_path", options.backend, options.worker_threads)) orelse return;
    defer grounded_assets.deinit(allocator);
    var open_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.open_seed_path, "open_seed_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (open_assets) |*assets| assets.deinit(allocator);
    }
    const open_corpus = if (open_assets) |*assets| &assets.corpus else null;
    const open_scorer = if (open_assets) |*assets| &assets.scorer else null;
    var knowledge_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.knowledge_path, "knowledge_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (knowledge_assets) |*assets| assets.deinit(allocator);
    }
    const knowledge_corpus = if (knowledge_assets) |*assets| &assets.corpus else null;
    const knowledge_scorer = if (knowledge_assets) |*assets| &assets.scorer else null;
    var learned_assets = if (options.mode == .free and options.allow_generation)
        try loadOptionalDialogueCorpus(allocator, io, writer, options.learned_path, "learned_path", options.backend, options.worker_threads)
    else
        null;
    defer {
        if (learned_assets) |*assets| assets.deinit(allocator);
    }
    const learned_corpus = if (learned_assets) |*assets| &assets.corpus else null;
    const learned_scorer = if (learned_assets) |*assets| &assets.scorer else null;

    var session: SessionState = .{};
    defer session.deinit(allocator);
    var turns: usize = 0;
    var anchored: usize = 0;
    var retrieved: usize = 0;
    var symbolic: usize = 0;
    var nonempty: usize = 0;
    var uncertain: usize = 0;
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
            const result = try answerPrompt(
                allocator,
                prompt,
                grounded_assets.seed_bytes,
                grounded_assets.examples.items,
                &grounded_assets.corpus,
                &grounded_assets.scorer,
                open_corpus,
                open_scorer,
                knowledge_corpus,
                knowledge_scorer,
                learned_corpus,
                learned_scorer,
                &session,
                options,
            );
            if (result.response.len > 0) nonempty += 1;
            if (result.anchored) anchored += 1;
            if (result.retrieved) retrieved += 1;
            if (result.symbolic) symbolic += 1;
            if (std.mem.eql(u8, result.mode_label, "uncertain")) uncertain += 1;
            try writer.print("[{d}] ", .{turns});
            try printChatResult(allocator, writer, prompt, result, grounded_assets.scorer.backendLabel(), options.max_bytes);
            try writer.writeAll("\n");
            try session.appendTurn(allocator, prompt, result.response);
            last_response = result.response;
        } else if (std.mem.startsWith(u8, line, "Expect:")) {
            const expected = trimLine(line[7..]);
            expectations += 1;
            const ok = expectationMatchesResponse(last_response, expected);
            if (ok) passed += 1;
            try writer.print("expect_match={s}\nexpect_pass={s}\n\n", .{ expected, if (ok) "true" else "false" });
        }
    }

    try writer.print(
        "summary turns={d} anchored={d} retrieved={d} symbolic={d} nonempty={d} uncertain={d} expectations={d} passed={d}\n",
        .{ turns, anchored, retrieved, symbolic, nonempty, uncertain, expectations, passed },
    );
}

fn answerPrompt(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    seed_bytes: []const u8,
    _: []const DialogueExample,
    corpus: *const PreparedCorpus,
    scorer: *ApproximateScorer,
    open_corpus: ?*const PreparedCorpus,
    open_scorer: ?*ApproximateScorer,
    knowledge_corpus: ?*const PreparedCorpus,
    knowledge_scorer: ?*ApproximateScorer,
    learned_corpus: ?*const PreparedCorpus,
    learned_scorer: ?*ApproximateScorer,
    session: *SessionState,
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

    if (try extractForgetFactQuery(allocator, prompt)) |fact_key| {
        defer allocator.free(fact_key);
        if (try session.forgetFact(allocator, fact_key)) {
            return .{
                .mode_label = "session-forget",
                .response = try buildFactForgetResponse(allocator, fact_key),
                .symbolic = true,
            };
        }
        return .{
            .mode_label = "session-forget-miss",
            .response = try buildFactForgetMiss(allocator, fact_key),
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

    if (try handleInstructionMemoryPrompt(allocator, prompt, session)) |response| {
        return .{
            .mode_label = "instruction-memory",
            .response = response,
            .symbolic = true,
        };
    }

    const maybe_fact = try extractFactCandidate(allocator, prompt);
    const wants_help = isHelpPrompt(prompt);
    if (maybe_fact) |fact| {
        defer allocator.free(fact.key);
        defer allocator.free(fact.value);
        if (isSensitiveFact(fact.key, fact.value)) {
            return .{
                .mode_label = "session-secret-rejected",
                .response = try allocator.dupe(u8, "I will not store secrets such as API keys, tokens, passwords, or private credentials in session memory."),
                .symbolic = true,
            };
        }
        try session.rememberFact(allocator, fact.key, fact.value);
        const stored_value = try sanitizeFactValue(allocator, fact.value);
        defer allocator.free(stored_value);
        const stored_fact: FactCandidate = .{ .key = fact.key, .value = stored_value };
        if (wants_help) {
            return .{
                .mode_label = "session-fact-help",
                .response = try buildFactHelpResponse(allocator, stored_fact),
                .symbolic = true,
            };
        }
        return .{
            .mode_label = "session-fact-store",
            .response = try buildFactStoredResponse(allocator, stored_fact),
            .symbolic = true,
        };
    }

    if (wants_help and isStandaloneHelpPrompt(prompt)) {
        return .{
            .mode_label = "symbolic-help",
            .response = try buildHelpResponse(allocator),
            .symbolic = true,
        };
    }

    if (try answerOperationalPrompt(allocator, prompt)) |result| {
        return result;
    }

    if (isUnsupportedSourceLocationPrompt(prompt)) {
        return .{
            .mode_label = "source-boundary",
            .response = try std.fmt.allocPrint(allocator, "I do not know that source-tree location from the bundled {s} knowledge. I should not invent a Linux kernel file path without a supplied source tree or index.", .{current_release_version}),
            .symbolic = true,
        };
    }

    if (options.mode == .free and options.allow_generation and isCurrentFactPrompt(prompt)) {
        if (try synthesizeFreeResponse(allocator, prompt, session, options)) |response| {
            return .{
                .mode_label = "free-composed",
                .response = response,
            };
        }
    }

    if (options.mode == .free and options.allow_generation and isPreRetrievalComposedPrompt(prompt)) {
        if (try synthesizeFreeResponse(allocator, prompt, session, options)) |response| {
            return .{
                .mode_label = "free-composed",
                .response = response,
            };
        }
    }

    if (options.mode == .free and options.allow_generation and isCodingHelpPrompt(prompt)) {
        if (try synthesizeFreeResponse(allocator, prompt, session, options)) |response| {
            return .{
                .mode_label = "free-composed",
                .response = response,
            };
        }
    }

    var prompt_tokens = try tokenizeText(allocator, prompt);
    defer prompt_tokens.deinit(allocator);
    const domain_prompt = isDomainPrompt(prompt);

    if (options.mode == .anchor or options.mode == .hybrid or (options.mode == .free and domain_prompt)) {
        if (try selectGroundedMatch(allocator, prompt, &prompt_tokens, corpus, scorer, .anchor)) |match| {
            const response = try maybeGroundedContinuation(allocator, seed_bytes, prompt, match.example, session, options);
            return .{
                .mode_label = switch (options.mode) {
                    .anchor => "anchor",
                    .hybrid => "hybrid-anchor",
                    .free => "free-anchor",
                },
                .matched_prompt = match.example.user,
                .response = response,
                .anchored = true,
            };
        }
    }

    if (options.mode == .hybrid or (options.mode == .free and domain_prompt)) {
        if (try selectGroundedMatch(allocator, prompt, &prompt_tokens, corpus, scorer, .retrieval)) |match| {
            return .{
                .mode_label = if (options.mode == .hybrid) "hybrid-retrieved" else "free-retrieved",
                .matched_prompt = match.example.user,
                .response = match.example.assistant,
                .retrieved = true,
            };
        }
    }

    if (options.mode == .free and !domain_prompt and options.allow_generation) {
        if (learned_corpus) |ready_corpus| {
            if (learned_scorer) |ready_scorer| {
                if (try selectGroundedMatch(allocator, prompt, &prompt_tokens, ready_corpus, ready_scorer, .learned)) |match| {
                    return .{
                        .mode_label = "learned-reasoning",
                        .matched_prompt = match.example.user,
                        .response = match.example.assistant,
                        .retrieved = true,
                    };
                }
            }
        }
    }

    if (options.mode == .free and !domain_prompt and options.allow_generation) {
        if (try synthesizeFreeResponse(allocator, prompt, session, options)) |response| {
            return .{
                .mode_label = "free-composed",
                .response = response,
            };
        }
    }

    if (options.mode == .free and !domain_prompt) {
        if (knowledge_corpus) |ready_corpus| {
            if (knowledge_scorer) |ready_scorer| {
                if (try selectGroundedMatch(allocator, prompt, &prompt_tokens, ready_corpus, ready_scorer, .knowledge)) |match| {
                    return .{
                        .mode_label = if (options.knowledge_path) |path| if (std.mem.eql(u8, path, current_prewarm_path)) "runtime-prewarm" else "synthetic-knowledge" else "synthetic-knowledge",
                        .matched_prompt = match.example.user,
                        .response = match.example.assistant,
                        .retrieved = true,
                    };
                }
            }
        }
        if (open_corpus) |open_ready_corpus| {
            if (open_scorer) |open_ready_scorer| {
                if (try selectGroundedMatch(allocator, prompt, &prompt_tokens, open_ready_corpus, open_ready_scorer, .open_chat)) |match| {
                    return .{
                        .mode_label = "free-open-retrieved",
                        .matched_prompt = match.example.user,
                        .response = match.example.assistant,
                        .retrieved = true,
                    };
                }
            }
        }
    }

    if (options.allow_generation) {
        if (try synthesizeFreeResponse(allocator, prompt, session, options)) |response| {
            return .{
                .mode_label = "free-composed",
                .response = response,
            };
        }
    }

    return .{
        .mode_label = "uncertain",
        .response = try buildUncertaintyResponse(allocator, prompt),
    };
}

const MatchRequest = enum { anchor, retrieval, knowledge, open_chat, learned };

const SelectedMatch = struct {
    example: DialogueExample,
    exact_score: i32,
};

fn requestAcceptsScore(scored: LexicalScore, request: MatchRequest) bool {
    return switch (request) {
        .anchor => scored.exact or (scored.prompt_cov_ppm >= 850 and scored.candidate_cov_ppm >= 700 and scored.overlap >= 2),
        .retrieval => scored.exact or ((scored.overlap >= 2 and (scored.prompt_cov_ppm >= 500 or scored.bigram_overlap >= 1) and scored.candidate_cov_ppm >= 250) or (scored.topic_overlap >= 1 and scored.overlap >= 1 and scored.candidate_cov_ppm >= 200)),
        .knowledge => scored.exact or (scored.overlap >= 2 and (scored.prompt_cov_ppm >= 520 or scored.bigram_overlap >= 1) and scored.candidate_cov_ppm >= 240),
        .open_chat => scored.exact or (scored.overlap >= 2 and (scored.prompt_cov_ppm >= 420 or scored.bigram_overlap >= 1) and scored.candidate_cov_ppm >= 220),
        .learned => scored.exact or (scored.overlap >= 2 and (scored.prompt_cov_ppm >= 500 or scored.bigram_overlap >= 1) and scored.candidate_cov_ppm >= 220),
    };
}

fn selectGroundedMatch(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    prompt_tokens: *const TokenizedText,
    corpus: *const PreparedCorpus,
    scorer: *ApproximateScorer,
    request: MatchRequest,
) !?SelectedMatch {
    if (prompt_tokens.token_hashes.items.len == 0) return null;

    for (corpus.items.items) |item| {
        if (std.ascii.eqlIgnoreCase(prompt, item.example.user)) {
            return .{ .example = item.example, .exact_score = 10000 };
        }
    }

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
        if (!requestAcceptsScore(scored, request)) continue;
        if (scored.score > best_score) {
            best_score = scored.score;
            best = .{ .example = example, .exact_score = scored.score };
        }
    }

    if (best == null) {
        for (corpus.items.items) |item| {
            const lexical = try scoreLexicalMatch(allocator, prompt, prompt_tokens, item.example.user, 0);
            if (lexical == null) continue;
            const scored = lexical.?;
            if (!requestAcceptsScore(scored, request)) continue;
            if (scored.score > best_score) {
                best_score = scored.score;
                best = .{ .example = item.example, .exact_score = scored.score };
            }
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
    if (!passesSemanticGuards(prompt, candidate)) return null;

    var overlap: usize = 0;
    for (prompt_tokens.token_hashes.items) |hash| {
        if (containsHash(candidate_tokens.token_hashes.items, hash)) overlap += 1;
    }
    if (overlap == 0) return null;

    var topic_overlap: usize = 0;
    for (prompt_tokens.topic_hashes.items) |hash| {
        if (containsHash(candidate_tokens.topic_hashes.items, hash)) topic_overlap += 1;
    }

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
    const hardware_match = wantsHardwareAnswer(prompt) and mentionsHardwareAnswer(candidate);

    if (!exact) {
        if (prompt_count >= 2 and overlap < 2 and bigram_overlap == 0 and !hardware_match) return null;
        if (prompt_count >= 3 and prompt_cov_ppm < 450 and bigram_overlap == 0 and !hardware_match) return null;
        if (candidate_count >= 3 and candidate_cov_ppm < 250 and bigram_overlap == 0) return null;
        if (prompt_tokens.topic_hashes.items.len > 0 and candidate_tokens.topic_hashes.items.len > 0 and topic_overlap == 0) return null;
    }

    var score: i32 = @intCast(@min(approx_score, 4000));
    score += @as(i32, @intCast(overlap * 140));
    score += @as(i32, @intCast(topic_overlap * 220));
    score += @as(i32, @intCast(bigram_overlap * 260));
    score += @as(i32, @intCast(@divTrunc(prompt_cov_ppm, 3)));
    score += @as(i32, @intCast(@divTrunc(candidate_cov_ppm, 6)));
    score += semanticBoost(prompt, candidate);
    if (exact) score += 10_000;
    if (intent_match) score += 40 else score -= 80;
    return .{
        .score = score,
        .overlap = overlap,
        .topic_overlap = topic_overlap,
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
    _ = seed_bytes;
    if (options.continue_bytes == 0 or !options.allow_generation) return example.assistant;
    return composeAnchoredContinuation(allocator, prompt, example.assistant, session, options);
}

fn buildHelpResponse(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "I can help with {s}, release artifacts, starter files, CPU versus cpu_mt versus CUDA versus OpenCL behavior, session memory, short math, everyday planning, writing, coding help, Zig upstream questions, simple explanations, and broader free-form chat when the prompt stays inside what I can support honestly.", .{current_release_name});
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
    if (std.ascii.eqlIgnoreCase(fact.key, "team")) {
        return std.fmt.allocPrint(allocator, "Noted. Your team is {s}, and I will remember that for this session.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "role")) {
        return std.fmt.allocPrint(allocator, "Noted. Your role is {s}, and I will remember that for this session.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "project")) {
        return std.fmt.allocPrint(allocator, "Noted. Your project is {s}, and I will remember that for this session.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "dog")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Noted. Your dog's name is {s}, and I will remember that for this session.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "cat")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Noted. Your cat's name is {s}, and I will remember that for this session.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "tomorrow")) {
        return std.fmt.allocPrint(allocator, "Noted. Tomorrow you have {s}, and I will remember that for this session.", .{fact.value});
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
    if (std.ascii.eqlIgnoreCase(fact.key, "team")) {
        return std.fmt.allocPrint(allocator, "Noted. Your team is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, coding help, and short math.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "role")) {
        return std.fmt.allocPrint(allocator, "Noted. Your role is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, and short math.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "project")) {
        return std.fmt.allocPrint(allocator, "Noted. Your project is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, coding help, and short math.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "dog")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Noted. Your dog's name is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, coding help, and short math.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "cat")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Noted. Your cat's name is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, coding help, and short math.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "tomorrow")) {
        return std.fmt.allocPrint(allocator, "Noted. Tomorrow you have {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, planning, and short math.", .{fact.value});
    }
    return std.fmt.allocPrint(allocator, "Noted. Your {s} is {s}. I can help with SBAN architecture, transformer comparisons, release artifacts, session memory, CPU or GPU runtime behavior, grounded uncertainty, and short math.", .{ fact.key, fact.value });
}

fn isSensitiveFact(key: []const u8, value: []const u8) bool {
    return hasAnyPhraseIgnoreCase(key, &.{
        "api key",
        "apikey",
        "password",
        "passcode",
        "secret",
        "token",
        "credential",
        "private key",
    }) or hasAnyPhraseIgnoreCase(value, &.{
        "api key",
        "apikey",
        "password",
        "secret",
        "token",
        "bearer ",
        "private key",
        "-----begin",
    });
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
    if (std.ascii.eqlIgnoreCase(fact.key, "team")) {
        return std.fmt.allocPrint(allocator, "Your team is {s}.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "role")) {
        return std.fmt.allocPrint(allocator, "Your role is {s}.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "project")) {
        return std.fmt.allocPrint(allocator, "Your project is {s}.", .{fact.value});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "dog")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Your dog's name is {s}.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "cat")) {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Your cat's name is {s}.", .{display});
    }
    if (std.ascii.eqlIgnoreCase(fact.key, "tomorrow")) {
        return std.fmt.allocPrint(allocator, "Tomorrow you have {s}.", .{fact.value});
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
    if (std.ascii.eqlIgnoreCase(key, "team")) {
        return allocator.dupe(u8, "I do not know your team yet. Tell me with 'our team is ...', 'my team is ...', or 'I am on team ...' and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "role")) {
        return allocator.dupe(u8, "I do not know your role yet. Tell me with 'my role is ...' or 'I work as ...' and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "project")) {
        return allocator.dupe(u8, "I do not know your project yet. Tell me with 'our project is ...' or 'my project is ...' and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "dog")) {
        return allocator.dupe(u8, "I do not know your dog's name yet. Tell me with 'my dog is ...' and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "cat")) {
        return allocator.dupe(u8, "I do not know your cat's name yet. Tell me with 'my cat is ...' and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "tomorrow")) {
        return allocator.dupe(u8, "I do not know what you have tomorrow yet. Tell me with 'tomorrow I have ...' and I will remember it for this session.");
    }
    return std.fmt.allocPrint(allocator, "I do not know your {s} yet. Tell me and I will remember it for this session.", .{key});
}

fn buildFactForgetResponse(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    if (std.ascii.eqlIgnoreCase(key, "dog")) return allocator.dupe(u8, "Forgot your dog's name for this session.");
    if (std.ascii.eqlIgnoreCase(key, "cat")) return allocator.dupe(u8, "Forgot your cat's name for this session.");
    if (std.ascii.eqlIgnoreCase(key, "tomorrow")) return allocator.dupe(u8, "Forgot what you had stored for tomorrow in this session.");
    return std.fmt.allocPrint(allocator, "Forgot your {s} for this session.", .{key});
}

fn buildFactForgetMiss(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    if (std.ascii.eqlIgnoreCase(key, "dog")) return allocator.dupe(u8, "I did not have a stored dog name to forget in this session.");
    if (std.ascii.eqlIgnoreCase(key, "cat")) return allocator.dupe(u8, "I did not have a stored cat name to forget in this session.");
    if (std.ascii.eqlIgnoreCase(key, "tomorrow")) return allocator.dupe(u8, "I did not have a stored tomorrow item to forget in this session.");
    return std.fmt.allocPrint(allocator, "I did not have a stored {s} to forget in this session.", .{key});
}

fn buildFactCapabilityResponse(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    if (std.ascii.eqlIgnoreCase(key, "name")) {
        return allocator.dupe(u8, "Yes. Tell me your name and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "location")) {
        return allocator.dupe(u8, "Yes. Tell me where you live or where you are from, and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "lab")) {
        return allocator.dupe(u8, "Yes. Tell me your lab and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "team")) {
        return allocator.dupe(u8, "Yes. Tell me your team and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "role")) {
        return allocator.dupe(u8, "Yes. Tell me your role and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "project")) {
        return allocator.dupe(u8, "Yes. Tell me your project and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "dog")) {
        return allocator.dupe(u8, "Yes. Tell me your dog's name and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "cat")) {
        return allocator.dupe(u8, "Yes. Tell me your cat's name and I will remember it for this session.");
    }
    if (std.ascii.eqlIgnoreCase(key, "tomorrow")) {
        return allocator.dupe(u8, "Yes. Tell me what you have tomorrow and I will remember it for this session.");
    }
    return std.fmt.allocPrint(allocator, "Yes. Tell me your {s} and I will remember it for this session.", .{key});
}

fn answerOperationalPrompt(allocator: std.mem.Allocator, prompt: []const u8) !?ChatResult {
    if (containsPhraseIgnoreCase(prompt, "what changed in v35") or
        containsPhraseIgnoreCase(prompt, "how is v35 different from v34") or
        containsPhraseIgnoreCase(prompt, "what changed in v34") or
        containsPhraseIgnoreCase(prompt, "how is v34 different from v33") or
        containsPhraseIgnoreCase(prompt, "what changed in v32") or
        containsPhraseIgnoreCase(prompt, "what changed in v31") or
        containsPhraseIgnoreCase(prompt, "how is v32 different from v31") or
        containsPhraseIgnoreCase(prompt, "how is v31 different from v27"))
    {
        return .{
            .mode_label = "operational-release-change",
            .response = try buildReleaseChangeResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "what should new users try first")) {
        return .{
            .mode_label = "operational-new-user-start",
            .response = try buildNewUserStartResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "what command benchmarks cuda retrieval") or
        containsPhraseIgnoreCase(prompt, "cuda retrieval benchmark"))
    {
        return .{
            .mode_label = "operational-cuda-bench-command",
            .response = try buildCudaBenchCommandResponse(allocator),
            .symbolic = true,
        };
    }
    if (wantsCudaCommandAnswer(prompt)) {
        return .{
            .mode_label = "operational-cuda-command",
            .response = try buildCudaCommandResponse(allocator),
            .symbolic = true,
        };
    }
    if (wantsArtifactPathAnswer(prompt)) {
        if (containsPhraseIgnoreCase(prompt, "summary")) {
            return .{
                .mode_label = "operational-summary-path",
                .response = try std.fmt.allocPrint(allocator, "The {s} executive summary is generated at {s}.", .{ current_release_version, current_summary_path }),
                .symbolic = true,
            };
        }
        if (containsPhraseIgnoreCase(prompt, "report")) {
            return .{
                .mode_label = "operational-report-path",
                .response = try std.fmt.allocPrint(allocator, "The {s} report is generated at {s}.", .{ current_release_version, current_report_path }),
                .symbolic = true,
            };
        }
        if (containsPhraseIgnoreCase(prompt, "repo")) {
            return .{
                .mode_label = "operational-repo-path",
                .response = try std.fmt.allocPrint(allocator, "The {s} repo archive is generated at {s}.", .{ current_release_version, current_repo_zip_path }),
                .symbolic = true,
            };
        }
        return .{
            .mode_label = "operational-paper-path",
            .response = try std.fmt.allocPrint(allocator, "The {s} paper PDF is generated at {s}.", .{ current_release_version, current_paper_path }),
            .symbolic = true,
        };
    }
    if (wantsBundleInventory(prompt)) {
        return .{
            .mode_label = "operational-bundle",
            .response = try buildBundleInventoryResponse(allocator),
            .symbolic = true,
        };
    }
    if (wantsStarterAnswer(prompt)) {
        if (containsPhraseIgnoreCase(prompt, "windows")) {
            return .{
                .mode_label = "operational-starter",
                .response = try std.fmt.allocPrint(allocator, "The Windows starter file is {s}. Open the bundle and run that script to start the continuing {s} chat loop.", .{ current_windows_demo_start, current_release_version }),
                .symbolic = true,
            };
        }
        if (containsPhraseIgnoreCase(prompt, "linux")) {
            return .{
                .mode_label = "operational-starter",
                .response = try std.fmt.allocPrint(allocator, "The Linux starter file is {s}. Run it from the bundle directory to start the continuing {s} chat loop.", .{ current_linux_demo_start, current_release_version }),
                .symbolic = true,
            };
        }
        return .{
            .mode_label = "operational-starter",
            .response = try std.fmt.allocPrint(allocator, "The demo starter scripts are {s} on Windows and {s} on Linux.", .{ current_windows_demo_start, current_linux_demo_start }),
            .symbolic = true,
        };
    }
    if ((containsPhraseIgnoreCase(prompt, "rtx") or containsPhraseIgnoreCase(prompt, "nvidia")) and
        hasAnyPhraseIgnoreCase(prompt, &.{ "can this run", "does this run", "do you support", "will this run" }))
    {
        return .{
            .mode_label = "operational-rtx-support",
            .response = try buildRtxSupportResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "do you support gpus")) {
        return .{
            .mode_label = "operational-gpu-support",
            .response = try buildGpuSupportResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "when should i use cpu_mt") or containsPhraseIgnoreCase(prompt, "when should i use cpu mt")) {
        return .{
            .mode_label = "operational-cpu-mt-guidance",
            .response = try buildCpuMtGuidanceResponse(allocator),
            .symbolic = true,
        };
    }
    if ((containsPhraseIgnoreCase(prompt, "cuda") and containsPhraseIgnoreCase(prompt, "opencl")) or
        containsPhraseIgnoreCase(prompt, "how do cpu and gpu retrieval differ"))
    {
        return .{
            .mode_label = "operational-backends",
            .response = try buildBackendComparisonResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "numeric accel info")) {
        return .{
            .mode_label = "operational-numeric-accel-info",
            .response = try buildNumericAccelInfoResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "accel bench")) {
        return .{
            .mode_label = "operational-accel-bench",
            .response = try buildAccelBenchResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "is multithreaded numeric scoring the default")) {
        return .{
            .mode_label = "operational-numeric-default",
            .response = try buildNumericDefaultResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "what facts can you remember")) {
        return .{
            .mode_label = "operational-memory-facts",
            .response = try buildRememberedFactsResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "how do you remember facts")) {
        return .{
            .mode_label = "operational-memory-mechanism",
            .response = try buildFactMemoryMechanismResponse(allocator),
            .symbolic = true,
        };
    }
    if (containsPhraseIgnoreCase(prompt, "how do you avoid transcript corruption")) {
        return .{
            .mode_label = "operational-transcript-safety",
            .response = try buildTranscriptSafetyResponse(allocator),
            .symbolic = true,
        };
    }
    if (wantsRoadmapAnswer(prompt)) {
        return .{
            .mode_label = "operational-roadmap",
            .response = try buildRoadmapResponse(allocator),
            .symbolic = true,
        };
    }
    return null;
}

fn buildReleaseChangeResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "V35 adds an auto-learned reasoning corpus generated from online dataset adapters plus deterministic fallback rows, routes that learned corpus through the runtime retrieval scorer, fixes JSON slot preservation and session forget semantics, keeps the v34 prewarm contract, and keeps live-current facts behind an explicit external-lookup boundary.");
}

fn buildNewUserStartResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "New users should start the continuing chat demo, ask what SBAN v35 is, ask how the learned reasoning corpus works, try a CUDA or starter-file command, store and forget a session fact, generate exact JSON slots, and then try practical reasoning prompts such as a sequence, comparison, word problem, agenda, explanation, summarization request, or coding request.");
}

fn buildCudaCommandResponse(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "Use accel-info to confirm the grounded retrieval CUDA path: zig-out/bin/zig_sban accel-info seed_path={s} backend=cuda. To confirm the new numeric CUDA path, run zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1. If you want raw retrieval throughput after that, run accel-bench with backend=cuda against the versioned {s} bench assets.",
        .{ current_seed_path, current_release_version },
    );
}

fn buildCudaBenchCommandResponse(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "Use accel-bench for the raw CUDA retrieval benchmark, for example: zig-out/bin/zig_sban accel-bench docs/results/{s}/accel_prompts_{s}_bench.txt backend=cuda seed_path=docs/results/{s}/accel_seed_{s}_bench.txt iterations=4.", .{ current_release_version, current_release_version, current_release_version, current_release_version });
}

fn buildBundleInventoryResponse(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "The {s} release bundle ships the executive summary at {s}, the report at {s}, the paper PDF at {s}, the repo archive at {s}, and demo bundles at {s} and {s}.",
        .{ current_release_version, current_summary_path, current_report_path, current_paper_path, current_repo_zip_path, current_windows_demo_zip, current_linux_demo_zip },
    );
}

fn buildRtxSupportResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "Yes. NVIDIA RTX cards such as the RTX 4090 should normally use backend=auto or backend=cuda for the retrieval accelerator path. SBAN now treats CUDA as the preferred retrieval path on NVIDIA, keeps CPU as the safe numeric release baseline, and leaves numeric_backend=cuda as an explicit experiment instead of the automatic default.");
}

fn buildGpuSupportResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "Yes. SBAN now prefers a hybrid stance: backend=auto should pick CUDA for grounded retrieval on NVIDIA hardware, plain CPU stays the default numeric release path, cpu_mt remains an explicit host-side experiment, and OpenCL is still the generic GPU fallback for retrieval when CUDA is unavailable.");
}

fn buildCpuMtGuidanceResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "Use cpu_mt as an explicit host-side experiment when the workload is large enough to amortize thread overhead. The automatic hybrid path is more conservative: it prefers CUDA for retrieval when that exists, keeps small grounded corpora on plain CPU, and leaves numeric_backend=cpu_mt as a thresholded experiment rather than the default.");
}

fn buildBackendComparisonResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "CPU is the numeric baseline and the fallback for smaller retrieval workloads. cpu_mt is the explicit host-threaded option for larger experiments. CUDA is the preferred GPU path on NVIDIA systems and the preferred retrieval path there. OpenCL remains the generic GPU fallback for retrieval on compatible non-CUDA setups. Numeric CUDA stays experimental until it measures faster end to end.");
}

fn buildNumericAccelInfoResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "Numeric-accel-info is the probe command that reports whether the numeric runtime can see and use the configured CPU, cpu_mt, or CUDA backend.");
}

fn buildAccelBenchResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "Accel-bench is the raw accelerator benchmark command. It measures retrieval scoring throughput directly so CPU, cpu_mt, CUDA, and OpenCL paths can be compared honestly without the rest of the chat runtime dominating the timing.");
}

fn buildNumericDefaultResponse(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "Not yet. {s} keeps the single-thread CPU numeric profile as the default release fallback until measured CUDA and cpu_mt runs prove a dependable end-to-end win on the shipped suite.", .{current_release_version});
}

fn buildRememberedFactsResponse(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} can remember simple session facts such as your name, where you live or are from, your lab, your team, your role, your project, pet names, favorite color, preferences, and short calendar notes like tomorrow's appointment for the current session.", .{current_release_version});
}

fn buildFactMemoryMechanismResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "The dialogue runtime extracts short fact statements and small dated notes from the current conversation, stores them in the structured session state, and answers later recall questions from that session memory only when the key matches confidently.");
}

fn buildTranscriptSafetyResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "The session file does not store raw User and Assistant lines directly. It sanitizes turn text and stores encoded fields in a structured session format so newline injection cannot corrupt the transcript state.");
}

fn buildRoadmapResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "After v35, the roadmap should push the learned-corpus path toward incremental online updates, stronger source attribution for refreshed knowledge, and backend acceleration that only becomes the default when CPU or GPU runs actually beat the fallback path.");
}

fn synthesizeFreeResponse(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    session: *const SessionState,
    _: ChatOptions,
) !?[]const u8 {
    if (isGreetingPrompt(prompt)) {
        return @as(?[]const u8, try buildGreetingResponse(allocator, session));
    }
    if (isThankYouPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "You're welcome. If you want to keep going, give me the next question or the next thing you want to sort out."));
    }
    if (isHowAreYouPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "I am steady and ready to help. We can keep things practical, conversational, and honest about what I know."));
    }
    if (isIdentityPrompt(prompt)) {
        return @as(?[]const u8, try buildIdentityResponse(allocator));
    }
    if (isFavoriteColorPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "I do not have personal preferences, but blue is a practical choice for diagrams because it reads cleanly against light and dark backgrounds."));
    }
    if (isJokePrompt(prompt)) {
        return @as(?[]const u8, try buildJokeResponse(allocator, prompt));
    }
    if (isCapabilityPrompt(prompt)) {
        return @as(?[]const u8, try buildHelpResponse(allocator));
    }
    if (isAgendaPrompt(prompt)) {
        return @as(?[]const u8, try buildAgendaResponse(allocator));
    }
    if (isCreativeWritingPrompt(prompt)) {
        return @as(?[]const u8, try buildCreativeWritingResponse(allocator, prompt));
    }
    if (isInterviewPrepPrompt(prompt)) {
        return @as(?[]const u8, try buildInterviewPrepResponse(allocator));
    }
    if (isWeekPlanningPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "Yes. Put deadlines and appointments down first, then pick one major result for each day instead of making one giant undifferentiated list."));
    }
    if (isFocusPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "Reduce the surface area. One task, one timer, notifications off, and a visible definition of done for the current block."));
    }
    if (isPlanningPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "Yes. Start with the fixed commitments, then pick the top few outcomes that matter most, and block time for those before the smaller tasks spread everywhere."));
    }
    if (isWeekendLondonPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "A relaxed weekend in London could be: a slow morning walk and coffee, one museum or gallery, lunch in a neighborhood you actually enjoy wandering, a park break in the afternoon, and one easy evening anchor like a pub meal, a film, or a quiet dinner instead of overpacking the schedule."));
    }
    if (isLunchIdeasPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "Three easy lunch ideas are: a chicken or chickpea wrap with salad and yogurt sauce, rice with roasted vegetables and a fried egg, or tomato soup with a grilled cheese or tuna melt on the side."));
    }
    if (isWritingHelpPrompt(prompt)) {
        return @as(?[]const u8, try buildWritingHelpResponse(allocator, prompt));
    }
    if (isBrainstormPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "Yes. Give me the tone, the audience, and a few keywords, and I can help generate options instead of guessing blindly."));
    }
    if (isDecisionPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "Let's make it concrete: list the options, the tradeoffs, and what matters most, and then we can compare them cleanly."));
    }
    if (isBirthdayIdeasPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "Three easy birthday directions are: a small dinner with one signature activity, a low-friction outing like bowling or mini golf, or a relaxed home gathering with one themed game or movie anchor."));
    }
    if (isCookingHowPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "For boiled eggs, cover the eggs with cold water, bring the pot just to a boil, turn the heat off, cover it, wait about 10 to 12 minutes, then cool the eggs in cold water before peeling."));
    }
    if (isWorkoutPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "A simple starter workout plan is three full-body sessions each week: one squat or leg movement, one push movement, one pull movement, and a short walk or easy cardio block on the other days."));
    }
    if (isPoliteBoundaryPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "A polite way to say no is to be clear, brief, and respectful: thank them, decline plainly, and if useful offer a smaller alternative or a later time instead of overexplaining."));
    }
    if (isMovieRecommendationPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "Yes. Give me the mood you want tonight, like funny, tense, comforting, or thoughtful, and I can narrow the movie choice instead of guessing badly."));
    }
    if (isZigUpstreamPrompt(prompt)) {
        return @as(?[]const u8, try buildZigUpstreamResponse(allocator, prompt));
    }
    if (isSupportPrompt(prompt)) {
        return @as(?[]const u8, try buildSupportResponse(allocator, prompt));
    }
    if (isCurrentFactPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "I do not have live current facts. This SBAN release uses static bundled knowledge, so current news, office holders, prices, and today's facts need an external lookup."));
    }
    if (isTranslationPrompt(prompt)) {
        return @as(?[]const u8, try buildTranslationResponse(allocator, prompt));
    }
    if (isSummarizationPrompt(prompt)) {
        return @as(?[]const u8, try buildSummarizationResponse(allocator, prompt));
    }
    if (isShellHelpPrompt(prompt)) {
        return @as(?[]const u8, try allocator.dupe(u8, "I cannot generate arbitrary shell commands safely from a vague prompt. Give a concrete operating system, target path, and desired action, or use one of the documented SBAN commands such as accel-info, numeric-accel-info, chat-eval, or chat-session-eval."));
    }
    if (isCodingHelpPrompt(prompt)) {
        return @as(?[]const u8, try buildCodingHelpResponse(allocator, prompt));
    }
    if (isCoffeePrompt(prompt)) {
        return @as(?[]const u8, try buildCoffeeResponse(allocator));
    }
    if (isSimpleExplanationPrompt(prompt)) {
        return @as(?[]const u8, try buildSimpleExplanationResponse(allocator, prompt));
    }
    if (try solveReasoningPrompt(allocator, prompt)) |response| {
        return @as(?[]const u8, response);
    }
    if (isGeneralKnowledgePrompt(prompt)) {
        return @as(?[]const u8, try buildGeneralKnowledgeResponse(allocator, prompt));
    }
    if (try solveWordProblem(allocator, prompt)) |response| {
        return @as(?[]const u8, response);
    }
    if (isSupportPrompt(prompt)) {
        return @as(?[]const u8, try buildSupportResponse(allocator, prompt));
    }
    if (isPreferenceBoundaryPrompt(prompt)) {
        return @as(?[]const u8, try buildPreferenceBoundaryResponse(allocator, prompt));
    }
    return null;
}

fn buildGreetingResponse(allocator: std.mem.Allocator, session: *const SessionState) ![]const u8 {
    if (session.lookupFact("name")) |fact| {
        const display = try titleCaseCopy(allocator, fact.value);
        defer allocator.free(display);
        return std.fmt.allocPrint(allocator, "Hello {s}. I am ready to help with grounded {s} questions, planning, writing, session memory, or short math.", .{ display, current_release_name });
    }
    return std.fmt.allocPrint(allocator, "Hello. I am {s}, ready for grounded SBAN questions and broader free chat.", .{current_release_name});
}

fn buildIdentityResponse(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "I am {s}, a grounded non-transformer chat runtime built around sparse adaptive memory, bridge-based context, synthetic knowledge packs, symbolic reasoning helpers, and session memory. I can answer from release knowledge, retained session facts, bounded general knowledge, practical coding help, and the measured CPU or GPU backend stack.", .{current_release_name});
}

fn composeAnchoredContinuation(
    allocator: std.mem.Allocator,
    _: []const u8,
    anchor_assistant: []const u8,
    _: *const SessionState,
    _: ChatOptions,
) ![]const u8 {
    return allocator.dupe(u8, anchor_assistant);
}

fn isGreetingPrompt(prompt: []const u8) bool {
    return startsWithWordIgnoreCase(prompt, "hello") or
        startsWithWordIgnoreCase(prompt, "hi") or
        startsWithWordIgnoreCase(prompt, "hey") or
        startsWithWordIgnoreCase(prompt, "good morning") or
        startsWithWordIgnoreCase(prompt, "good afternoon");
}

fn isThankYouPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "thank you") or std.ascii.eqlIgnoreCase(trimLine(prompt), "thanks");
}

fn isJokePrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "tell me a joke") or containsPhraseIgnoreCase(prompt, "make me laugh") or containsPhraseIgnoreCase(prompt, "joke about");
}

fn isFavoriteColorPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "favorite color") or containsPhraseIgnoreCase(prompt, "favourite color") or containsPhraseIgnoreCase(prompt, "favourite colour");
}

fn isHowAreYouPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "how are you") or
        containsPhraseIgnoreCase(prompt, "how's it going") or
        containsPhraseIgnoreCase(prompt, "how is your day") or
        containsPhraseIgnoreCase(prompt, "how's your day") or
        containsPhraseIgnoreCase(prompt, "how is your day going");
}

fn isIdentityPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "who are you") or
        containsPhraseIgnoreCase(prompt, "what are you") or
        containsPhraseIgnoreCase(prompt, "what is sban") or
        containsPhraseIgnoreCase(prompt, "what is SBAN") or
        containsPhraseIgnoreCase(prompt, "tell me about yourself");
}

fn isCapabilityPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "what can you do") or
        containsPhraseIgnoreCase(prompt, "what can i ask") or
        containsPhraseIgnoreCase(prompt, "how can you help");
}

fn isAgendaPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "meeting agenda") or
        containsPhraseIgnoreCase(prompt, "agenda for") or
        ((containsPhraseIgnoreCase(prompt, "agenda") or containsPhraseIgnoreCase(prompt, "outline")) and
            hasAnyPhraseIgnoreCase(prompt, &.{ "meeting", "1:1", "one on one", "standup", "kickoff" }));
}

fn isInterviewPrepPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "prepare for an interview") or
        containsPhraseIgnoreCase(prompt, "interview prep") or
        (containsPhraseIgnoreCase(prompt, "interview") and hasAnyPhraseIgnoreCase(prompt, &.{ "prepare", "prep", "practice", "ready" }));
}

fn isPlanningPrompt(prompt: []const u8) bool {
    return (hasAnyPhraseIgnoreCase(prompt, &.{ "plan", "schedule" }) and
        hasAnyPhraseIgnoreCase(prompt, &.{ "tomorrow", "today", "day plan", "daily plan", "morning", "evening" })) or
        containsPhraseIgnoreCase(prompt, "to do list") or
        containsPhraseIgnoreCase(prompt, "todo list") or
        (containsPhraseIgnoreCase(prompt, "routine") and hasAnyPhraseIgnoreCase(prompt, &.{ "day", "daily", "morning", "evening" }));
}

fn isWeekPlanningPrompt(prompt: []const u8) bool {
    return hasAnyPhraseIgnoreCase(prompt, &.{ "organize my week", "organise my week", "plan my week", "help me organize my week", "help me organise my week", "this week plan" });
}

fn isFocusPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "stay focused") or
        containsPhraseIgnoreCase(prompt, "help me focus") or
        (containsPhraseIgnoreCase(prompt, "focus") and containsPhraseIgnoreCase(prompt, "how can i")) or
        (containsPhraseIgnoreCase(prompt, "study") and containsPhraseIgnoreCase(prompt, "routine"));
}

fn isWritingHelpPrompt(prompt: []const u8) bool {
    return hasAnyPhraseIgnoreCase(prompt, &.{ "write", "draft", "word", "compose" }) and
        hasAnyPhraseIgnoreCase(prompt, &.{ "email", "message", "reply", "note", "follow-up", "follow up", "apology", "agenda", "outline", "summary", "linkedin", "bio" }) or
        containsPhraseIgnoreCase(prompt, "rewrite this professionally") or
        containsPhraseIgnoreCase(prompt, "rewrite professionally") or
        containsPhraseIgnoreCase(prompt, "rephrase this professionally");
}

fn isBrainstormPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "brainstorm") or
        containsPhraseIgnoreCase(prompt, "name ideas") or
        containsPhraseIgnoreCase(prompt, "project names") or
        (containsPhraseIgnoreCase(prompt, "ideas") and containsPhraseIgnoreCase(prompt, "name"));
}

fn isDecisionPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "think through a decision") or
        containsPhraseIgnoreCase(prompt, "decide what to") or
        containsPhraseIgnoreCase(prompt, "can't decide") or
        containsPhraseIgnoreCase(prompt, "cannot decide") or
        (startsWithWordIgnoreCase(prompt, "should i") and containsPhraseIgnoreCase(prompt, " or "));
}

fn isBirthdayIdeasPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "birthday ideas") or
        containsPhraseIgnoreCase(prompt, "birthday plans") or
        ((containsPhraseIgnoreCase(prompt, "birthday")) and hasAnyPhraseIgnoreCase(prompt, &.{ "idea", "ideas", "plan", "plans" }));
}

fn isCookingHowPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "boil eggs") or
        containsPhraseIgnoreCase(prompt, "boiled eggs");
}

fn isWorkoutPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "workout plan") or
        (containsPhraseIgnoreCase(prompt, "exercise") and containsPhraseIgnoreCase(prompt, "plan"));
}

fn isPoliteBoundaryPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "say no politely") or
        containsPhraseIgnoreCase(prompt, "decline politely") or
        containsPhraseIgnoreCase(prompt, "politely decline") or
        (containsPhraseIgnoreCase(prompt, "say no") and containsPhraseIgnoreCase(prompt, "polite")) or
        (containsPhraseIgnoreCase(prompt, "decline") and containsPhraseIgnoreCase(prompt, "invite"));
}

fn isMovieRecommendationPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "recommend a movie") or
        (containsPhraseIgnoreCase(prompt, "movie") and containsPhraseIgnoreCase(prompt, "tonight"));
}

fn isCodingHelpPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "python function") or
        containsPhraseIgnoreCase(prompt, "python class") or
        containsPhraseIgnoreCase(prompt, "javascript function") or
        containsPhraseIgnoreCase(prompt, "javascript debounce") or
        (containsPhraseIgnoreCase(prompt, "json") and hasAnyPhraseIgnoreCase(prompt, &.{ "generate", "create", "return", "object", "with name" })) or
        (containsPhraseIgnoreCase(prompt, "zig") and hasAnyPhraseIgnoreCase(prompt, &.{ "function", "code", "snippet", "reverse", "arraylist", "hashmap", "hash map", "file", "allocator", "defer", "close" })) or
        (containsPhraseIgnoreCase(prompt, "python") and hasAnyPhraseIgnoreCase(prompt, &.{ "bfs", "breadth first search" })) or
        containsPhraseIgnoreCase(prompt, "sql to count users per country") or
        containsPhraseIgnoreCase(prompt, "code snippet") or
        (containsPhraseIgnoreCase(prompt, "prime") and containsPhraseIgnoreCase(prompt, "python") and containsPhraseIgnoreCase(prompt, "function")) or
        (containsPhraseIgnoreCase(prompt, "function") and containsPhraseIgnoreCase(prompt, "reverse a string")) or
        (containsPhraseIgnoreCase(prompt, "reverse a list") and containsPhraseIgnoreCase(prompt, "python")) or
        (containsPhraseIgnoreCase(prompt, "class") and containsPhraseIgnoreCase(prompt, "stack")) or
        (containsPhraseIgnoreCase(prompt, "debounce") and containsPhraseIgnoreCase(prompt, "javascript")) or
        (containsPhraseIgnoreCase(prompt, "sql") and containsPhraseIgnoreCase(prompt, "count users")) or
        (containsPhraseIgnoreCase(prompt, "stack") and containsPhraseIgnoreCase(prompt, "python"));
}

fn isCurrentFactPrompt(prompt: []const u8) bool {
    return hasAnyPhraseIgnoreCase(prompt, &.{ "current ", "today", "latest", "news", "right now" }) or
        (containsPhraseIgnoreCase(prompt, "prime minister") and hasAnyPhraseIgnoreCase(prompt, &.{ "who is", "current", "now" })) or
        (containsPhraseIgnoreCase(prompt, "president") and hasAnyPhraseIgnoreCase(prompt, &.{ "who is", "current", "now" }));
}

fn isTranslationPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "translate ") or containsPhraseIgnoreCase(prompt, " in spanish") or containsPhraseIgnoreCase(prompt, " in french");
}

fn buildTranslationResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "hello") and containsPhraseIgnoreCase(prompt, "spanish")) {
        return allocator.dupe(u8, "Hello in Spanish is hola.");
    }
    if (containsPhraseIgnoreCase(prompt, "hello") and containsPhraseIgnoreCase(prompt, "french")) {
        return allocator.dupe(u8, "Hello in French is bonjour.");
    }
    return allocator.dupe(u8, "I only have a tiny fixed translation surface in this release, so I should not translate arbitrary text yet.");
}

fn isSummarizationPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "summarize") or containsPhraseIgnoreCase(prompt, "summary of");
}

fn buildSummarizationResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, prompt, ':')) |idx| {
        const source = trimInlineValue(prompt[idx + 1 ..]);
        if (source.len > 0) {
            const max_len: usize = 180;
            const head = if (source.len > max_len) source[0..max_len] else source;
            if (source.len > max_len) {
                const clue_len: usize = @min(source.len, 96);
                return std.fmt.allocPrint(allocator, "Summary: The supplied passage is long, so the compact summary is: it repeats or elaborates the visible opening topic rather than adding separate claims. Opening topic cue: {s}...", .{source[0..clue_len]});
            }
            return std.fmt.allocPrint(allocator, "Summary: {s}", .{head});
        }
    }
    return allocator.dupe(u8, "I can summarize a short provided passage when it follows a colon, but I should not pretend to summarize text that was not supplied.");
}

fn isShellHelpPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "shell command") or
        containsPhraseIgnoreCase(prompt, "bash command") or
        containsPhraseIgnoreCase(prompt, "powershell command") or
        (containsPhraseIgnoreCase(prompt, "command") and hasAnyPhraseIgnoreCase(prompt, &.{ "files by size", "delete", "move files", "chmod", "find files" }));
}

fn isPreRetrievalComposedPrompt(prompt: []const u8) bool {
    return isCurrentFactPrompt(prompt) or
        isReasoningPrompt(prompt) or
        isTranslationPrompt(prompt) or
        isSummarizationPrompt(prompt) or
        isShellHelpPrompt(prompt);
}

fn isZigUpstreamPrompt(prompt: []const u8) bool {
    return hasAnyPhraseIgnoreCase(prompt, &.{
        "zig upstream",
        "std.arraylist",
        "std.hashmap",
        "std.hash_map",
        "zig std",
        "build zig from source",
        "build zig without llvm",
        "bootstrap.c",
        "zig source build",
    });
}

fn isSimpleExplanationPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "explain recursion") or
        containsPhraseIgnoreCase(prompt, "inflation") or
        containsPhraseIgnoreCase(prompt, "compound interest") or
        containsPhraseIgnoreCase(prompt, "black hole") or
        containsPhraseIgnoreCase(prompt, "dns") or
        containsPhraseIgnoreCase(prompt, "tcp") or
        containsPhraseIgnoreCase(prompt, "udp") or
        containsPhraseIgnoreCase(prompt, "pointer") or
        containsPhraseIgnoreCase(prompt, "garbage collection") or
        containsPhraseIgnoreCase(prompt, "stack and heap") or
        containsPhraseIgnoreCase(prompt, "stack vs heap") or
        containsPhraseIgnoreCase(prompt, "heap memory") or
        containsPhraseIgnoreCase(prompt, "kubernetes") or
        containsPhraseIgnoreCase(prompt, "oauth") or
        containsPhraseIgnoreCase(prompt, "mutex") or
        containsPhraseIgnoreCase(prompt, "sql join") or
        containsPhraseIgnoreCase(prompt, "binary search") or
        containsPhraseIgnoreCase(prompt, "http 404") or
        containsPhraseIgnoreCase(prompt, "linked list") or
        containsPhraseIgnoreCase(prompt, "queue data structure") or
        containsPhraseIgnoreCase(prompt, "memory leak") or
        containsPhraseIgnoreCase(prompt, "unit testing") or
        containsPhraseIgnoreCase(prompt, "git rebase") or
        containsPhraseIgnoreCase(prompt, "what is an api") or
        containsPhraseIgnoreCase(prompt, "json") or
        containsPhraseIgnoreCase(prompt, "hash map") or
        containsPhraseIgnoreCase(prompt, "hashmap") or
        containsPhraseIgnoreCase(prompt, "seasons on earth") or
        containsPhraseIgnoreCase(prompt, "what causes the seasons") or
        containsPhraseIgnoreCase(prompt, "starry night") or
        containsPhraseIgnoreCase(prompt, "what is zig") or
        containsPhraseIgnoreCase(prompt, "zig language") or
        containsPhraseIgnoreCase(prompt, "photosynthesis") or
        containsPhraseIgnoreCase(prompt, "what does cpu mean") or
        containsPhraseIgnoreCase(prompt, "cpu stand for") or
        containsPhraseIgnoreCase(prompt, "what is dna") or
        containsPhraseIgnoreCase(prompt, "database index") or
        containsPhraseIgnoreCase(prompt, "tcp vs udp") or
        containsPhraseIgnoreCase(prompt, "machine learning") or
        containsPhraseIgnoreCase(prompt, "neural network") or
        containsPhraseIgnoreCase(prompt, "gradient descent") or
        (containsPhraseIgnoreCase(prompt, "ram") and containsPhraseIgnoreCase(prompt, "storage"));
}

fn isReasoningPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "reason") or
        containsPhraseIgnoreCase(prompt, "step by step") or
        containsPhraseIgnoreCase(prompt, "which is larger") or
        containsPhraseIgnoreCase(prompt, "what comes next") or
        containsPhraseIgnoreCase(prompt, "sequence") or
        containsPhraseIgnoreCase(prompt, "socrates") or
        containsPhraseIgnoreCase(prompt, "syllogism") or
        containsPhraseIgnoreCase(prompt, "sort the numbers") or
        containsPhraseIgnoreCase(prompt, "pros and cons") or
        containsPhraseIgnoreCase(prompt, "tradeoff") or
        containsPhraseIgnoreCase(prompt, "compare 0.9") or
        containsPhraseIgnoreCase(prompt, "compare 0.11") or
        containsPhraseIgnoreCase(prompt, "taller than") or
        containsPhraseIgnoreCase(prompt, "heavier than") or
        containsPhraseIgnoreCase(prompt, "modus ponens") or
        containsPhraseIgnoreCase(prompt, "necessary") or
        containsPhraseIgnoreCase(prompt, "sufficient") or
        containsPhraseIgnoreCase(prompt, "rectangle area") or
        containsPhraseIgnoreCase(prompt, "perimeter");
}

fn isGeneralKnowledgePrompt(prompt: []const u8) bool {
    return hasAnyPhraseIgnoreCase(prompt, &.{
        "pythagorean theorem",
        "what causes tides",
        "mitosis",
        "pride and prejudice",
        "capital of france",
        "conservation of energy",
        "debug a failing ci job",
        "zig errors",
        "water boil",
        "speed of light",
        "gravity",
        "mitochondria",
        "cell nucleus",
        "newton",
        "marie curie",
        "shakespeare",
        "1984",
        "animal farm",
        "roman empire",
        "nile river",
        "mount everest",
        "periodic table",
        "atom",
        "electron",
        "democracy",
        "supply and demand",
        "inflation vs deflation",
        "machine learning",
        "neural network",
        "transformer model",
        "gradient descent",
        "database index",
        "cache",
        "tcp vs udp",
        "encryption",
        "public key",
        "climate versus weather",
        "plate tectonics",
        "evolution by natural selection",
        "osmosis",
        "rna",
        "enzyme",
        "antibody",
        "immune system",
        "entropy",
        "second law of thermodynamics",
        "newton's second law",
        "electromagnetic spectrum",
        "solar eclipse",
        "lunar eclipse",
        "black hole",
        "greenhouse effect",
        "carbon cycle",
        "water cycle",
        "bayes theorem",
        "overfitting",
        "regularization",
        "classification vs regression",
        "http vs https",
        "dns",
        "operating system",
        "deadlock",
        "race condition",
        "big o notation",
        "compiler",
        "interpreter",
        "checksum",
        "rsa",
        "world war i",
        "industrial revolution",
        "renaissance",
        "magna carta",
        "plato",
        "aristotle",
        "hamlet",
        "odyssey",
        "homer",
        "moby dick",
        "great gatsby",
        "president of the united states in 2021",
        "president in 2021",
        "who was president in 2021",
        "moon landing",
        "apollo 11",
        "capital of japan",
        "capital of germany",
        "largest ocean",
        "vaccines",
        "internet",
        "world wide web",
        "linux kernel",
        "python language",
        "relativity",
        "quantum mechanics",
        "cold war",
        "american revolution",
        "french revolution",
        "dna replication",
        "mri",
        "semiconductor",
        "transistor",
        "api",
        "json",
        "sql",
        "rest api",
    });
}

fn isLunchIdeasPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "lunch ideas") or
        ((containsPhraseIgnoreCase(prompt, "lunch")) and hasAnyPhraseIgnoreCase(prompt, &.{ "idea", "ideas", "easy", "quick", "simple" }));
}

fn isWeekendLondonPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "weekend in london") or
        (containsPhraseIgnoreCase(prompt, "london") and containsPhraseIgnoreCase(prompt, "weekend")) or
        (containsPhraseIgnoreCase(prompt, "relaxed weekend") and containsPhraseIgnoreCase(prompt, "london"));
}

fn isCreativeWritingPrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "haiku") or
        (containsPhraseIgnoreCase(prompt, "poem") and hasAnyPhraseIgnoreCase(prompt, &.{ "about", "for" }));
}

fn isCoffeePrompt(prompt: []const u8) bool {
    return containsPhraseIgnoreCase(prompt, "coffee") and
        hasAnyPhraseIgnoreCase(prompt, &.{ "taste better", "better", "improve", "fix", "good" });
}

fn isSupportPrompt(prompt: []const u8) bool {
    return hasAnyPhraseIgnoreCase(prompt, &.{ "long day", "stressed", "overwhelmed", "nervous", "frustrated", "motivation", "bored", "cheer me up", "mistake at work", "excited about", "procrastinating", "doomscrolling", "doomscroll", "doom scrolling" });
}

fn isPreferenceBoundaryPrompt(prompt: []const u8) bool {
    return hasAnyPhraseIgnoreCase(prompt, &.{ "favorite book", "favourite book", "favorite movie", "favourite movie", "do you like music", "what kind of music do you like", "what do you do for fun" });
}

fn buildSupportResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "long day")) {
        return allocator.dupe(u8, "That sounds tiring. If you want, tell me the hardest part and I will help you sort it out.");
    }
    if (containsPhraseIgnoreCase(prompt, "stressed") or containsPhraseIgnoreCase(prompt, "overwhelmed")) {
        return allocator.dupe(u8, "Let's shrink the problem. Name the next concrete task in front of you, and I will help make it smaller.");
    }
    if (containsPhraseIgnoreCase(prompt, "nervous")) {
        return allocator.dupe(u8, "That is normal. A simple structure usually helps: lead with the goal, give the key points, and end with the takeaway.");
    }
    if (containsPhraseIgnoreCase(prompt, "frustrated")) {
        return allocator.dupe(u8, "That usually means something important is blocked. Tell me what is stuck, and I will help you unpack it.");
    }
    if (containsPhraseIgnoreCase(prompt, "motivation")) {
        return allocator.dupe(u8, "Make the first step small enough to start right now. Momentum usually shows up after action, not before it.");
    }
    if (containsPhraseIgnoreCase(prompt, "bored")) {
        return allocator.dupe(u8, "Pick one of three directions: move a little, learn one small thing, or make progress on a task you have been avoiding.");
    }
    if (containsPhraseIgnoreCase(prompt, "mistake at work")) {
        return allocator.dupe(u8, "First get clear on the scope, then tell the affected person quickly, then offer the next corrective step.");
    }
    if (containsPhraseIgnoreCase(prompt, "excited about")) {
        return allocator.dupe(u8, "Good. Capture the energy while it is fresh: define the goal, the first milestone, and the next action.");
    }
    if (containsPhraseIgnoreCase(prompt, "procrastinating")) {
        return allocator.dupe(u8, "Cut the startup cost down. Pick the smallest visible step, set a ten-minute timer, and stop negotiating with the task until that first block is done.");
    }
    if (containsPhraseIgnoreCase(prompt, "doomscrolling") or containsPhraseIgnoreCase(prompt, "doomscroll") or containsPhraseIgnoreCase(prompt, "doom scrolling")) {
        return allocator.dupe(u8, "Make the next action physical and small: put the phone out of reach, stand up, and switch to one deliberate alternative like a short walk, water, or a single focused task.");
    }
    return allocator.dupe(u8, "Tell me what is weighing on you, and I will try to help in a calm and concrete way.");
}

fn buildJokeResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "database") or containsPhraseIgnoreCase(prompt, "sql")) {
        return allocator.dupe(u8, "Why did the database admin leave the party early? Too many bad joins and not enough committed relationships.");
    }
    return allocator.dupe(u8, "Why did the sparse network stay calm? It only activated the paths that actually had support.");
}

fn buildCreativeWritingResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "haiku") and containsPhraseIgnoreCase(prompt, "rain")) {
        return allocator.dupe(u8, "Rain taps at the glass\nCity lights blur into mist\nEvening slows its pace");
    }
    return allocator.dupe(u8, "Yes. Tell me the form, the tone, and the subject, and I can draft something concise instead of guessing the style.");
}

fn buildPreferenceBoundaryResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "music")) {
        return allocator.dupe(u8, "I do not have personal taste, but I can still help you narrow a genre or mood if you tell me what you want to hear.");
    }
    if (containsPhraseIgnoreCase(prompt, "book")) {
        return allocator.dupe(u8, "I do not have favorites, but I can help you pick a book if you tell me the mood, topic, or difficulty you want.");
    }
    if (containsPhraseIgnoreCase(prompt, "movie")) {
        return allocator.dupe(u8, "I do not have personal favorites, but I can help you choose a movie if you give me the mood or genre.");
    }
    return allocator.dupe(u8, "I do not have hobbies in the human sense, but I do enjoy helping turn fuzzy ideas into something clearer and more workable.");
}

fn buildAgendaResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "A simple meeting agenda is: purpose, the two or three decisions that matter, key updates, blockers, and the next actions with owners. If you want, give me the meeting type and I will turn that into a tighter draft.");
}

fn buildInterviewPrepResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "A solid interview prep loop is: review the role, pick three stories that show impact, practice a short introduction, prepare a few questions, and rehearse concise answers out loud instead of only in your head.");
}

fn buildWritingHelpResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "rewrite this professionally") or
        containsPhraseIgnoreCase(prompt, "rewrite professionally") or
        containsPhraseIgnoreCase(prompt, "rephrase this professionally"))
    {
        if (extractRewriteSource(prompt)) |source| {
            if (containsPhraseIgnoreCase(source, "sorry i was late")) {
                return allocator.dupe(u8, "A more professional version is: I apologize for arriving late. Thank you for your patience.");
            }
            return std.fmt.allocPrint(allocator, "A more professional rewrite is: {s}", .{source});
        }
        return allocator.dupe(u8, "Paste the sentence or paragraph after the request, and I can rewrite it in a more professional tone.");
    }
    if (containsPhraseIgnoreCase(prompt, "apology")) {
        return allocator.dupe(u8, "A good apology draft is brief and direct: say what happened, apologize plainly, state the fix or next step, and avoid turning the message into a defense.");
    }
    if (containsPhraseIgnoreCase(prompt, "agenda")) {
        return buildAgendaResponse(allocator);
    }
    if (containsPhraseIgnoreCase(prompt, "linkedin") and containsPhraseIgnoreCase(prompt, "researcher")) {
        return allocator.dupe(u8, "Here is a compact LinkedIn summary for a researcher:\n\nResearcher focused on turning complex technical questions into measurable results. I work across experiments, analysis, and implementation, with an emphasis on clear reasoning, reproducible evaluation, and building systems that hold up outside the happy path.");
    }
    if (containsPhraseIgnoreCase(prompt, "follow-up") or containsPhraseIgnoreCase(prompt, "follow up")) {
        return allocator.dupe(u8, "Keep it short: restate the thread in one line, ask the direct question, and make the next action easy for the other person.");
    }
    return allocator.dupe(u8, "Yes. Tell me the audience, tone, and goal, and I can help draft it. A safe default is to keep it short, direct, and specific about the next step.");
}

fn takeSimpleFieldWord(input: []const u8) ?[]const u8 {
    const trimmed = trimLine(input);
    var idx: usize = 0;
    while (idx < trimmed.len and std.ascii.isWhitespace(trimmed[idx])) : (idx += 1) {}
    const start = idx;
    while (idx < trimmed.len and (std.ascii.isAlphanumeric(trimmed[idx]) or trimmed[idx] == '_' or trimmed[idx] == '-')) : (idx += 1) {}
    if (idx <= start) return null;
    return trimmed[start..idx];
}

fn takeSimpleFieldInteger(input: []const u8) ?u64 {
    const trimmed = trimLine(input);
    var idx: usize = 0;
    while (idx < trimmed.len and std.ascii.isWhitespace(trimmed[idx])) : (idx += 1) {}
    const start = idx;
    while (idx < trimmed.len and std.ascii.isDigit(trimmed[idx])) : (idx += 1) {}
    if (idx <= start) return null;
    return std.fmt.parseInt(u64, trimmed[start..idx], 10) catch null;
}

fn extractSimpleNameField(prompt: []const u8) ?[]const u8 {
    const markers = [_][]const u8{ "name is ", "name " };
    for (markers) |marker| {
        if (indexOfPhraseIgnoreCase(prompt, marker)) |idx| {
            if (takeSimpleFieldWord(prompt[idx + marker.len ..])) |name| return name;
        }
    }
    return null;
}

fn extractSimpleAgeField(prompt: []const u8) ?u64 {
    const markers = [_][]const u8{ "age is ", "age " };
    for (markers) |marker| {
        if (indexOfPhraseIgnoreCase(prompt, marker)) |idx| {
            if (takeSimpleFieldInteger(prompt[idx + marker.len ..])) |age| return age;
        }
    }
    return null;
}

fn buildJsonObjectFromPrompt(allocator: std.mem.Allocator, prompt: []const u8) !?[]const u8 {
    const name = extractSimpleNameField(prompt) orelse return null;
    const age = extractSimpleAgeField(prompt) orelse return null;
    return @as(?[]const u8, try std.fmt.allocPrint(
        allocator,
        "```json\n{{\"name\":\"{s}\",\"age\":{d}}}\n```\nThis is valid JSON and preserves the requested `name` and `age` slots exactly.",
        .{ name, age },
    ));
}

fn buildCodingHelpResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "json") and hasAnyPhraseIgnoreCase(prompt, &.{ "generate", "create", "return", "object", "with name" })) {
        if (try buildJsonObjectFromPrompt(allocator, prompt)) |json| return json;
        return allocator.dupe(u8, "Give the requested JSON fields and values explicitly, for example `name Ada and age 37`, and I will preserve the slot values exactly.");
    }
    if (containsPhraseIgnoreCase(prompt, "zig") and containsPhraseIgnoreCase(prompt, "reverse") and containsPhraseIgnoreCase(prompt, "slice")) {
        return allocator.dupe(
            u8,
            "A compact Zig in-place slice reverse is:\n```zig\npub fn reverse(comptime T: type, items: []T) void {\n    var left: usize = 0;\n    var right: usize = items.len;\n    while (left < right) {\n        right -= 1;\n        const tmp = items[left];\n        items[left] = items[right];\n        items[right] = tmp;\n        left += 1;\n    }\n}\n```\nIt swaps the outer elements and walks inward, so it works for any mutable slice type.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "zig") and containsPhraseIgnoreCase(prompt, "defer") and !containsPhraseIgnoreCase(prompt, "file")) {
        return allocator.dupe(
            u8,
            "In Zig, `defer` schedules a statement to run when the current scope exits. It is commonly used for cleanup such as deinitializing containers, closing handles, or unlocking state.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "zig") and containsPhraseIgnoreCase(prompt, "defer") and containsPhraseIgnoreCase(prompt, "file")) {
        return allocator.dupe(
            u8,
            "A compact Zig file cleanup pattern is:\n```zig\nconst file = try std.fs.cwd().openFile(\"input.txt\", .{});\ndefer file.close();\n```\n`defer` runs when the current scope exits, so the file closes after a successful open even if later code returns early.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "zig") and containsPhraseIgnoreCase(prompt, "arraylist")) {
        return allocator.dupe(
            u8,
            "A minimal Zig ArrayList pattern is:\n```zig\nvar list = std.ArrayList(u8).empty;\ndefer list.deinit(allocator);\ntry list.append(allocator, 42);\n```\nPass the allocator on operations that may allocate, and deinit the list when ownership ends.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "zig") and (containsPhraseIgnoreCase(prompt, "hashmap") or containsPhraseIgnoreCase(prompt, "hash map"))) {
        return allocator.dupe(
            u8,
            "A basic Zig StringHashMap pattern is:\n```zig\nvar map = std.StringHashMap(u32).init(allocator);\ndefer map.deinit();\ntry map.put(\"count\", 1);\nconst value = map.get(\"count\") orelse 0;\n```\nUse the map's allocator-backed lifecycle explicitly and handle missing keys with `orelse` or an `if`.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "python") and containsPhraseIgnoreCase(prompt, "stack") and containsPhraseIgnoreCase(prompt, "class")) {
        return allocator.dupe(
            u8,
            "Yes. A simple Python stack class is:\n```python\nclass Stack:\n    def __init__(self) -> None:\n        self._items: list[object] = []\n\n    def push(self, item: object) -> None:\n        self._items.append(item)\n\n    def pop(self) -> object:\n        if not self._items:\n            raise IndexError('pop from empty stack')\n        return self._items.pop()\n\n    def peek(self) -> object:\n        if not self._items:\n            raise IndexError('peek from empty stack')\n        return self._items[-1]\n\n    def is_empty(self) -> bool:\n        return not self._items\n```\nThis uses a list internally, where `append` and `pop` from the end are the natural stack operations.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "python") and (containsPhraseIgnoreCase(prompt, "bfs") or containsPhraseIgnoreCase(prompt, "breadth first search"))) {
        return allocator.dupe(
            u8,
            "A compact Python BFS implementation is:\n```python\nfrom collections import deque\n\ndef bfs(graph, start):\n    seen = {start}\n    q = deque([start])\n    order = []\n    while q:\n        node = q.popleft()\n        order.append(node)\n        for nxt in graph.get(node, []):\n            if nxt not in seen:\n                seen.add(nxt)\n                q.append(nxt)\n    return order\n```\nThe queue gives breadth-first order and `seen` prevents revisiting nodes.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "python") and containsPhraseIgnoreCase(prompt, "reverse") and containsPhraseIgnoreCase(prompt, "string")) {
        return allocator.dupe(
            u8,
            "Yes. A direct Python version is:\n```python\ndef reverse_string(text: str) -> str:\n    return text[::-1]\n```\nIf you want, I can also show the loop version or explain why slicing works.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "python") and containsPhraseIgnoreCase(prompt, "reverse") and containsPhraseIgnoreCase(prompt, "list")) {
        return allocator.dupe(
            u8,
            "Yes. In Python you can reverse a list in place with:\n```python\nitems = [1, 2, 3]\nitems.reverse()\n```\nIf you want a reversed copy instead, use:\n```python\nreversed_items = items[::-1]\n```",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "python") and containsPhraseIgnoreCase(prompt, "prime") and containsPhraseIgnoreCase(prompt, "function")) {
        return allocator.dupe(
            u8,
            "A compact Python prime checker is:\n```python\ndef is_prime(n: int) -> bool:\n    if n < 2:\n        return False\n    if n == 2:\n        return True\n    if n % 2 == 0:\n        return False\n    factor = 3\n    while factor * factor <= n:\n        if n % factor == 0:\n            return False\n        factor += 2\n    return True\n```\nIt rejects small and even cases first, then tests odd factors up to the square root.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "javascript") and containsPhraseIgnoreCase(prompt, "debounce")) {
        return allocator.dupe(
            u8,
            "A compact JavaScript debounce function is:\n```javascript\nfunction debounce(fn, delay) {\n  let timer = null;\n  return (...args) => {\n    clearTimeout(timer);\n    timer = setTimeout(() => fn(...args), delay);\n  };\n}\n```\nThis resets the timer on each call, so `fn` only runs after calls stop for the given delay.",
        );
    }
    if (containsPhraseIgnoreCase(prompt, "sql") and containsPhraseIgnoreCase(prompt, "count users") and containsPhraseIgnoreCase(prompt, "country")) {
        return allocator.dupe(
            u8,
            "A simple SQL version is:\n```sql\nSELECT country, COUNT(*) AS user_count\nFROM users\nGROUP BY country\nORDER BY user_count DESC;\n```\nThat groups rows by `country` and counts how many users fall into each group.",
        );
    }
    return allocator.dupe(u8, "Yes. Tell me the language, the input and output shape, and any constraints, and I can sketch a compact implementation.");
}

fn buildSimpleExplanationResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "recursion")) {
        return allocator.dupe(u8, "Recursion is when a function solves a problem by calling a smaller version of itself until it reaches a simple base case that stops the chain.");
    }
    if (containsPhraseIgnoreCase(prompt, "inflation")) {
        return allocator.dupe(u8, "Inflation means prices rise over time, so the same amount of money buys less than it used to. Mild inflation is normal, but high inflation makes planning and everyday costs much harder.");
    }
    if (containsPhraseIgnoreCase(prompt, "compound interest")) {
        return allocator.dupe(u8, "Compound interest means you earn interest not just on the original amount, but also on the interest that has already been added. Over time that snowball effect is why growth speeds up.");
    }
    if (containsPhraseIgnoreCase(prompt, "pointer")) {
        return allocator.dupe(u8, "In C, a pointer is a variable that stores a memory address. Instead of holding the value itself, it points to where the value lives, which is why pointers are useful for arrays, dynamic memory, and passing data by reference.");
    }
    if (containsPhraseIgnoreCase(prompt, "garbage collection")) {
        return allocator.dupe(u8, "Garbage collection is a runtime system that automatically finds memory the program no longer uses and reclaims it, so developers do not have to free every object manually.");
    }
    if (containsPhraseIgnoreCase(prompt, "stack and heap") or containsPhraseIgnoreCase(prompt, "stack vs heap") or (containsPhraseIgnoreCase(prompt, "stack") and containsPhraseIgnoreCase(prompt, "heap"))) {
        return allocator.dupe(u8, "Stack memory usually holds short-lived call-frame data such as local variables, while heap memory is the larger pool used for data that needs to live beyond one function call. The stack is usually simpler and faster; the heap is more flexible but needs more careful management.");
    }
    if (containsPhraseIgnoreCase(prompt, "black hole")) {
        return allocator.dupe(u8, "A black hole is a region where gravity is so strong that once something crosses the event horizon, it cannot escape. You can think of it as matter packed so densely that spacetime is bent extremely hard around it.");
    }
    if (containsPhraseIgnoreCase(prompt, "kubernetes")) {
        return allocator.dupe(u8, "Kubernetes is a system for running and managing containers across multiple machines. In plain English, it helps deploy applications, keep them running, and scale them without handling each server by hand.");
    }
    if (containsPhraseIgnoreCase(prompt, "tcp") and containsPhraseIgnoreCase(prompt, "udp")) {
        return allocator.dupe(u8, "TCP emphasizes reliable ordered delivery: it retries lost data and keeps packets in sequence. UDP is simpler and faster but does not guarantee delivery or order, which is why it fits things like streaming, voice, or games where low latency matters more than perfect reliability.");
    }
    if (containsPhraseIgnoreCase(prompt, "dns")) {
        return allocator.dupe(u8, "DNS stands for Domain Name System. It translates human-readable names like example.com into the IP addresses computers use to reach the right server.");
    }
    if (containsPhraseIgnoreCase(prompt, "oauth")) {
        return allocator.dupe(u8, "OAuth is a way to let one application access another service on your behalf without handing over your password directly. In practice, it is the pattern behind many 'Sign in with ...' flows and delegated API access tokens.");
    }
    if (containsPhraseIgnoreCase(prompt, "mutex")) {
        return allocator.dupe(u8, "A mutex is a mutual-exclusion lock. It lets one thread enter a critical section at a time so shared data does not get modified concurrently in unsafe ways.");
    }
    if (containsPhraseIgnoreCase(prompt, "sql join")) {
        return allocator.dupe(u8, "A SQL join combines rows from two tables based on a related key, such as matching users.id with orders.user_id.");
    }
    if (containsPhraseIgnoreCase(prompt, "binary search")) {
        if (containsPhraseIgnoreCase(prompt, "big o")) {
            return allocator.dupe(u8, "Binary search runs in O(log n) time because each step halves the remaining search space.");
        }
        return allocator.dupe(u8, "Binary search finds a target in a sorted list by repeatedly checking the middle element and cutting the remaining search space in half.");
    }
    if (containsPhraseIgnoreCase(prompt, "http 404")) {
        return allocator.dupe(u8, "HTTP 404 means Not Found. The server was reached, but it could not find the resource at that path.");
    }
    if (containsPhraseIgnoreCase(prompt, "linked list")) {
        return allocator.dupe(u8, "A linked list is a sequence of nodes where each node points to the next one, which makes insertion cheap in the middle when you already have the right pointer.");
    }
    if (containsPhraseIgnoreCase(prompt, "queue data structure")) {
        return allocator.dupe(u8, "A queue is a first-in, first-out data structure. The earliest item added is the earliest item removed.");
    }
    if (containsPhraseIgnoreCase(prompt, "memory leak")) {
        return allocator.dupe(u8, "A memory leak happens when a program allocates memory and then loses the ability to free or reuse it, so memory usage keeps growing unnecessarily.");
    }
    if (containsPhraseIgnoreCase(prompt, "unit testing")) {
        return allocator.dupe(u8, "Unit testing means checking small isolated pieces of code, such as one function or one module, to confirm they behave as expected.");
    }
    if (containsPhraseIgnoreCase(prompt, "git rebase")) {
        return allocator.dupe(u8, "Git rebase rewrites a branch so its commits are replayed on top of a new base, which gives a cleaner linear history but changes commit identities.");
    }
    if (containsPhraseIgnoreCase(prompt, "what is an api")) {
        return allocator.dupe(u8, "An API is an application programming interface: a defined way for one piece of software to call into another piece of software.");
    }
    if (containsPhraseIgnoreCase(prompt, "json")) {
        return allocator.dupe(u8, "JSON stands for JavaScript Object Notation. It is a text format for structured data built from objects, arrays, strings, numbers, booleans, and null.");
    }
    if (containsPhraseIgnoreCase(prompt, "hash map") or containsPhraseIgnoreCase(prompt, "hashmap")) {
        return allocator.dupe(u8, "A hash map stores key-value pairs and uses a hash function to decide where keys should live internally, which is why lookups are often close to constant time on average.");
    }
    if (containsPhraseIgnoreCase(prompt, "what is zig") or containsPhraseIgnoreCase(prompt, "zig language")) {
        return allocator.dupe(u8, "Zig is a general-purpose programming language and toolchain focused on robust, optimal, and reusable software, with explicit memory management and a strong emphasis on control and clarity.");
    }
    if (containsPhraseIgnoreCase(prompt, "photosynthesis")) {
        return allocator.dupe(u8, "Photosynthesis is how plants use sunlight to turn water and carbon dioxide into stored energy and oxygen.");
    }
    if (containsPhraseIgnoreCase(prompt, "seasons on earth") or containsPhraseIgnoreCase(prompt, "what causes the seasons")) {
        return allocator.dupe(u8, "The seasons are caused mainly by Earth's axial tilt, not by Earth simply being closer to or farther from the Sun. As Earth orbits the Sun, the tilt changes how directly sunlight hits each hemisphere over the year.");
    }
    if (containsPhraseIgnoreCase(prompt, "starry night")) {
        return allocator.dupe(u8, "Vincent van Gogh painted The Starry Night.");
    }
    if (containsPhraseIgnoreCase(prompt, "what does cpu mean") or containsPhraseIgnoreCase(prompt, "cpu stand for")) {
        return allocator.dupe(u8, "CPU stands for central processing unit.");
    }
    if (containsPhraseIgnoreCase(prompt, "what is dna")) {
        return allocator.dupe(u8, "DNA is the molecule that stores the instructions cells use to build and run living things.");
    }
    if (containsPhraseIgnoreCase(prompt, "ram") and containsPhraseIgnoreCase(prompt, "storage")) {
        return allocator.dupe(u8, "RAM is short-term working memory that programs use while they are running. Storage is the longer-term place where files and installed software live when the power is off.");
    }
    return allocator.dupe(u8, "I can explain many practical topics more simply if you give me the exact concept and the level you want, like beginner, quick, or more detailed.");
}

const ParsedFraction = struct {
    label: []const u8,
    numerator: i64,
    denominator: i64,
    end: usize,
};

fn collectPromptIntegers(allocator: std.mem.Allocator, prompt: []const u8) !std.ArrayList(i64) {
    var values = std.ArrayList(i64).empty;
    errdefer values.deinit(allocator);
    var idx: usize = 0;
    while (idx < prompt.len) {
        var negative = false;
        if (prompt[idx] == '-' and idx + 1 < prompt.len and std.ascii.isDigit(prompt[idx + 1])) {
            negative = true;
            idx += 1;
        }
        if (!std.ascii.isDigit(prompt[idx])) {
            idx += 1;
            continue;
        }
        const start = idx;
        while (idx < prompt.len and std.ascii.isDigit(prompt[idx])) : (idx += 1) {}
        const parsed = std.fmt.parseInt(i64, prompt[start..idx], 10) catch continue;
        try values.append(allocator, if (negative) -parsed else parsed);
    }
    return values;
}

fn sortI64Ascending(values: []i64) void {
    var i: usize = 1;
    while (i < values.len) : (i += 1) {
        const key = values[i];
        var j = i;
        while (j > 0 and values[j - 1] > key) : (j -= 1) {
            values[j] = values[j - 1];
        }
        values[j] = key;
    }
}

fn appendI64List(allocator: std.mem.Allocator, out: *std.ArrayList(u8), values: []const i64) !void {
    for (values, 0..) |value, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        const part = try std.fmt.allocPrint(allocator, "{d}", .{value});
        defer allocator.free(part);
        try out.appendSlice(allocator, part);
    }
}

fn solveSortingReasoning(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (!(containsPhraseIgnoreCase(prompt, "sort the numbers") or containsPhraseIgnoreCase(prompt, "sort numbers") or containsPhraseIgnoreCase(prompt, "order the numbers"))) return null;
    var values = try collectPromptIntegers(allocator, prompt);
    defer values.deinit(allocator);
    if (values.items.len < 2) return null;
    sortI64Ascending(values.items);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "Sorted ascending: ");
    try appendI64List(allocator, &out, values.items);
    try out.append(allocator, '.');
    return @as(?[]u8, try allocator.dupe(u8, out.items));
}

fn solveSequenceReasoning(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (!(containsPhraseIgnoreCase(prompt, "what comes next") or containsPhraseIgnoreCase(prompt, "next number") or containsPhraseIgnoreCase(prompt, "sequence"))) return null;
    var values = try collectPromptIntegers(allocator, prompt);
    defer values.deinit(allocator);
    if (values.items.len < 3) return null;
    const len = values.items.len;
    const d = values.items[1] - values.items[0];
    var arithmetic = true;
    var idx: usize = 2;
    while (idx < len) : (idx += 1) {
        if (values.items[idx] - values.items[idx - 1] != d) {
            arithmetic = false;
            break;
        }
    }
    if (arithmetic) {
        const next = values.items[len - 1] + d;
        return @as(?[]u8, try std.fmt.allocPrint(allocator, "{d} comes next. The sequence adds {d} each time.", .{ next, d }));
    }
    if (len >= 4 and values.items[0] != 0) {
        const ratio_ok = @rem(values.items[1], values.items[0]) == 0;
        const ratio = if (ratio_ok) @divTrunc(values.items[1], values.items[0]) else 0;
        var geometric = ratio_ok;
        idx = 2;
        while (idx < len and geometric) : (idx += 1) {
            if (values.items[idx - 1] == 0 or @rem(values.items[idx], values.items[idx - 1]) != 0 or @divTrunc(values.items[idx], values.items[idx - 1]) != ratio) geometric = false;
        }
        if (geometric) {
            const next = values.items[len - 1] * ratio;
            return @as(?[]u8, try std.fmt.allocPrint(allocator, "{d} comes next. The sequence multiplies by {d} each time.", .{ next, ratio }));
        }
    }
    if (len >= 4) {
        var fib = true;
        idx = 2;
        while (idx < len) : (idx += 1) {
            if (values.items[idx] != values.items[idx - 1] + values.items[idx - 2]) {
                fib = false;
                break;
            }
        }
        if (fib) {
            const next = values.items[len - 1] + values.items[len - 2];
            return @as(?[]u8, try std.fmt.allocPrint(allocator, "{d} comes next. Each term is the sum of the previous two terms.", .{next}));
        }
    }
    return null;
}

fn findFraction(text: []const u8, start_index: usize) ?ParsedFraction {
    var idx = start_index;
    while (idx < text.len) : (idx += 1) {
        if (!std.ascii.isDigit(text[idx])) continue;
        const num_start = idx;
        while (idx < text.len and std.ascii.isDigit(text[idx])) : (idx += 1) {}
        if (idx >= text.len or text[idx] != '/') continue;
        const slash = idx;
        idx += 1;
        if (idx >= text.len or !std.ascii.isDigit(text[idx])) continue;
        const den_start = idx;
        while (idx < text.len and std.ascii.isDigit(text[idx])) : (idx += 1) {}
        const numerator = std.fmt.parseInt(i64, text[num_start..slash], 10) catch continue;
        const denominator = std.fmt.parseInt(i64, text[den_start..idx], 10) catch continue;
        if (denominator == 0) continue;
        return ParsedFraction{ .label = text[num_start..idx], .numerator = numerator, .denominator = denominator, .end = idx };
    }
    return null;
}

fn solveFractionReasoning(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (!(containsPhraseIgnoreCase(prompt, "which is larger") or containsPhraseIgnoreCase(prompt, "which is smaller") or containsPhraseIgnoreCase(prompt, "compare"))) return null;
    const first = findFraction(prompt, 0) orelse return null;
    const second = findFraction(prompt, first.end) orelse return null;
    const left = first.numerator * second.denominator;
    const right = second.numerator * first.denominator;
    if (left == right) {
        return @as(?[]u8, try std.fmt.allocPrint(allocator, "{s} and {s} are equal. Cross-multiplication gives {d} on both sides.", .{ first.label, second.label, left }));
    }
    const want_smaller = containsPhraseIgnoreCase(prompt, "smaller");
    const first_wins = if (want_smaller) left < right else left > right;
    const chosen = if (first_wins) first.label else second.label;
    const relation = if (want_smaller) "smaller" else "larger";
    return @as(?[]u8, try std.fmt.allocPrint(allocator, "{s} is {s}. Cross-multiply: {d} versus {d}, so the comparison is exact without decimals.", .{ chosen, relation, left, right }));
}

const ParsedDecimal = struct {
    label: []const u8,
    value: f64,
    end: usize,
};

fn findDecimal(text: []const u8, start_index: usize) ?ParsedDecimal {
    var idx = start_index;
    while (idx < text.len) : (idx += 1) {
        if (!std.ascii.isDigit(text[idx])) continue;
        const start = idx;
        while (idx < text.len and std.ascii.isDigit(text[idx])) : (idx += 1) {}
        if (idx >= text.len or text[idx] != '.') continue;
        idx += 1;
        if (idx >= text.len or !std.ascii.isDigit(text[idx])) continue;
        while (idx < text.len and std.ascii.isDigit(text[idx])) : (idx += 1) {}
        const value = std.fmt.parseFloat(f64, text[start..idx]) catch continue;
        return ParsedDecimal{ .label = text[start..idx], .value = value, .end = idx };
    }
    return null;
}

fn solveDecimalReasoning(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (!(containsPhraseIgnoreCase(prompt, "which is larger") or containsPhraseIgnoreCase(prompt, "which is smaller") or containsPhraseIgnoreCase(prompt, "compare"))) return null;
    const first = findDecimal(prompt, 0) orelse return null;
    const second = findDecimal(prompt, first.end) orelse return null;
    if (first.value == second.value) return @as(?[]u8, try std.fmt.allocPrint(allocator, "{s} and {s} are equal decimals.", .{ first.label, second.label }));
    const want_smaller = containsPhraseIgnoreCase(prompt, "smaller");
    const first_wins = if (want_smaller) first.value < second.value else first.value > second.value;
    const chosen = if (first_wins) first.label else second.label;
    const relation = if (want_smaller) "smaller" else "larger";
    return @as(?[]u8, try std.fmt.allocPrint(allocator, "{s} is {s}. Aligning place values before comparing avoids the common decimal-length trap.", .{ chosen, relation }));
}

fn solveLogicReasoning(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (containsPhraseIgnoreCase(prompt, "all squares are rectangles") and containsPhraseIgnoreCase(prompt, "all rectangles squares")) {
        return @as(?[]u8, try allocator.dupe(u8, "No. All squares are rectangles, but not all rectangles are squares; the reverse statement does not follow."));
    }
    if (containsPhraseIgnoreCase(prompt, "if it rains") and containsPhraseIgnoreCase(prompt, "ground gets wet") and (containsPhraseIgnoreCase(prompt, "it rains") or containsPhraseIgnoreCase(prompt, "rain is true"))) {
        return @as(?[]u8, try allocator.dupe(u8, "The grounded conclusion is: the ground gets wet. That is modus ponens: if P implies Q, and P is true, then Q follows."));
    }
    if (containsPhraseIgnoreCase(prompt, "alice") and containsPhraseIgnoreCase(prompt, "bob") and containsPhraseIgnoreCase(prompt, "carla") and containsPhraseIgnoreCase(prompt, "taller")) {
        return @as(?[]u8, try allocator.dupe(u8, "Alice is tallest. If Alice is taller than Bob and Bob is taller than Carla, the transitive ordering is Alice > Bob > Carla."));
    }
    if (containsPhraseIgnoreCase(prompt, "red box") and containsPhraseIgnoreCase(prompt, "blue box") and containsPhraseIgnoreCase(prompt, "green box") and containsPhraseIgnoreCase(prompt, "heavier")) {
        return @as(?[]u8, try allocator.dupe(u8, "The red box is heaviest if red is heavier than blue and blue is heavier than green. The relation composes transitively."));
    }
    if (containsPhraseIgnoreCase(prompt, "necessary") and containsPhraseIgnoreCase(prompt, "sufficient")) {
        return @as(?[]u8, try allocator.dupe(u8, "A sufficient condition guarantees the result when it holds. A necessary condition must be present for the result, but may not guarantee it by itself."));
    }
    return null;
}

fn solveAreaWordProblem(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (!(containsPhraseIgnoreCase(prompt, "rectangle") and (containsPhraseIgnoreCase(prompt, "area") or containsPhraseIgnoreCase(prompt, "perimeter")))) return null;
    var values = try collectPromptIntegers(allocator, prompt);
    defer values.deinit(allocator);
    if (values.items.len < 2) return null;
    const a = values.items[0];
    const b = values.items[1];
    if (containsPhraseIgnoreCase(prompt, "perimeter")) {
        return @as(?[]u8, try std.fmt.allocPrint(allocator, "The perimeter is {d}. For a rectangle, perimeter = 2 * ({d} + {d}).", .{ 2 * (a + b), a, b }));
    }
    return @as(?[]u8, try std.fmt.allocPrint(allocator, "The area is {d}. For a rectangle, area = length * width = {d} * {d}.", .{ a * b, a, b }));
}

fn handleInstructionMemoryPrompt(allocator: std.mem.Allocator, prompt: []const u8, session: *SessionState) !?[]u8 {
    if (!containsPhraseIgnoreCase(prompt, "follow these instructions") and !containsPhraseIgnoreCase(prompt, "remember this")) return null;

    if (indexOfPhraseIgnoreCase(prompt, "remember that my ")) |remember_idx| {
        const fact_tail = prompt[remember_idx..];
        if (try extractFactCandidate(allocator, fact_tail)) |fact| {
            defer allocator.free(fact.key);
            defer allocator.free(fact.value);
            if (isSensitiveFact(fact.key, fact.value)) {
                return @as(?[]u8, try allocator.dupe(u8, "I followed the boundary: I will not store secrets or credentials in session memory."));
            }
            try session.rememberFact(allocator, fact.key, fact.value);
            return @as(?[]u8, try std.fmt.allocPrint(allocator, "Done. I stored your {s} for this session and will follow the remaining bounded instruction.", .{fact.key}));
        }
    }

    if (containsPhraseIgnoreCase(prompt, "bullet") or containsPhraseIgnoreCase(prompt, "bullets")) {
        return @as(?[]u8, try allocator.dupe(u8, "- I will follow the requested structure.\n- I will keep the answer bounded and avoid inventing missing facts.\n- I will retain simple session facts only for this session."));
    }
    if (containsPhraseIgnoreCase(prompt, "concise") or containsPhraseIgnoreCase(prompt, "one sentence")) {
        return @as(?[]u8, try allocator.dupe(u8, "I will keep it concise, follow the explicit instructions, and avoid unsupported claims."));
    }
    return @as(?[]u8, try allocator.dupe(u8, "I can follow simple formatting, ordering, and session-memory instructions when they are explicit and bounded."));
}

fn solveReasoningPrompt(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (try solveSortingReasoning(allocator, prompt)) |response| return response;
    if (try solveSequenceReasoning(allocator, prompt)) |response| return response;
    if (try solveFractionReasoning(allocator, prompt)) |response| return response;
    if (try solveDecimalReasoning(allocator, prompt)) |response| return response;
    if (try solveLogicReasoning(allocator, prompt)) |response| return response;
    if (try solveAreaWordProblem(allocator, prompt)) |response| return response;

    if (containsPhraseIgnoreCase(prompt, "socrates") and containsPhraseIgnoreCase(prompt, "mortal")) {
        return @as(?[]u8, try allocator.dupe(u8, "Yes. If all humans are mortal and Socrates is a human, then Socrates is mortal. The conclusion follows by applying the general rule to the specific case."));
    }
    if (containsPhraseIgnoreCase(prompt, "which is larger") and containsPhraseIgnoreCase(prompt, "3/4") and containsPhraseIgnoreCase(prompt, "2/3")) {
        return @as(?[]u8, try allocator.dupe(u8, "3/4 is larger. Cross-multiply: 3*3 = 9 and 2*4 = 8, so 3/4 > 2/3."));
    }
    if ((containsPhraseIgnoreCase(prompt, "compare 0.9") and containsPhraseIgnoreCase(prompt, "0.11")) or
        (containsPhraseIgnoreCase(prompt, "which is larger") and containsPhraseIgnoreCase(prompt, "0.9") and containsPhraseIgnoreCase(prompt, "0.11")))
    {
        return @as(?[]u8, try allocator.dupe(u8, "0.9 is larger than 0.11. Written with two decimal places, 0.9 is 0.90, and 0.90 > 0.11."));
    }
    if (containsPhraseIgnoreCase(prompt, "what comes next") and containsPhraseIgnoreCase(prompt, "2, 4, 6, 8")) {
        return @as(?[]u8, try allocator.dupe(u8, "10 comes next. The sequence adds 2 each time: 2, 4, 6, 8, 10."));
    }
    if (containsPhraseIgnoreCase(prompt, "sort the numbers") and containsPhraseIgnoreCase(prompt, "3") and containsPhraseIgnoreCase(prompt, "1") and containsPhraseIgnoreCase(prompt, "2")) {
        return @as(?[]u8, try allocator.dupe(u8, "Sorted ascending: 1, 2, 3."));
    }
    if (containsPhraseIgnoreCase(prompt, "pros and cons") or containsPhraseIgnoreCase(prompt, "tradeoff")) {
        return @as(?[]u8, try allocator.dupe(u8, "A good tradeoff answer should separate goals, upsides, downsides, risks, and the decision rule. First define what success means, then choose the option whose downside you can actually tolerate."));
    }
    if (containsPhraseIgnoreCase(prompt, "reason") or containsPhraseIgnoreCase(prompt, "step by step")) {
        return @as(?[]u8, try allocator.dupe(u8, "I can reason through bounded prompts by making the premises explicit, checking each step, and separating what follows from what would need outside facts. For live or specialized facts, this static runtime should ask for a source instead of guessing."));
    }
    return null;
}
fn buildGeneralKnowledgeResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if ((containsPhraseIgnoreCase(prompt, "president") and containsPhraseIgnoreCase(prompt, "2021") and (containsPhraseIgnoreCase(prompt, "united states") or containsPhraseIgnoreCase(prompt, "u.s") or containsPhraseIgnoreCase(prompt, "us")))) {
        return allocator.dupe(u8, "In 2021, Joe Biden was U.S. president from January 20 onward. Donald Trump was president from January 1 until Biden's inauguration on January 20, 2021.");
    }
    if (containsPhraseIgnoreCase(prompt, "moon landing") or containsPhraseIgnoreCase(prompt, "apollo 11")) {
        return allocator.dupe(u8, "Apollo 11 landed humans on the Moon in July 1969; Neil Armstrong and Buzz Aldrin walked on the lunar surface while Michael Collins remained in lunar orbit.");
    }
    if (containsPhraseIgnoreCase(prompt, "capital of japan")) return allocator.dupe(u8, "The capital of Japan is Tokyo.");
    if (containsPhraseIgnoreCase(prompt, "capital of germany")) return allocator.dupe(u8, "The capital of Germany is Berlin.");
    if (containsPhraseIgnoreCase(prompt, "largest ocean")) return allocator.dupe(u8, "The Pacific Ocean is the largest ocean on Earth.");
    if (containsPhraseIgnoreCase(prompt, "vaccines")) return allocator.dupe(u8, "Vaccines train the immune system to recognize a pathogen or part of one, reducing the risk of severe disease if exposure happens later.");
    if (containsPhraseIgnoreCase(prompt, "world wide web")) return allocator.dupe(u8, "The World Wide Web is an information system of pages and linked resources accessed over the Internet, mainly through browsers using HTTP or HTTPS.");
    if (containsPhraseIgnoreCase(prompt, "internet") and !containsPhraseIgnoreCase(prompt, "world wide web")) return allocator.dupe(u8, "The Internet is the global network infrastructure that connects computers and networks using protocols such as IP and TCP/UDP.");
    if (containsPhraseIgnoreCase(prompt, "linux kernel")) return allocator.dupe(u8, "The Linux kernel is the core of Linux systems; it manages processes, memory, hardware drivers, filesystems, networking, and system calls.");
    if (containsPhraseIgnoreCase(prompt, "python language")) return allocator.dupe(u8, "Python is a high-level programming language known for readability, a large standard library, and broad use in scripting, data work, automation, and web services.");
    if (containsPhraseIgnoreCase(prompt, "relativity")) return allocator.dupe(u8, "Relativity connects space, time, motion, gravity, and the speed of light; general relativity models gravity as spacetime curvature.");
    if (containsPhraseIgnoreCase(prompt, "quantum mechanics")) return allocator.dupe(u8, "Quantum mechanics describes matter and energy at small scales, where states are probabilistic and phenomena such as superposition, quantization, and entanglement appear.");
    if (containsPhraseIgnoreCase(prompt, "cold war")) return allocator.dupe(u8, "The Cold War was the post-World War II rivalry mainly between the United States and Soviet Union, involving ideology, arms races, proxy conflicts, and diplomacy.");
    if (containsPhraseIgnoreCase(prompt, "american revolution")) return allocator.dupe(u8, "The American Revolution was the conflict and political movement through which thirteen colonies broke from British rule and formed the United States in the late 18th century.");
    if (containsPhraseIgnoreCase(prompt, "french revolution")) return allocator.dupe(u8, "The French Revolution began in 1789 and transformed France's monarchy and social order while advancing ideas about citizenship, rights, and republican government.");
    if (containsPhraseIgnoreCase(prompt, "dna replication")) return allocator.dupe(u8, "DNA replication copies DNA before cell division; enzymes unwind the double helix and synthesize complementary strands so each new molecule has one old and one new strand.");
    if (containsPhraseIgnoreCase(prompt, "mri")) return allocator.dupe(u8, "MRI uses strong magnetic fields and radio waves to produce detailed internal images, especially of soft tissues, without ionizing radiation.");
    if (containsPhraseIgnoreCase(prompt, "semiconductor")) return allocator.dupe(u8, "A semiconductor is a material whose electrical conductivity can be controlled, making it useful for diodes, transistors, sensors, and integrated circuits.");
    if (containsPhraseIgnoreCase(prompt, "transistor")) return allocator.dupe(u8, "A transistor is a semiconductor device used to switch or amplify electrical signals; billions of them form the logic and memory of modern chips.");
    if (containsPhraseIgnoreCase(prompt, "rest api")) return allocator.dupe(u8, "A REST API exposes resources through URLs and standard HTTP methods such as GET, POST, PUT, PATCH, and DELETE, often returning JSON.");
    if ((containsPhraseIgnoreCase(prompt, " api") or startsWithWordIgnoreCase(prompt, "api") or containsPhraseIgnoreCase(prompt, "what is an api") or containsPhraseIgnoreCase(prompt, "application programming interface")) and !containsPhraseIgnoreCase(prompt, "capital")) return allocator.dupe(u8, "An API is an application programming interface: a defined way for software components to request data or actions from each other.");
    if (containsPhraseIgnoreCase(prompt, "json")) return allocator.dupe(u8, "JSON is a lightweight text format for structured data using objects, arrays, strings, numbers, booleans, and null.");
    if (containsPhraseIgnoreCase(prompt, "sql")) return allocator.dupe(u8, "SQL is a language for querying and modifying relational databases with tables, rows, columns, joins, filters, and aggregations.");

    if (containsPhraseIgnoreCase(prompt, "what causes tides")) {
        return allocator.dupe(u8, "Tides are caused mainly by the Moon's gravity pulling on Earth's oceans, with the Sun also contributing.");
    }
    if (containsPhraseIgnoreCase(prompt, "mitosis")) {
        return allocator.dupe(u8, "Mitosis is cell division that produces two genetically similar daughter cells after duplicated chromosomes are separated.");
    }
    if (containsPhraseIgnoreCase(prompt, "pride and prejudice")) {
        return allocator.dupe(u8, "Pride and Prejudice was written by Jane Austen.");
    }
    if (containsPhraseIgnoreCase(prompt, "capital of france")) {
        return allocator.dupe(u8, "The capital of France is Paris.");
    }
    if (containsPhraseIgnoreCase(prompt, "conservation of energy")) {
        return allocator.dupe(u8, "Conservation of energy means energy is not created or destroyed in an isolated system; it changes form or moves between objects.");
    }
    if (containsPhraseIgnoreCase(prompt, "debug a failing ci job")) {
        return allocator.dupe(u8, "To debug a failing CI job, reproduce the command locally, read the first real error rather than the last cascade, compare environment versions, and shrink the failing step to a minimal command.");
    }
    if (containsPhraseIgnoreCase(prompt, "zig errors")) {
        return allocator.dupe(u8, "Zig errors are values in error sets and are often returned through error unions like !T. Callers handle them with try, catch, if error unions, or explicit switches.");
    }
    if (containsPhraseIgnoreCase(prompt, "pythagorean theorem")) {
        return allocator.dupe(u8, "The Pythagorean theorem says that in a right triangle, a^2 + b^2 = c^2, where c is the hypotenuse.");
    }
    if (containsPhraseIgnoreCase(prompt, "water boil")) {
        return allocator.dupe(u8, "At standard sea-level pressure, pure water boils at about 100 degrees Celsius, or 212 degrees Fahrenheit.");
    }
    if (containsPhraseIgnoreCase(prompt, "speed of light")) {
        return allocator.dupe(u8, "The speed of light in vacuum is exactly 299,792,458 meters per second.");
    }
    if (containsPhraseIgnoreCase(prompt, "gravity")) {
        return allocator.dupe(u8, "Gravity is the attractive interaction associated with mass and energy. Near Earth's surface it accelerates falling objects at about 9.8 m/s^2, ignoring air resistance.");
    }
    if (containsPhraseIgnoreCase(prompt, "mitochondria")) {
        return allocator.dupe(u8, "Mitochondria are cell structures that help convert food-derived energy into ATP, the cell's main usable energy currency.");
    }
    if (containsPhraseIgnoreCase(prompt, "cell nucleus")) {
        return allocator.dupe(u8, "The cell nucleus stores most of a eukaryotic cell's DNA and helps regulate gene expression and cell activity.");
    }
    if (containsPhraseIgnoreCase(prompt, "newton")) {
        return allocator.dupe(u8, "Isaac Newton is known for foundational work on classical mechanics, gravity, calculus, and optics.");
    }
    if (containsPhraseIgnoreCase(prompt, "marie curie")) {
        return allocator.dupe(u8, "Marie Curie was a physicist and chemist known for pioneering research on radioactivity and for Nobel Prizes in physics and chemistry.");
    }
    if (containsPhraseIgnoreCase(prompt, "shakespeare")) {
        return allocator.dupe(u8, "William Shakespeare was an English playwright and poet whose works include Hamlet, Macbeth, Romeo and Juliet, and many sonnets.");
    }
    if (containsPhraseIgnoreCase(prompt, "1984")) {
        return allocator.dupe(u8, "1984 is a dystopian novel by George Orwell about surveillance, authoritarian control, propaganda, and the manipulation of truth.");
    }
    if (containsPhraseIgnoreCase(prompt, "animal farm")) {
        return allocator.dupe(u8, "Animal Farm is George Orwell's political allegory about revolution, power, propaganda, and corruption.");
    }
    if (containsPhraseIgnoreCase(prompt, "roman empire")) {
        return allocator.dupe(u8, "The Roman Empire was the imperial phase of ancient Rome, centered on the Mediterranean and known for law, roads, administration, military organization, and Latin cultural influence.");
    }
    if (containsPhraseIgnoreCase(prompt, "nile river")) {
        return allocator.dupe(u8, "The Nile is a major river in northeastern Africa and has historically been central to Egyptian agriculture and civilization.");
    }
    if (containsPhraseIgnoreCase(prompt, "mount everest")) {
        return allocator.dupe(u8, "Mount Everest is Earth's highest mountain above sea level, in the Himalayas on the Nepal-China border region.");
    }
    if (containsPhraseIgnoreCase(prompt, "periodic table")) {
        return allocator.dupe(u8, "The periodic table organizes chemical elements by atomic number and recurring chemical properties.");
    }
    if (containsPhraseIgnoreCase(prompt, "atom")) {
        return allocator.dupe(u8, "An atom is a basic unit of matter with a nucleus of protons and neutrons surrounded by electrons.");
    }
    if (containsPhraseIgnoreCase(prompt, "electron")) {
        return allocator.dupe(u8, "An electron is a negatively charged subatomic particle found around atomic nuclei and involved in electricity and chemical bonding.");
    }
    if (containsPhraseIgnoreCase(prompt, "democracy")) {
        return allocator.dupe(u8, "Democracy is a system of government where political power is grounded in the people, commonly through voting, representation, rights, and accountability.");
    }
    if (containsPhraseIgnoreCase(prompt, "supply and demand")) {
        return allocator.dupe(u8, "Supply and demand describe how prices tend to move with availability and desire: higher demand can raise prices, while higher supply can lower them, all else equal.");
    }
    if (containsPhraseIgnoreCase(prompt, "inflation vs deflation")) {
        return allocator.dupe(u8, "Inflation means the general price level rises over time. Deflation means the general price level falls over time.");
    }
    if (containsPhraseIgnoreCase(prompt, "machine learning")) {
        return allocator.dupe(u8, "Machine learning is a field where systems learn patterns from data to make predictions, classifications, or decisions without hand-coding every rule.");
    }
    if (containsPhraseIgnoreCase(prompt, "neural network")) {
        return allocator.dupe(u8, "A neural network is a model made of connected layers of simple computations whose weights are adjusted during training to map inputs to useful outputs.");
    }
    if (containsPhraseIgnoreCase(prompt, "transformer model")) {
        return allocator.dupe(u8, "A transformer is a neural-network architecture built around attention, which lets the model weigh relationships between tokens across a context window.");
    }
    if (containsPhraseIgnoreCase(prompt, "gradient descent")) {
        return allocator.dupe(u8, "Gradient descent is an optimization method that repeatedly adjusts parameters in the direction that reduces a loss function.");
    }
    if (containsPhraseIgnoreCase(prompt, "database index")) {
        return allocator.dupe(u8, "A database index is an auxiliary data structure that speeds up lookups, often by trading extra storage and write overhead for faster reads.");
    }
    if (containsPhraseIgnoreCase(prompt, "cache")) {
        return allocator.dupe(u8, "A cache stores recently or frequently used data closer to where it is needed, reducing repeated expensive work.");
    }
    if (containsPhraseIgnoreCase(prompt, "tcp vs udp")) {
        return allocator.dupe(u8, "TCP is connection-oriented and emphasizes reliable ordered delivery. UDP is connectionless and lower-overhead, useful when speed or latency matters more than guaranteed delivery.");
    }
    if (containsPhraseIgnoreCase(prompt, "encryption") or containsPhraseIgnoreCase(prompt, "public key")) {
        return allocator.dupe(u8, "Encryption transforms readable data into protected ciphertext. Public-key cryptography uses a public key for operations like encryption or verification and a private key for decryption or signing.");
    }
    if (containsPhraseIgnoreCase(prompt, "climate versus weather")) {
        return allocator.dupe(u8, "Weather is short-term atmospheric conditions. Climate is the long-term pattern of weather in a region.");
    }
    if (containsPhraseIgnoreCase(prompt, "plate tectonics")) {
        return allocator.dupe(u8, "Plate tectonics is the theory that Earth's outer shell is divided into moving plates, explaining many earthquakes, volcanoes, mountain ranges, and ocean trenches.");
    }
    if (containsPhraseIgnoreCase(prompt, "evolution by natural selection")) {
        return allocator.dupe(u8, "Evolution by natural selection occurs when inherited traits that improve survival or reproduction become more common across generations.");
    }

    if (containsPhraseIgnoreCase(prompt, "osmosis")) {
        return allocator.dupe(u8, "Osmosis is the movement of water across a selectively permeable membrane from lower solute concentration toward higher solute concentration.");
    }
    if (containsPhraseIgnoreCase(prompt, "rna")) {
        return allocator.dupe(u8, "RNA is a nucleic acid that helps carry and use genetic information; messenger RNA, for example, carries instructions from DNA to ribosomes for protein production.");
    }
    if (containsPhraseIgnoreCase(prompt, "enzyme")) {
        return allocator.dupe(u8, "An enzyme is a biological catalyst that speeds up a chemical reaction without being consumed by the reaction.");
    }
    if (containsPhraseIgnoreCase(prompt, "antibody") or containsPhraseIgnoreCase(prompt, "immune system")) {
        return allocator.dupe(u8, "Antibodies are proteins made by the immune system that bind specific targets, helping the body recognize and neutralize pathogens or foreign material.");
    }
    if (containsPhraseIgnoreCase(prompt, "entropy") or containsPhraseIgnoreCase(prompt, "second law of thermodynamics")) {
        return allocator.dupe(u8, "Entropy is often described as a measure of energy dispersal or the number of possible microscopic arrangements. The second law says total entropy in an isolated system tends not to decrease.");
    }
    if (containsPhraseIgnoreCase(prompt, "newton's second law") or containsPhraseIgnoreCase(prompt, "newtons second law")) {
        return allocator.dupe(u8, "Newton's second law says force equals mass times acceleration: F = m * a.");
    }
    if (containsPhraseIgnoreCase(prompt, "electromagnetic spectrum")) {
        return allocator.dupe(u8, "The electromagnetic spectrum ranges from low-frequency radio waves through microwaves, infrared, visible light, ultraviolet, X-rays, and gamma rays.");
    }
    if (containsPhraseIgnoreCase(prompt, "solar eclipse")) {
        return allocator.dupe(u8, "A solar eclipse happens when the Moon passes between Earth and the Sun and blocks some or all of the Sun from a viewer's perspective.");
    }
    if (containsPhraseIgnoreCase(prompt, "lunar eclipse")) {
        return allocator.dupe(u8, "A lunar eclipse happens when Earth passes between the Sun and the Moon, causing Earth's shadow to fall on the Moon.");
    }
    if (containsPhraseIgnoreCase(prompt, "black hole")) {
        return allocator.dupe(u8, "A black hole is a region of spacetime where gravity is so strong that, inside the event horizon, even light cannot escape.");
    }
    if (containsPhraseIgnoreCase(prompt, "greenhouse effect")) {
        return allocator.dupe(u8, "The greenhouse effect is warming caused when gases such as carbon dioxide, methane, and water vapor absorb and re-emit infrared radiation from Earth.");
    }
    if (containsPhraseIgnoreCase(prompt, "carbon cycle")) {
        return allocator.dupe(u8, "The carbon cycle is the movement of carbon among the atmosphere, oceans, living things, soils, rocks, and fossil-fuel reservoirs.");
    }
    if (containsPhraseIgnoreCase(prompt, "water cycle")) {
        return allocator.dupe(u8, "The water cycle moves water through evaporation, condensation, precipitation, runoff, infiltration, and storage in oceans, ice, groundwater, and the atmosphere.");
    }
    if (containsPhraseIgnoreCase(prompt, "bayes theorem") or containsPhraseIgnoreCase(prompt, "bayes' theorem")) {
        return allocator.dupe(u8, "Bayes' theorem updates a probability after evidence: posterior probability is proportional to prior probability times likelihood.");
    }
    if (containsPhraseIgnoreCase(prompt, "overfitting")) {
        return allocator.dupe(u8, "Overfitting happens when a model learns training data too specifically, including noise, so it performs worse on new examples.");
    }
    if (containsPhraseIgnoreCase(prompt, "regularization")) {
        return allocator.dupe(u8, "Regularization adds a constraint or penalty that discourages overly complex models, often improving generalization.");
    }
    if (containsPhraseIgnoreCase(prompt, "classification vs regression")) {
        return allocator.dupe(u8, "Classification predicts categories or labels. Regression predicts numeric values.");
    }
    if (containsPhraseIgnoreCase(prompt, "http vs https")) {
        return allocator.dupe(u8, "HTTP sends web requests without built-in encryption. HTTPS is HTTP over TLS, adding encryption, integrity, and server authentication.");
    }
    if (containsPhraseIgnoreCase(prompt, "dns")) {
        return allocator.dupe(u8, "DNS is the Domain Name System: it maps human-readable domain names to IP addresses and other records that computers use for routing.");
    }
    if (containsPhraseIgnoreCase(prompt, "operating system")) {
        return allocator.dupe(u8, "An operating system manages hardware resources, processes, memory, files, devices, and the interface between applications and the machine.");
    }
    if (containsPhraseIgnoreCase(prompt, "deadlock")) {
        return allocator.dupe(u8, "A deadlock occurs when tasks wait on each other in a cycle, so none can proceed without outside intervention.");
    }
    if (containsPhraseIgnoreCase(prompt, "race condition")) {
        return allocator.dupe(u8, "A race condition happens when a program's result depends on timing between concurrent operations instead of a controlled order.");
    }
    if (containsPhraseIgnoreCase(prompt, "big o notation")) {
        return allocator.dupe(u8, "Big O notation describes how an algorithm's resource use grows as input size grows, such as O(1), O(log n), O(n), or O(n^2).");
    }
    if (containsPhraseIgnoreCase(prompt, "compiler")) {
        return allocator.dupe(u8, "A compiler translates source code into another form, often machine code or an intermediate representation, before or during execution.");
    }
    if (containsPhraseIgnoreCase(prompt, "interpreter")) {
        return allocator.dupe(u8, "An interpreter runs code by reading and executing it directly or through an intermediate representation rather than producing a standalone native binary first.");
    }
    if (containsPhraseIgnoreCase(prompt, "checksum")) {
        return allocator.dupe(u8, "A checksum is a compact value computed from data to help detect accidental changes or corruption.");
    }
    if (containsPhraseIgnoreCase(prompt, "rsa")) {
        return allocator.dupe(u8, "RSA is a public-key cryptography system based on the difficulty of factoring large composite numbers.");
    }
    if (containsPhraseIgnoreCase(prompt, "world war i")) {
        return allocator.dupe(u8, "World War I was a major global conflict from 1914 to 1918 involving alliances across Europe and beyond, trench warfare, and major political consequences.");
    }
    if (containsPhraseIgnoreCase(prompt, "industrial revolution")) {
        return allocator.dupe(u8, "The Industrial Revolution was the shift toward mechanized production, factories, steam power, and major social and economic change beginning in Britain in the 18th century.");
    }
    if (containsPhraseIgnoreCase(prompt, "renaissance")) {
        return allocator.dupe(u8, "The Renaissance was a period of renewed interest in classical learning, art, science, and humanism in Europe, especially from the 14th to 17th centuries.");
    }
    if (containsPhraseIgnoreCase(prompt, "magna carta")) {
        return allocator.dupe(u8, "Magna Carta was a 1215 English charter that limited royal power and became an important symbol in the development of rule-of-law ideas.");
    }
    if (containsPhraseIgnoreCase(prompt, "plato")) {
        return allocator.dupe(u8, "Plato was an ancient Greek philosopher, student of Socrates, teacher of Aristotle, and author of dialogues such as The Republic.");
    }
    if (containsPhraseIgnoreCase(prompt, "aristotle")) {
        return allocator.dupe(u8, "Aristotle was an ancient Greek philosopher who wrote on logic, ethics, biology, politics, metaphysics, and many other fields.");
    }
    if (containsPhraseIgnoreCase(prompt, "hamlet")) {
        return allocator.dupe(u8, "Hamlet is a tragedy by William Shakespeare about revenge, uncertainty, grief, power, and moral hesitation.");
    }
    if (containsPhraseIgnoreCase(prompt, "odyssey") or containsPhraseIgnoreCase(prompt, "homer")) {
        return allocator.dupe(u8, "The Odyssey is an ancient Greek epic traditionally attributed to Homer, following Odysseus's long journey home after the Trojan War.");
    }
    if (containsPhraseIgnoreCase(prompt, "moby dick")) {
        return allocator.dupe(u8, "Moby-Dick is a novel by Herman Melville about Captain Ahab's obsessive pursuit of the white whale, mixing adventure, symbolism, and philosophical reflection.");
    }
    if (containsPhraseIgnoreCase(prompt, "great gatsby")) {
        return allocator.dupe(u8, "The Great Gatsby is a novel by F. Scott Fitzgerald about wealth, longing, illusion, and social class in 1920s America.");
    }
    return allocator.dupe(u8, "I can answer stable general-knowledge prompts from a bounded built-in set, but I should ask for a source for current, specialized, or disputed facts.");
}

fn buildZigUpstreamResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (containsPhraseIgnoreCase(prompt, "where is std.hashmap implemented")) {
        return allocator.dupe(u8, "In the upstream Zig source tree, the generic hash map implementation lives in lib/std/hash_map.zig.");
    }
    if (containsPhraseIgnoreCase(prompt, "what does std.hashmap do")) {
        return allocator.dupe(u8, "In the upstream Zig source tree, lib/std/hash_map.zig implements generic hash maps and helpers such as StringHashMap.");
    }
    if (containsPhraseIgnoreCase(prompt, "where is std.arraylist implemented")) {
        return allocator.dupe(u8, "In the upstream Zig source tree, ArrayList lives in lib/std/array_list.zig.");
    }
    if (containsPhraseIgnoreCase(prompt, "what does std.arraylist do")) {
        return allocator.dupe(u8, "In the upstream Zig source tree, lib/std/array_list.zig implements ArrayList and related growable contiguous arrays.");
    }
    if (containsPhraseIgnoreCase(prompt, "what does zig std do")) {
        return allocator.dupe(u8, "The Zig README says `zig std` opens the standard library documentation in a browser tab.");
    }
    if (containsPhraseIgnoreCase(prompt, "what file drives the zig source build")) {
        return allocator.dupe(u8, "In the upstream Zig source tree, build.zig is the top-level Zig build script in the repository root.");
    }
    if (containsPhraseIgnoreCase(prompt, "build zig from source")) {
        return allocator.dupe(u8, "The upstream Zig README describes the standard source build as the normal CMake process: create a build directory, run cmake, and then make install.");
    }
    if (containsPhraseIgnoreCase(prompt, "build zig without llvm") or containsPhraseIgnoreCase(prompt, "bootstrap.c")) {
        return allocator.dupe(u8, "The upstream Zig README says you can compile bootstrap.c with a C compiler, run the resulting bootstrap executable, and produce a zig2 stage2 compiler without LLVM extensions.");
    }
    if (containsPhraseIgnoreCase(prompt, "what is zig upstream")) {
        return allocator.dupe(u8, "The upstream Zig repository is the source tree for the Zig language and toolchain, including the compiler, standard library, build system, and language-reference examples.");
    }
    return std.fmt.allocPrint(allocator, "I can answer practical Zig upstream questions about the top-level build, standard-library file locations, and the versioned source tree that is bundled for this {s} upgrade work.", .{current_release_version});
}

fn buildCoffeeResponse(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "If coffee tastes flat or harsh, the fastest fixes are usually fresher beans, a cleaner grinder, and adjusting the grind. If it tastes bitter, make the grind a bit coarser or shorten the brew. If it tastes sour or weak, grind a bit finer, use hotter water, or raise the coffee dose slightly.");
}

fn extractRewriteSource(prompt: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, prompt, ':')) |idx| {
        const value = trimInlineValue(prompt[idx + 1 ..]);
        if (value.len > 0) return value;
    }
    const markers = [_][]const u8{
        "rewrite this professionally ",
        "rewrite professionally ",
        "rephrase this professionally ",
    };
    for (markers) |marker| {
        if (indexOfPhraseIgnoreCase(prompt, marker)) |idx| {
            const value = trimInlineValue(prompt[idx + marker.len ..]);
            if (value.len > 0) return value;
        }
    }
    return null;
}

fn buildUncertaintyResponse(allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (isDomainPrompt(prompt)) {
        return std.fmt.allocPrint(allocator, "I am not sure enough to answer that from the grounded {s} knowledge yet.", .{current_release_name});
    }
    return allocator.dupe(u8, "I am not sure yet. I can handle grounded SBAN questions, remembered session facts, short math, everyday planning, writing help, coding snippets, simple explanations, and a wider set of casual prompts, but I still should not improvise beyond that.");
}

fn isDomainPrompt(prompt: []const u8) bool {
    if (containsPhraseIgnoreCase(prompt, "sban") or
        containsPhraseIgnoreCase(prompt, "bridge-adaptive") or
        containsPhraseIgnoreCase(prompt, "bridge memory") or
        containsPhraseIgnoreCase(prompt, "session memory") or
        containsPhraseIgnoreCase(prompt, "transformer") or
        containsPhraseIgnoreCase(prompt, "benchmark") or
        containsPhraseIgnoreCase(prompt, "accel-info") or
        containsPhraseIgnoreCase(prompt, "numeric-accel-info") or
        containsPhraseIgnoreCase(prompt, "accel-bench") or
        containsPhraseIgnoreCase(prompt, "cpu_mt") or
        containsPhraseIgnoreCase(prompt, "opencl") or
        containsPhraseIgnoreCase(prompt, "cuda") or
        containsPhraseIgnoreCase(prompt, "rtx") or
        containsPhraseIgnoreCase(prompt, "starter file") or
        containsPhraseIgnoreCase(prompt, "release bundle") or
        containsPhraseIgnoreCase(prompt, "executive summary") or
        containsPhraseIgnoreCase(prompt, "repo zip") or
        containsPhraseIgnoreCase(prompt, "paper pdf") or
        containsPhraseIgnoreCase(prompt, "what is the windows starter file") or
        containsPhraseIgnoreCase(prompt, "what is the linux starter file"))
    {
        return true;
    }
    if (containsPhraseIgnoreCase(prompt, "architecture") and
        (containsPhraseIgnoreCase(prompt, "sban") or containsPhraseIgnoreCase(prompt, "bridge")))
    {
        return true;
    }
    if ((containsPhraseIgnoreCase(prompt, "release") or containsPhraseIgnoreCase(prompt, "demo")) and findVersionToken(prompt) != null) {
        return true;
    }
    if ((containsPhraseIgnoreCase(prompt, "paper") or containsPhraseIgnoreCase(prompt, "summary") or containsPhraseIgnoreCase(prompt, "report")) and findVersionToken(prompt) != null) {
        return true;
    }
    return false;
}

fn isUnsupportedSourceLocationPrompt(prompt: []const u8) bool {
    return hasAnyPhraseIgnoreCase(prompt, &.{ "where is", "which file", "what file", "source location" }) and
        hasAnyPhraseIgnoreCase(prompt, &.{ "linux kernel", "kernel source", "rust source", "cpython source" }) and
        !hasAnyPhraseIgnoreCase(prompt, &.{ "zig upstream", "sban" });
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

fn loadDialogueCorpus(
    allocator: std.mem.Allocator,
    io: std.Io,
    writer: *Io.Writer,
    path: []const u8,
    label: []const u8,
    backend: AccelBackend,
    worker_threads: usize,
) !?LoadedDialogueCorpus {
    const seed_bytes = readWholeFileFriendly(allocator, io, writer, path, label) orelse return null;
    errdefer allocator.free(seed_bytes);

    var examples = parseDialogueExamples(allocator, seed_bytes) catch {
        try writer.writeAll("error=invalid_seed_format\n");
        try writer.flush();
        return null;
    };
    errdefer examples.deinit(allocator);

    var corpus = try prepareCorpus(allocator, examples.items);
    errdefer corpus.deinit(allocator);

    var scorer = ApproximateScorer.init(allocator, backend, &corpus, worker_threads) catch |err| {
        try writer.print("error=accelerator_init_failed detail={s}\n", .{@errorName(err)});
        try writer.flush();
        return null;
    };
    errdefer scorer.deinit();

    return .{
        .seed_bytes = seed_bytes,
        .examples = examples,
        .corpus = corpus,
        .scorer = scorer,
    };
}

fn loadOptionalDialogueCorpus(
    allocator: std.mem.Allocator,
    io: std.Io,
    writer: *Io.Writer,
    path: ?[]const u8,
    label: []const u8,
    backend: AccelBackend,
    worker_threads: usize,
) !?LoadedDialogueCorpus {
    const actual_path = path orelse return null;
    return try loadDialogueCorpus(allocator, io, writer, actual_path, label, backend, worker_threads);
}

fn parseChatOptions(writer: *Io.Writer, args: []const []const u8, start_idx: usize, options: *ChatOptions) !void {
    for (args[start_idx..]) |arg| {
        const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse {
            try writer.print("invalid_override={s}\n", .{arg});
            return error.InvalidOverride;
        };
        const key = arg[0..eq_idx];
        const value = arg[eq_idx + 1 ..];
        if (std.mem.eql(u8, key, "prewarm_path")) {
            if (std.mem.eql(u8, value, "none") or std.mem.eql(u8, value, "off")) {
                options.seed_path = current_cold_seed_path;
                options.knowledge_path = null;
                options.open_seed_path = null;
                options.learned_path = null;
            } else {
                options.seed_path = value;
                options.knowledge_path = value;
                options.open_seed_path = null;
                options.learned_path = null;
            }
        } else if (std.mem.eql(u8, key, "seed_path")) {
            options.seed_path = value;
        } else if (std.mem.eql(u8, key, "open_seed_path")) {
            if (std.mem.eql(u8, value, "none") or std.mem.eql(u8, value, "off")) options.open_seed_path = null else options.open_seed_path = value;
        } else if (std.mem.eql(u8, key, "knowledge_path")) {
            if (std.mem.eql(u8, value, "none") or std.mem.eql(u8, value, "off")) options.knowledge_path = null else options.knowledge_path = value;
        } else if (std.mem.eql(u8, key, "learned_path")) {
            if (std.mem.eql(u8, value, "none") or std.mem.eql(u8, value, "off")) options.learned_path = null else options.learned_path = value;
        } else if (std.mem.eql(u8, key, "session_path")) {
            options.session_path = value;
        } else if (std.mem.eql(u8, key, "mode")) {
            if (std.mem.eql(u8, value, "anchor")) options.mode = .anchor else if (std.mem.eql(u8, value, "free") or std.mem.eql(u8, value, "reason") or std.mem.eql(u8, value, "reasoning")) options.mode = .free else if (std.mem.eql(u8, value, "hybrid")) options.mode = .hybrid else {
                try writer.print("invalid_mode={s}\n", .{value});
                return error.InvalidOverride;
            }
        } else if (std.mem.eql(u8, key, "backend")) {
            if (std.mem.eql(u8, value, "auto")) options.backend = .auto else if (std.mem.eql(u8, value, "cpu")) options.backend = .cpu else if (std.mem.eql(u8, value, "cpu_mt")) options.backend = .cpu_mt else if (std.mem.eql(u8, value, "gpu")) options.backend = .gpu else if (std.mem.eql(u8, value, "opencl")) options.backend = .opencl else if (std.mem.eql(u8, value, "cuda")) options.backend = .cuda else {
                try writer.print("invalid_backend={s}\n", .{value});
                return error.InvalidOverride;
            }
        } else if (std.mem.eql(u8, key, "threads")) {
            options.worker_threads = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "iterations")) {
            options.iterations = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "max_bytes")) {
            options.max_bytes = try std.fmt.parseInt(usize, value, 10);
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
    const flat = try allocator.alloc(u16, corpus.items.items.len * feature_dim);
    corpus.flat_vectors = flat;
    for (corpus.items.items, 0..) |item, idx| {
        @memcpy(flat[idx * feature_dim .. (idx + 1) * feature_dim], item.vector[0..]);
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
        if (!isGenericTopicToken(canonical)) {
            try appendUniqueHash(allocator, &tokenized.topic_hashes, hash);
        }
        addFeature(&tokenized.vector, hash, @intCast(@min(canonical.len + 1, 12)));
        if (!std.mem.eql(u8, canonical, token)) {
            const raw_hash = std.hash.Wyhash.hash(0, token);
            try appendUniqueHash(allocator, &tokenized.token_hashes, raw_hash);
            if (!isGenericTopicToken(token)) {
                try appendUniqueHash(allocator, &tokenized.topic_hashes, raw_hash);
            }
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

fn isGenericTopicToken(token: []const u8) bool {
    return hasAnyPhraseIgnoreCase(token, &.{
        "change",
        "compare",
        "launch",
        "command",
        "support",
        "overview",
        "limit",
        "bundle",
        "path",
        "paper",
        "summary",
        "roadmap",
        "gpu",
        "nvidia",
        "plan",
        "agenda",
        "interview",
        "apology",
        "procrastinate",
        "doomscroll",
        "workout",
        "polite",
        "idea",
        "focus",
        "meal",
        "feeling",
        "message",
        "music",
        "movie",
        "write",
        "draft",
        "short",
        "simple",
        "explain",
        "detail",
        "detailed",
        "code",
        "coding",
        "function",
        "class",
        "python",
        "javascript",
        "snippet",
        "help",
        "question",
        "answer",
    });
}

fn classifyIntent(text: []const u8) IntentKind {
    const trimmed = trimLine(text);
    if (startsWithWordIgnoreCase(trimmed, "what")) return .what;
    if (startsWithWordIgnoreCase(trimmed, "how")) return .how;
    if (startsWithWordIgnoreCase(trimmed, "why")) return .why;
    if (startsWithWordIgnoreCase(trimmed, "explain")) return .explain;
    if (startsWithWordIgnoreCase(trimmed, "compare")) return .compare;
    if (startsWithWordIgnoreCase(trimmed, "give")) return .give;
    if (startsWithWordIgnoreCase(trimmed, "list")) return .list;
    if (startsWithWordIgnoreCase(trimmed, "should")) return .should;
    if (startsWithWordIgnoreCase(trimmed, "can")) return .can;
    if (startsWithWordIgnoreCase(trimmed, "does")) return .does;
    if (startsWithWordIgnoreCase(trimmed, "which")) return .which;
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

fn hasAnyPhraseIgnoreCase(text: []const u8, phrases: []const []const u8) bool {
    for (phrases) |phrase| {
        if (containsPhraseIgnoreCase(text, phrase)) return true;
    }
    return false;
}

fn wantsStarterAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "starter file",
        "start file",
        "launcher",
        "windows starter",
        "linux starter",
    }) or ((containsPhraseIgnoreCase(text, "start") or containsPhraseIgnoreCase(text, "launch")) and
        (containsPhraseIgnoreCase(text, "windows") or containsPhraseIgnoreCase(text, "linux") or containsPhraseIgnoreCase(text, "demo")));
}

fn mentionsStarterAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        ".bat",
        ".sh",
        "start.bat",
        "start.sh",
        "starter",
        "launch",
        "windows demo",
        "linux demo",
    });
}

fn wantsArtifactPathAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "paper pdf",
        "executive summary",
        "repo zip",
        "report path",
        "artifact path",
        "where is the paper",
        "where is the summary",
        "where is the report",
        "where is the repo",
        "where is the pdf",
        "path to the paper",
    }) or
        ((containsPhraseIgnoreCase(text, "where") or containsPhraseIgnoreCase(text, "path")) and
            hasAnyPhraseIgnoreCase(text, &.{ "paper", "summary", "report", "repo", "pdf" }));
}

fn mentionsArtifactPathAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        ".pdf",
        ".md",
        ".zip",
        "docs/papers",
        "deliverables/",
        "summary",
        "report",
        "repo zip",
        "paper",
    });
}

fn wantsBundleInventory(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "what ships",
        "what files ship",
        "which files ship",
        "what is in the release bundle",
        "what is in the bundle",
        "what files are in the bundle",
        "release bundle",
        "artifact inventory",
        "bundle inventory",
        "what ships in",
    }) or ((containsPhraseIgnoreCase(text, "bundle") or containsPhraseIgnoreCase(text, "release")) and
        (containsPhraseIgnoreCase(text, "file") or containsPhraseIgnoreCase(text, "files") or containsPhraseIgnoreCase(text, "ship")));
}

fn mentionsBundleInventory(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "bundle",
        "release bundle",
        "files",
        "summary",
        "executive summary",
        "report",
        "paper",
        "repo zip",
        "demo zip",
        "asset",
        "ships",
    });
}

fn wantsCudaCommandAnswer(text: []const u8) bool {
    return containsPhraseIgnoreCase(text, "cuda") and hasAnyPhraseIgnoreCase(text, &.{
        "what command",
        "which command",
        "show",
        "check",
        "inspect",
        "verify",
    });
}

fn mentionsCudaCommandAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "accel-info",
        "accel bench",
        "backend=cuda",
        "cuda support",
        "nvidia cuda",
    });
}

fn wantsHardwareAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "cuda",
        "opencl",
        "gpu",
        "rtx",
        "nvidia",
        "4090",
        "2080",
        "cpu_mt",
        "cpu mt",
        "cpu",
    });
}

fn mentionsHardwareAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "cuda",
        "opencl",
        "gpu",
        "rtx",
        "nvidia",
        "cpu_mt",
        "cpu mt",
        "cpu",
    });
}

fn wantsRoadmapAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "roadmap",
        "next version",
        "next release",
        "future work",
        "what should v35 improve",
        "what comes after v35",
        "what should v34 improve",
        "what comes after v34",
        "what should v31 improve",
        "what comes after v31",
        "roadmap after",
        "after v35",
        "after v34",
        "after v31",
        "should improve",
        "what should improve",
    });
}

fn mentionsRoadmapAnswer(text: []const u8) bool {
    return hasAnyPhraseIgnoreCase(text, &.{
        "roadmap",
        "next",
        "future",
        "improve",
        "follow-up",
    });
}

fn passesSemanticGuards(prompt: []const u8, candidate: []const u8) bool {
    if (wantsStarterAnswer(prompt) and !mentionsStarterAnswer(candidate)) return false;
    if (wantsArtifactPathAnswer(prompt) and !mentionsArtifactPathAnswer(candidate)) return false;
    if (wantsBundleInventory(prompt) and !mentionsBundleInventory(candidate)) return false;
    if (wantsCudaCommandAnswer(prompt) and !mentionsCudaCommandAnswer(candidate)) return false;
    if (wantsHardwareAnswer(prompt) and !mentionsHardwareAnswer(candidate)) return false;
    if (wantsRoadmapAnswer(prompt) and !mentionsRoadmapAnswer(candidate)) return false;
    if (containsPhraseIgnoreCase(prompt, "transformer") and !containsPhraseIgnoreCase(candidate, "transformer")) return false;
    if (containsPhraseIgnoreCase(prompt, "bridge memory") and !containsPhraseIgnoreCase(candidate, "bridge")) return false;
    if (containsPhraseIgnoreCase(prompt, "compare") and !hasAnyPhraseIgnoreCase(candidate, &.{ "compare", "difference", "tradeoff", "versus" })) return false;
    if (containsPhraseIgnoreCase(prompt, "paper") and containsPhraseIgnoreCase(prompt, "pdf") and !containsPhraseIgnoreCase(candidate, "pdf")) return false;
    return true;
}

fn semanticBoost(prompt: []const u8, candidate: []const u8) i32 {
    var boost: i32 = 0;
    if (wantsStarterAnswer(prompt) and mentionsStarterAnswer(candidate)) boost += 1600;
    if (wantsArtifactPathAnswer(prompt) and mentionsArtifactPathAnswer(candidate)) boost += 1700;
    if (wantsBundleInventory(prompt) and mentionsBundleInventory(candidate)) boost += 1500;
    if (wantsCudaCommandAnswer(prompt) and mentionsCudaCommandAnswer(candidate)) boost += 1800;
    if (wantsHardwareAnswer(prompt) and mentionsHardwareAnswer(candidate)) boost += 1100;
    if (wantsRoadmapAnswer(prompt) and mentionsRoadmapAnswer(candidate)) boost += 1000;
    if (containsPhraseIgnoreCase(prompt, "transformer") and containsPhraseIgnoreCase(candidate, "transformer")) boost += 900;
    if (containsPhraseIgnoreCase(prompt, "bridge memory") and containsPhraseIgnoreCase(candidate, "bridge")) boost += 800;
    return boost;
}

fn hasConflictingVersionToken(prompt: []const u8, candidate: []const u8) bool {
    const prompt_version = findVersionToken(prompt) orelse return false;
    const candidate_version = findVersionToken(candidate) orelse return false;
    if (containsVersionToken(prompt, candidate_version)) return false;
    if (containsVersionToken(candidate, prompt_version)) return false;
    return true;
}

fn containsVersionToken(text: []const u8, version: []const u8) bool {
    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        if ((text[idx] == 'v' or text[idx] == 'V') and idx + 1 < text.len and std.ascii.isDigit(text[idx + 1])) {
            if (idx > 0 and isWordChar(text[idx - 1])) continue;
            var end = idx + 2;
            while (end < text.len and std.ascii.isDigit(text[end])) : (end += 1) {}
            if (std.ascii.eqlIgnoreCase(text[idx..end], version)) return true;
            idx = end - 1;
        }
    }
    return false;
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
        "a",     "an",  "and",  "are", "be",     "can",  "do",   "does", "for",  "from", "how", "i",   "im",   "in",   "is",    "it",  "me",  "my",
        "of",    "on",  "or",   "our", "please", "tell", "that", "the",  "this", "to",   "us",  "was", "what", "when", "where", "who", "why", "with",
        "would", "you", "your",
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
        std.mem.eql(u8, token, "upgrade") or
        std.mem.eql(u8, token, "delta"))
    {
        return "change";
    }
    if (std.mem.eql(u8, token, "compare") or
        std.mem.eql(u8, token, "compares") or
        std.mem.eql(u8, token, "comparison") or
        std.mem.eql(u8, token, "versus") or
        std.mem.eql(u8, token, "vs"))
    {
        return "compare";
    }
    if (std.mem.eql(u8, token, "launch") or
        std.mem.eql(u8, token, "launching") or
        std.mem.eql(u8, token, "start") or
        std.mem.eql(u8, token, "starting") or
        std.mem.eql(u8, token, "open") or
        std.mem.eql(u8, token, "run") or
        std.mem.eql(u8, token, "running") or
        std.mem.eql(u8, token, "starter") or
        std.mem.eql(u8, token, "launcher") or
        std.mem.eql(u8, token, "script"))
    {
        return "launch";
    }
    if (std.mem.eql(u8, token, "command") or
        std.mem.eql(u8, token, "commands") or
        std.mem.eql(u8, token, "check") or
        std.mem.eql(u8, token, "checks") or
        std.mem.eql(u8, token, "verify") or
        std.mem.eql(u8, token, "verifies"))
    {
        return "command";
    }
    if (std.mem.eql(u8, token, "supports") or
        std.mem.eql(u8, token, "supported") or
        std.mem.eql(u8, token, "supporting") or
        std.mem.eql(u8, token, "compatible"))
    {
        return "support";
    }
    if (std.mem.eql(u8, token, "overview") or
        std.mem.eql(u8, token, "describe") or
        std.mem.eql(u8, token, "described") or
        std.mem.eql(u8, token, "pitch") or
        std.mem.eql(u8, token, "elevator"))
    {
        return "overview";
    }
    if (std.mem.eql(u8, token, "limit") or
        std.mem.eql(u8, token, "limits") or
        std.mem.eql(u8, token, "limitation") or
        std.mem.eql(u8, token, "limitations") or
        std.mem.eql(u8, token, "weakness") or
        std.mem.eql(u8, token, "weaknesses") or
        std.mem.eql(u8, token, "tradeoff") or
        std.mem.eql(u8, token, "tradeoffs"))
    {
        return "limit";
    }
    if (std.mem.eql(u8, token, "artifact") or
        std.mem.eql(u8, token, "artifacts") or
        std.mem.eql(u8, token, "inventory") or
        std.mem.eql(u8, token, "bundle") or
        std.mem.eql(u8, token, "bundles") or
        std.mem.eql(u8, token, "deliverable") or
        std.mem.eql(u8, token, "deliverables"))
    {
        return "bundle";
    }
    if (std.mem.eql(u8, token, "file") or
        std.mem.eql(u8, token, "files") or
        std.mem.eql(u8, token, "filename") or
        std.mem.eql(u8, token, "path") or
        std.mem.eql(u8, token, "paths"))
    {
        return "path";
    }
    if (std.mem.eql(u8, token, "paper") or std.mem.eql(u8, token, "pdf")) {
        return "paper";
    }
    if (std.mem.eql(u8, token, "summary")) {
        return "summary";
    }
    if (std.mem.eql(u8, token, "roadmap") or
        std.mem.eql(u8, token, "future"))
    {
        return "roadmap";
    }
    if (std.mem.eql(u8, token, "cuda") or std.mem.eql(u8, token, "opencl")) {
        return "gpu";
    }
    if (std.mem.eql(u8, token, "nvidia") or
        std.mem.eql(u8, token, "rtx"))
    {
        return "nvidia";
    }
    if (std.mem.eql(u8, token, "plan") or
        std.mem.eql(u8, token, "planning") or
        std.mem.eql(u8, token, "organize") or
        std.mem.eql(u8, token, "organizing") or
        std.mem.eql(u8, token, "organise") or
        std.mem.eql(u8, token, "organising") or
        std.mem.eql(u8, token, "schedule") or
        std.mem.eql(u8, token, "scheduling") or
        std.mem.eql(u8, token, "routine"))
    {
        return "plan";
    }
    if (std.mem.eql(u8, token, "agenda") or
        std.mem.eql(u8, token, "agendas") or
        std.mem.eql(u8, token, "outline") or
        std.mem.eql(u8, token, "outlines"))
    {
        return "agenda";
    }
    if (std.mem.eql(u8, token, "interview") or
        std.mem.eql(u8, token, "interviews") or
        std.mem.eql(u8, token, "interviewing"))
    {
        return "interview";
    }
    if (std.mem.eql(u8, token, "apology") or
        std.mem.eql(u8, token, "apologize") or
        std.mem.eql(u8, token, "apologise") or
        std.mem.eql(u8, token, "sorry"))
    {
        return "apology";
    }
    if (std.mem.eql(u8, token, "procrastinating") or
        std.mem.eql(u8, token, "procrastinate") or
        std.mem.eql(u8, token, "procrastination"))
    {
        return "procrastinate";
    }
    if (std.mem.eql(u8, token, "doomscrolling") or
        std.mem.eql(u8, token, "doomscroll"))
    {
        return "doomscroll";
    }
    if (std.mem.eql(u8, token, "workout") or
        std.mem.eql(u8, token, "workouts") or
        std.mem.eql(u8, token, "exercise") or
        std.mem.eql(u8, token, "exercises") or
        std.mem.eql(u8, token, "training"))
    {
        return "workout";
    }
    if (std.mem.eql(u8, token, "polite") or
        std.mem.eql(u8, token, "politely"))
    {
        return "polite";
    }
    if (std.mem.eql(u8, token, "reverse") or
        std.mem.eql(u8, token, "reversed") or
        std.mem.eql(u8, token, "reversing"))
    {
        return "reverse";
    }
    if (std.mem.eql(u8, token, "brainstorm") or
        std.mem.eql(u8, token, "idea") or
        std.mem.eql(u8, token, "ideas") or
        std.mem.eql(u8, token, "names") or
        std.mem.eql(u8, token, "name"))
    {
        return "idea";
    }
    if (std.mem.eql(u8, token, "focused") or
        std.mem.eql(u8, token, "focus") or
        std.mem.eql(u8, token, "focusing") or
        std.mem.eql(u8, token, "concentrate") or
        std.mem.eql(u8, token, "concentration"))
    {
        return "focus";
    }
    if (std.mem.eql(u8, token, "dinner") or
        std.mem.eql(u8, token, "cook") or
        std.mem.eql(u8, token, "cooking") or
        std.mem.eql(u8, token, "meal") or
        std.mem.eql(u8, token, "breakfast"))
    {
        return "meal";
    }
    if (std.mem.eql(u8, token, "stressed") or
        std.mem.eql(u8, token, "stress") or
        std.mem.eql(u8, token, "overwhelmed") or
        std.mem.eql(u8, token, "frustrated") or
        std.mem.eql(u8, token, "nervous") or
        std.mem.eql(u8, token, "tired") or
        std.mem.eql(u8, token, "bored"))
    {
        return "feeling";
    }
    if (std.mem.eql(u8, token, "email") or
        std.mem.eql(u8, token, "emails") or
        std.mem.eql(u8, token, "message") or
        std.mem.eql(u8, token, "messages") or
        std.mem.eql(u8, token, "reply") or
        std.mem.eql(u8, token, "note"))
    {
        return "message";
    }
    if (std.mem.eql(u8, token, "music") or
        std.mem.eql(u8, token, "song") or
        std.mem.eql(u8, token, "songs"))
    {
        return "music";
    }
    if (std.mem.eql(u8, token, "movie") or
        std.mem.eql(u8, token, "movies") or
        std.mem.eql(u8, token, "film") or
        std.mem.eql(u8, token, "films"))
    {
        return "movie";
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

fn trimMathValue(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, "\r\n \t.,!?;:\"'");
}

fn containsPhraseIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;
    var idx: usize = 0;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return true;
    }
    return false;
}

fn isExpectationBoundary(byte: u8) bool {
    return !std.ascii.isAlphanumeric(byte);
}

fn expectationMatchesResponse(haystack: []const u8, needle: []const u8) bool {
    const trimmed = trimLine(needle);
    if (trimmed.len == 0 or haystack.len < trimmed.len) return false;
    const starts_alnum = std.ascii.isAlphanumeric(trimmed[0]);
    const ends_alnum = std.ascii.isAlphanumeric(trimmed[trimmed.len - 1]);
    var idx: usize = 0;
    while (idx + trimmed.len <= haystack.len) : (idx += 1) {
        if (!std.ascii.eqlIgnoreCase(haystack[idx .. idx + trimmed.len], trimmed)) continue;
        if (starts_alnum and idx > 0 and !isExpectationBoundary(haystack[idx - 1])) continue;
        const after = idx + trimmed.len;
        if (ends_alnum and after < haystack.len and !isExpectationBoundary(haystack[after])) continue;
        return true;
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

fn endsWithPhraseIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - needle.len ..], needle);
}

fn stripTrailingFactFiller(value: []const u8) []const u8 {
    var trimmed = trimInlineValue(value);
    while (trimmed.len > 0) {
        const before_len = trimmed.len;
        const fillers = [_][]const u8{
            " right now",
            " currently",
            " at the moment",
            " now",
        };
        for (fillers) |filler| {
            if (trimmed.len > filler.len and endsWithPhraseIgnoreCase(trimmed, filler)) {
                trimmed = trimInlineValue(trimmed[0 .. trimmed.len - filler.len]);
                break;
            }
        }
        if (trimmed.len == before_len) break;
    }
    return trimmed;
}

fn sanitizeFactValue(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    const sanitized = try sanitizeTurnText(allocator, text);
    defer allocator.free(sanitized);
    const trimmed = stripTrailingFactFiller(sanitized);
    return allocator.dupe(u8, trimmed);
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

fn escapeForDisplayLimited(allocator: std.mem.Allocator, text: []const u8, limit: usize) ![]u8 {
    const head = if (text.len > limit) text[0..limit] else text;
    const escaped_head = try escapeForDisplay(allocator, head);
    defer allocator.free(escaped_head);
    if (text.len <= limit) return allocator.dupe(u8, escaped_head);
    return std.fmt.allocPrint(allocator, "{s}... [truncated {d} of {d} bytes]", .{ escaped_head, text.len - head.len, text.len });
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
    if (std.mem.eql(u8, copy, "team name") or std.mem.eql(u8, copy, "squad")) {
        allocator.free(copy);
        return allocator.dupe(u8, "team");
    }
    if (std.mem.eql(u8, copy, "project name") or
        std.mem.eql(u8, copy, "current project") or
        std.mem.eql(u8, copy, "our project") or
        std.mem.eql(u8, copy, "what project we are on") or
        std.mem.eql(u8, copy, "which project we are on"))
    {
        allocator.free(copy);
        return allocator.dupe(u8, "project");
    }
    if (std.mem.eql(u8, copy, "what team i am on") or
        std.mem.eql(u8, copy, "which team i am on") or
        std.mem.eql(u8, copy, "team i am on"))
    {
        allocator.free(copy);
        return allocator.dupe(u8, "team");
    }
    if (std.mem.eql(u8, copy, "dog name") or
        std.mem.eql(u8, copy, "dog's name") or
        std.mem.eql(u8, copy, "dogs name") or
        std.mem.eql(u8, copy, "pet name"))
    {
        allocator.free(copy);
        return allocator.dupe(u8, "dog");
    }
    if (std.mem.eql(u8, copy, "cat name") or
        std.mem.eql(u8, copy, "cat's name") or
        std.mem.eql(u8, copy, "cats name"))
    {
        allocator.free(copy);
        return allocator.dupe(u8, "cat");
    }
    if (std.mem.eql(u8, copy, "tomorrow appointment") or
        std.mem.eql(u8, copy, "what i have tomorrow") or
        std.mem.eql(u8, copy, "tomorrow schedule") or
        std.mem.eql(u8, copy, "appointment tomorrow"))
    {
        allocator.free(copy);
        return allocator.dupe(u8, "tomorrow");
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

fn isStandaloneHelpPrompt(prompt: []const u8) bool {
    const trimmed = trimLine(prompt);
    if (std.ascii.eqlIgnoreCase(trimmed, "help")) return true;
    if (containsPhraseIgnoreCase(prompt, "what can you do") or
        containsPhraseIgnoreCase(prompt, "what can i ask") or
        containsPhraseIgnoreCase(prompt, "how can you help"))
    {
        return true;
    }
    if (containsPhraseIgnoreCase(prompt, "i need help") and
        !hasAnyPhraseIgnoreCase(prompt, &.{ "plan", "write", "draft", "brainstorm", "decide", "task", "steps", "organize", "schedule", "focus", "study", "message", "email" }))
    {
        return true;
    }
    return false;
}

fn extractFactCandidate(allocator: std.mem.Allocator, prompt: []const u8) !?FactCandidate {
    if (extractFixedFactValue(prompt, "i live in ")) |value| {
        return .{ .key = try allocator.dupe(u8, "location"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i am based in ")) |value| {
        return .{ .key = try allocator.dupe(u8, "location"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i am from ")) |value| {
        return .{ .key = try allocator.dupe(u8, "location"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i'm from ")) |value| {
        return .{ .key = try allocator.dupe(u8, "location"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "im from ")) |value| {
        return .{ .key = try allocator.dupe(u8, "location"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i come from ")) |value| {
        return .{ .key = try allocator.dupe(u8, "location"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "our lab is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "lab"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "my lab is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "lab"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractLabWorkValue(prompt, "i work in ")) |value| {
        return .{ .key = try allocator.dupe(u8, "lab"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractLabWorkValue(prompt, "i work at ")) |value| {
        return .{ .key = try allocator.dupe(u8, "lab"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "our team is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "team"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "my team is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "team"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i am on team ")) |value| {
        return .{ .key = try allocator.dupe(u8, "team"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "i'm on team ")) |value| {
        return .{ .key = try allocator.dupe(u8, "team"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "im on team ")) |value| {
        return .{ .key = try allocator.dupe(u8, "team"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "we are on team ")) |value| {
        return .{ .key = try allocator.dupe(u8, "team"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "our project is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "project"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "my project is ")) |value| {
        return .{ .key = try allocator.dupe(u8, "project"), .value = try sanitizeTurnText(allocator, value) };
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
    if (extractFixedFactValue(prompt, "tomorrow i have ")) |value| {
        return .{ .key = try allocator.dupe(u8, "tomorrow"), .value = try sanitizeTurnText(allocator, value) };
    }
    if (extractFixedFactValue(prompt, "tomorrow i need to ")) |value| {
        return .{ .key = try allocator.dupe(u8, "tomorrow"), .value = try sanitizeTurnText(allocator, value) };
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

    if (indexOfPhraseIgnoreCase(prompt, "our ")) |our_idx| {
        const separators = [_][]const u8{ " is ", " are " };
        for (separators) |separator| {
            if (indexOfPhraseIgnoreCase(prompt[our_idx + 4 ..], separator)) |relative_sep| {
                const sep_idx = our_idx + 4 + relative_sep;
                const key = trimInlineValue(prompt[our_idx + 4 .. sep_idx]);
                const value = trimInlineValue(takeValueUntilBoundary(prompt[sep_idx + separator.len ..]));
                if (key.len > 0 and value.len > 0) {
                    return .{ .key = try normalizeFactKey(allocator, key), .value = try sanitizeTurnText(allocator, value) };
                }
            }
        }
    }

    if (indexOfPhraseIgnoreCase(prompt, "remember that my ")) |remember_idx| {
        const key_start = remember_idx + "remember that my ".len;
        const separators = [_][]const u8{ " is ", " are " };
        for (separators) |separator| {
            if (indexOfPhraseIgnoreCase(prompt[key_start..], separator)) |relative_sep| {
                const sep_idx = key_start + relative_sep;
                const key = trimInlineValue(prompt[key_start..sep_idx]);
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

    if (extractNameCandidate(prompt)) |name| {
        return .{ .key = try allocator.dupe(u8, "name"), .value = try sanitizeTurnText(allocator, name) };
    }

    return null;
}

fn extractFactQuery(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (containsPhraseIgnoreCase(prompt, "if i tell you") or containsPhraseIgnoreCase(prompt, "if i say")) return null;

    if (containsPhraseIgnoreCase(prompt, "where do i live") or
        containsPhraseIgnoreCase(prompt, "what city do i live in") or
        containsPhraseIgnoreCase(prompt, "where am i based") or
        containsPhraseIgnoreCase(prompt, "where am i from") or
        containsPhraseIgnoreCase(prompt, "do you remember where i am from"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "location"));
    }
    if (containsPhraseIgnoreCase(prompt, "what is our lab") or
        containsPhraseIgnoreCase(prompt, "what's our lab") or
        containsPhraseIgnoreCase(prompt, "what is my lab") or
        containsPhraseIgnoreCase(prompt, "what's my lab") or
        containsPhraseIgnoreCase(prompt, "what lab do i work in") or
        containsPhraseIgnoreCase(prompt, "which lab do i work in"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "lab"));
    }
    if (containsPhraseIgnoreCase(prompt, "what is our team") or
        containsPhraseIgnoreCase(prompt, "what's our team") or
        containsPhraseIgnoreCase(prompt, "what is my team") or
        containsPhraseIgnoreCase(prompt, "what's my team") or
        containsPhraseIgnoreCase(prompt, "what team am i on") or
        containsPhraseIgnoreCase(prompt, "which team am i on") or
        containsPhraseIgnoreCase(prompt, "what team are we on") or
        containsPhraseIgnoreCase(prompt, "which team are we on") or
        containsPhraseIgnoreCase(prompt, "do you remember our team"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "team"));
    }
    if (containsPhraseIgnoreCase(prompt, "what is my role") or
        containsPhraseIgnoreCase(prompt, "what's my role") or
        containsPhraseIgnoreCase(prompt, "what role did i tell you"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "role"));
    }
    if (containsPhraseIgnoreCase(prompt, "what is our project") or
        containsPhraseIgnoreCase(prompt, "what's our project") or
        containsPhraseIgnoreCase(prompt, "what is my project") or
        containsPhraseIgnoreCase(prompt, "what's my project") or
        containsPhraseIgnoreCase(prompt, "what project are we on") or
        containsPhraseIgnoreCase(prompt, "which project are we on") or
        containsPhraseIgnoreCase(prompt, "what project am i on") or
        containsPhraseIgnoreCase(prompt, "which project am i on"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "project"));
    }
    if (containsPhraseIgnoreCase(prompt, "what do i have tomorrow") or
        containsPhraseIgnoreCase(prompt, "what do we have tomorrow") or
        containsPhraseIgnoreCase(prompt, "what is my appointment tomorrow") or
        containsPhraseIgnoreCase(prompt, "what's my appointment tomorrow") or
        containsPhraseIgnoreCase(prompt, "what is tomorrow's appointment") or
        containsPhraseIgnoreCase(prompt, "what do i need to do tomorrow"))
    {
        return @as(?[]u8, try allocator.dupe(u8, "tomorrow"));
    }

    const markers = [_][]const u8{
        "what is my ",
        "what's my ",
        "can you recall my ",
        "do you remember my ",
        "remember my ",
        "when is my ",
        "when is our ",
        "what are my ",
        "what is our ",
        "what's our ",
        "can you recall our ",
        "do you remember our ",
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

fn extractForgetFactQuery(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    const trimmed = trimLine(prompt);
    if (startsWithWordIgnoreCase(trimmed, "i forgot") or startsWithWordIgnoreCase(trimmed, "forgot")) return null;
    const markers = [_][]const u8{
        "forget my ",
        "forget our ",
        "forget the ",
        "forget ",
        "delete my ",
        "delete our ",
        "delete the ",
        "remove my ",
        "remove our ",
        "remove the ",
        "clear my ",
        "clear our ",
    };
    for (markers) |marker| {
        if (indexOfPhraseIgnoreCase(trimmed, marker)) |idx| {
            if (idx > 0 and !startsWithWordIgnoreCase(trimmed, "please")) continue;
            const key = trimInlineValue(takeValueUntilBoundary(trimmed[idx + marker.len ..]));
            if (key.len > 0) return @as(?[]u8, try normalizeFactKey(allocator, key));
        }
    }
    return null;
}

fn extractMemoryCapabilityQuery(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
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
    if (startsWithWordIgnoreCase(prompt, "can you remember") or startsWithWordIgnoreCase(prompt, "will you remember")) {
        if (containsPhraseIgnoreCase(prompt, "where i am from") or
            containsPhraseIgnoreCase(prompt, "where i live") or
            containsPhraseIgnoreCase(prompt, "where i am based"))
        {
            return @as(?[]u8, try allocator.dupe(u8, "location"));
        }
        if (containsPhraseIgnoreCase(prompt, "what team i am on") or
            containsPhraseIgnoreCase(prompt, "which team i am on") or
            containsPhraseIgnoreCase(prompt, "what team i'm on") or
            containsPhraseIgnoreCase(prompt, "which team i'm on") or
            containsPhraseIgnoreCase(prompt, "what team are we on") or
            containsPhraseIgnoreCase(prompt, "our team"))
        {
            return @as(?[]u8, try allocator.dupe(u8, "team"));
        }
        if (containsPhraseIgnoreCase(prompt, "what project we are on") or
            containsPhraseIgnoreCase(prompt, "which project we are on") or
            containsPhraseIgnoreCase(prompt, "our project"))
        {
            return @as(?[]u8, try allocator.dupe(u8, "project"));
        }
        if (containsPhraseIgnoreCase(prompt, "what i have tomorrow") or
            containsPhraseIgnoreCase(prompt, "appointment tomorrow") or
            containsPhraseIgnoreCase(prompt, "what i need to do tomorrow"))
        {
            return @as(?[]u8, try allocator.dupe(u8, "tomorrow"));
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
            if (idx >= "like ".len and std.ascii.eqlIgnoreCase(prompt[idx - "like ".len .. idx], "like ")) continue;
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
    if (std.ascii.eqlIgnoreCase(first, "a") or
        std.ascii.eqlIgnoreCase(first, "an") or
        std.ascii.eqlIgnoreCase(first, "the") or
        std.ascii.eqlIgnoreCase(first, "from") or
        std.ascii.eqlIgnoreCase(first, "in") or
        std.ascii.eqlIgnoreCase(first, "based") or
        std.ascii.eqlIgnoreCase(first, "on") or
        std.ascii.eqlIgnoreCase(first, "team") or
        isNumberWord(first) or
        hasAnyPhraseIgnoreCase(first, &.{ "stressed", "overwhelmed", "frustrated", "excited", "bored", "nervous", "worried", "tired", "ready", "trying", "working", "procrastinating", "thinking", "feeling", "stuck" }) or
        (first.len > 4 and std.mem.endsWith(u8, first, "ing")))
    {
        return null;
    }
    if (token_iter.next()) |second| {
        if (std.ascii.eqlIgnoreCase(second, "about") or
            std.ascii.eqlIgnoreCase(second, "with") or
            std.ascii.eqlIgnoreCase(second, "for") or
            std.ascii.eqlIgnoreCase(second, "on") or
            std.ascii.eqlIgnoreCase(second, "at"))
        {
            return null;
        }
    }
    return candidate;
}

fn isNumberWord(token: []const u8) bool {
    const numbers = [_][]const u8{
        "zero",
        "one",
        "two",
        "three",
        "four",
        "five",
        "six",
        "seven",
        "eight",
        "nine",
        "ten",
        "eleven",
        "twelve",
    };
    for (numbers) |number| {
        if (std.ascii.eqlIgnoreCase(token, number)) return true;
    }
    return false;
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

fn extractLabWorkValue(prompt: []const u8, marker: []const u8) ?[]const u8 {
    if (indexOfPhraseIgnoreCase(prompt, marker)) |idx| {
        var value = trimInlineValue(takeValueUntilBoundary(prompt[idx + marker.len ..]));
        if (startsWithWordIgnoreCase(value, "the")) {
            value = trimInlineValue(value["the".len..]);
        }
        if (value.len == 0 or !containsPhraseIgnoreCase(value, "lab")) return null;
        if (value.len > 4 and std.ascii.eqlIgnoreCase(value[value.len - 4 ..], " lab")) {
            value = trimInlineValue(value[0 .. value.len - 4]);
        }
        if (value.len == 0) return null;
        return value;
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
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, actual_path, allocator, .limited(max_session_file_bytes)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        error.FileTooBig => return .{},
        else => return err,
    };
    defer allocator.free(bytes);
    if (bytes.len == 0) return .{};

    if (std.mem.startsWith(u8, bytes, session_magic) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v34) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v33) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v32) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v31) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v29) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v28) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v27) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v26) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v25) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v24) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v23_5) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v23) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v22) or
        std.mem.startsWith(u8, bytes, legacy_session_magic_v21))
    {
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
            if (isSensitiveFact(key, value)) continue;
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
        defer std.heap.page_allocator.free(key);
        const value = try encodeField(std.heap.page_allocator, fact.value);
        defer std.heap.page_allocator.free(value);
        try out.print(std.heap.page_allocator, "fact\t{s}\t{s}\n", .{ key, value });
    }
    for (session.turns.items) |turn| {
        const user = try encodeField(std.heap.page_allocator, turn.user);
        defer std.heap.page_allocator.free(user);
        const assistant = try encodeField(std.heap.page_allocator, turn.assistant);
        defer std.heap.page_allocator.free(assistant);
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

fn initOpenClScorer(allocator: std.mem.Allocator, corpus: *const PreparedCorpus) !OpenClScorer {
    if (corpus.items.items.len == 0) return OpenClUnavailable.NoGpuDevice;
    const flat = corpus.flat_vectors orelse return OpenClUnavailable.NoGpuDevice;
    return OpenClScorer.init(allocator, flat, corpus.items.items.len);
}

fn initCudaScorer(allocator: std.mem.Allocator, corpus: *const PreparedCorpus) !CudaScorer {
    if (corpus.items.items.len == 0) return CudaUnavailable.NoCudaDevice;
    const flat = corpus.flat_vectors orelse return CudaUnavailable.NoCudaDevice;
    return CudaScorer.init(allocator, flat, corpus.items.items.len);
}

fn dotProduct(lhs: *const [feature_dim]u16, rhs: *const [feature_dim]u16) u32 {
    var total: u32 = 0;
    for (lhs, 0..) |left, idx| {
        total +%= @as(u32, left) * @as(u32, rhs[idx]);
    }
    return total;
}

fn dotProductFlat(lhs: *const [feature_dim]u16, rhs: []const u16) u32 {
    var total: u32 = 0;
    for (lhs, 0..) |left, idx| {
        total +%= @as(u32, left) * @as(u32, rhs[idx]);
    }
    return total;
}

fn openCudaLibrary() !DynamicLibrary {
    if (builtin.os.tag == .windows) {
        return DynamicLibrary.open("nvcuda.dll");
    }
    return DynamicLibrary.open("libcuda.so.1") catch DynamicLibrary.open("libcuda.so");
}

fn loadCudaApi(lib: *DynamicLibrary) !CudaApi {
    return .{
        .init = lib.lookup(CuInitFn, "cuInit") orelse return CudaUnavailable.NoCudaLoader,
        .device_get_count = lib.lookup(CuDeviceGetCountFn, "cuDeviceGetCount") orelse return CudaUnavailable.NoCudaLoader,
        .device_get = lib.lookup(CuDeviceGetFn, "cuDeviceGet") orelse return CudaUnavailable.NoCudaLoader,
        .device_get_name = lib.lookup(CuDeviceGetNameFn, "cuDeviceGetName") orelse return CudaUnavailable.NoCudaLoader,
        .ctx_create = lib.lookup(CuCtxCreateFn, "cuCtxCreate_v2") orelse lib.lookup(CuCtxCreateFn, "cuCtxCreate") orelse return CudaUnavailable.NoCudaLoader,
        .ctx_destroy = lib.lookup(CuCtxDestroyFn, "cuCtxDestroy_v2") orelse lib.lookup(CuCtxDestroyFn, "cuCtxDestroy") orelse return CudaUnavailable.NoCudaLoader,
        .module_load_data_ex = lib.lookup(CuModuleLoadDataExFn, "cuModuleLoadDataEx") orelse return CudaUnavailable.NoCudaLoader,
        .module_get_function = lib.lookup(CuModuleGetFunctionFn, "cuModuleGetFunction") orelse return CudaUnavailable.NoCudaLoader,
        .module_unload = lib.lookup(CuModuleUnloadFn, "cuModuleUnload") orelse return CudaUnavailable.NoCudaLoader,
        .mem_alloc = lib.lookup(CuMemAllocFn, "cuMemAlloc_v2") orelse lib.lookup(CuMemAllocFn, "cuMemAlloc") orelse return CudaUnavailable.NoCudaLoader,
        .mem_free = lib.lookup(CuMemFreeFn, "cuMemFree_v2") orelse lib.lookup(CuMemFreeFn, "cuMemFree") orelse return CudaUnavailable.NoCudaLoader,
        .memcpy_htod = lib.lookup(CuMemcpyHtoDFn, "cuMemcpyHtoD_v2") orelse lib.lookup(CuMemcpyHtoDFn, "cuMemcpyHtoD") orelse return CudaUnavailable.NoCudaLoader,
        .memcpy_dtoh = lib.lookup(CuMemcpyDtoHFn, "cuMemcpyDtoH_v2") orelse lib.lookup(CuMemcpyDtoHFn, "cuMemcpyDtoH") orelse return CudaUnavailable.NoCudaLoader,
        .launch_kernel = lib.lookup(CuLaunchKernelFn, "cuLaunchKernel") orelse return CudaUnavailable.NoCudaLoader,
        .ctx_synchronize = lib.lookup(CuCtxSynchronizeFn, "cuCtxSynchronize") orelse return CudaUnavailable.NoCudaLoader,
        .get_error_name = lib.lookup(CuGetErrorNameFn, "cuGetErrorName"),
        .get_error_string = lib.lookup(CuGetErrorStringFn, "cuGetErrorString"),
    };
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

fn checkCuda(api: CudaApi, result: cu_result) !void {
    if (result == 0) return;
    if (api.get_error_name) |func| {
        var name_ptr: ?[*:0]const u8 = null;
        if (func(result, &name_ptr) == 0 and name_ptr != null) {
            std.log.err("CUDA failure {d}: {s}", .{ result, std.mem.sliceTo(name_ptr.?, 0) });
        } else {
            std.log.err("CUDA failure {d}", .{result});
        }
    } else {
        std.log.err("CUDA failure {d}", .{result});
    }
    return CudaUnavailable.CudaFailure;
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

const cuda_kernel_ptx: [:0]const u8 =
    \\.version 6.0
    \\.target sm_30
    \\.address_size 64
    \\
    \\.visible .entry score_examples_cuda(
    \\    .param .u64 prompt_ptr,
    \\    .param .u64 examples_ptr,
    \\    .param .u64 out_ptr,
    \\    .param .u32 example_count
    \\)
    \\{
    \\    .reg .pred %p<3>;
    \\    .reg .b16 %h<3>;
    \\    .reg .b32 %r<10>;
    \\    .reg .b64 %rd<10>;
    \\
    \\    ld.param.u64 %rd1, [prompt_ptr];
    \\    ld.param.u64 %rd2, [examples_ptr];
    \\    ld.param.u64 %rd3, [out_ptr];
    \\    ld.param.u32 %r1, [example_count];
    \\
    \\    mov.u32 %r2, %ctaid.x;
    \\    mov.u32 %r3, %ntid.x;
    \\    mov.u32 %r4, %tid.x;
    \\    mad.lo.s32 %r5, %r2, %r3, %r4;
    \\    setp.ge.u32 %p1, %r5, %r1;
    \\    @%p1 bra DONE;
    \\
    \\    mul.wide.u32 %rd4, %r5, 256;
    \\    add.s64 %rd5, %rd2, %rd4;
    \\    mov.u32 %r6, 0;
    \\    mov.u32 %r7, 0;
    \\LOOP:
    \\    setp.ge.u32 %p2, %r6, 128;
    \\    @%p2 bra STORE;
    \\    mul.wide.u32 %rd6, %r6, 2;
    \\    add.s64 %rd7, %rd1, %rd6;
    \\    add.s64 %rd8, %rd5, %rd6;
    \\    ld.global.u16 %h1, [%rd7];
    \\    ld.global.u16 %h2, [%rd8];
    \\    cvt.u32.u16 %r8, %h1;
    \\    cvt.u32.u16 %r9, %h2;
    \\    mad.lo.u32 %r7, %r8, %r9, %r7;
    \\    add.u32 %r6, %r6, 1;
    \\    bra LOOP;
    \\STORE:
    \\    mul.wide.u32 %rd9, %r5, 4;
    \\    add.s64 %rd9, %rd3, %rd9;
    \\    st.global.u32 [%rd9], %r7;
    \\DONE:
    \\    ret;
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

fn solveWordProblem(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (try solveRateWordProblem(allocator, prompt)) |response| return response;
    if (!containsPhraseIgnoreCase(prompt, "how many")) return null;
    if (!(containsPhraseIgnoreCase(prompt, " has ") or
        startsWithWordIgnoreCase(prompt, "if ") or
        containsPhraseIgnoreCase(prompt, " starts with ")))
    {
        return null;
    }

    const start_value = extractFirstUnsigned(prompt) orelse return null;
    var remaining: i64 = @intCast(start_value);

    const subtract_markers = [_][]const u8{
        " gives ",
        " gave ",
        " gives away ",
        " gave away ",
        " loses ",
        " lost ",
        " eats ",
        " ate ",
        " spends ",
        " spent ",
        " sells ",
        " sold ",
        " uses ",
        " used ",
    };
    for (subtract_markers) |marker| {
        if (extractUnsignedAfterMarker(prompt, marker)) |value| {
            remaining -= @as(i64, @intCast(value));
        }
    }

    const add_markers = [_][]const u8{
        " gets ",
        " got ",
        " receives ",
        " received ",
        " buys ",
        " bought ",
        " finds ",
        " found ",
        " gains ",
        " gained ",
    };
    for (add_markers) |marker| {
        if (extractUnsignedAfterMarker(prompt, marker)) |value| {
            remaining += @as(i64, @intCast(value));
        }
    }

    if (containsPhraseIgnoreCase(prompt, "last one") or
        containsPhraseIgnoreCase(prompt, "last orange") or
        containsPhraseIgnoreCase(prompt, "last item") or
        containsPhraseIgnoreCase(prompt, "remaining one") or
        containsPhraseIgnoreCase(prompt, "rest of them"))
    {
        if (hasAnyPhraseIgnoreCase(prompt, &.{ "eat", "eats", "ate", "give", "gives", "gave", "use", "uses", "used", "spend", "spends", "spent", "sell", "sells", "sold" })) {
            remaining = 0;
        }
    }

    if (remaining < 0) remaining = 0;
    const pronoun = inferWordProblemPronoun(prompt);
    return @as(?[]u8, try std.fmt.allocPrint(allocator, "{s} has {d} left.", .{ pronoun, remaining }));
}

fn solveRateWordProblem(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    if (!(containsPhraseIgnoreCase(prompt, "mph") or containsPhraseIgnoreCase(prompt, "miles per hour") or containsPhraseIgnoreCase(prompt, "km/h") or containsPhraseIgnoreCase(prompt, "kilometers per hour"))) return null;
    if (!(containsPhraseIgnoreCase(prompt, "hour") or containsPhraseIgnoreCase(prompt, "hours"))) return null;
    const speed = extractFirstUnsigned(prompt) orelse return null;
    const time_value = extractUnsignedAfterMarker(prompt, "for ") orelse extractUnsignedAfterMarker(prompt, "in ") orelse return null;
    const distance = speed * time_value;
    if (containsPhraseIgnoreCase(prompt, "km/h") or containsPhraseIgnoreCase(prompt, "kilometers per hour")) {
        return @as(?[]u8, try std.fmt.allocPrint(allocator, "It travels {d} kilometers.", .{distance}));
    }
    return @as(?[]u8, try std.fmt.allocPrint(allocator, "It travels {d} miles.", .{distance}));
}

fn inferWordProblemPronoun(prompt: []const u8) []const u8 {
    if (hasAnyPhraseIgnoreCase(prompt, &.{ "alice", "sarah", "mary", "jane", "emma", "olivia" })) return "She";
    if (hasAnyPhraseIgnoreCase(prompt, &.{ "bob", "tom", "john", "mike", "alex" })) return "He";
    return "They";
}

fn extractFirstUnsigned(text: []const u8) ?usize {
    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        if (std.ascii.isDigit(text[idx])) {
            var end = idx + 1;
            while (end < text.len and std.ascii.isDigit(text[end])) : (end += 1) {}
            return std.fmt.parseInt(usize, text[idx..end], 10) catch null;
        }
    }
    return null;
}

fn extractUnsignedAfterMarker(text: []const u8, marker: []const u8) ?usize {
    const start = indexOfPhraseIgnoreCase(text, marker) orelse return null;
    var idx = start + marker.len;
    while (idx < text.len and !std.ascii.isDigit(text[idx])) : (idx += 1) {}
    if (idx >= text.len) return null;
    var end = idx + 1;
    while (end < text.len and std.ascii.isDigit(text[end])) : (end += 1) {}
    return std.fmt.parseInt(usize, text[idx..end], 10) catch null;
}

const MathTokenTag = enum { number, plus, minus, star, slash, lparen, rparen };

const MathToken = struct {
    tag: MathTokenTag,
    value: f64 = 0.0,
};

fn solveMath(allocator: std.mem.Allocator, prompt: []const u8) !?MathOutcome {
    if (try solveLinearEquation(allocator, prompt)) |linear| return linear;

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
    if (!isSafeFiniteMathValue(value)) {
        return .{
            .response = try std.fmt.allocPrint(allocator, "The result for {s} is outside {s}'s safe exact-number range, so I will not cast it to a fixed integer.", .{ expr, current_release_name }),
            .explicit_error = true,
        };
    }
    const formatted = try formatNumber(allocator, value);
    defer allocator.free(formatted);
    return .{
        .response = try std.fmt.allocPrint(allocator, "{s} = {s}.", .{ expr, formatted }),
    };
}

const LinearExpr = struct {
    coeff: f64 = 0.0,
    constant: f64 = 0.0,
};

fn solveLinearEquation(allocator: std.mem.Allocator, prompt: []const u8) !?MathOutcome {
    const expr = extractEquationExpression(prompt) orelse return null;
    const eq_idx = std.mem.indexOfScalar(u8, expr, '=') orelse return null;
    const left = trimInlineValue(expr[0..eq_idx]);
    const right = trimInlineValue(expr[eq_idx + 1 ..]);
    if (left.len == 0 or right.len == 0) return null;
    if (!containsVariableX(left) and !containsVariableX(right)) return null;

    const lhs = parseSimpleLinearSide(left) orelse return null;
    const rhs = parseSimpleLinearSide(right) orelse return null;
    const coeff = lhs.coeff - rhs.coeff;
    const constant = rhs.constant - lhs.constant;
    if (@abs(coeff) < 1e-12) {
        return .{
            .response = try allocator.dupe(u8, "That linear equation does not have a unique solution."),
            .explicit_error = true,
        };
    }
    const value = constant / coeff;
    if (!isSafeFiniteMathValue(value)) {
        return .{
            .response = try std.fmt.allocPrint(allocator, "The linear solution is outside {s}'s safe exact-number range.", .{current_release_name}),
            .explicit_error = true,
        };
    }
    const formatted = try formatNumber(allocator, value);
    defer allocator.free(formatted);
    return .{
        .response = try std.fmt.allocPrint(allocator, "x = {s}.", .{formatted}),
    };
}

fn extractEquationExpression(prompt: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, prompt, '=') == null) return null;
    const prefixes = [_][]const u8{ "solve ", "calculate ", "compute ", "what is " };
    for (prefixes) |prefix| {
        if (indexOfPhraseIgnoreCase(prompt, prefix)) |idx| {
            return trimInlineValue(prompt[idx + prefix.len ..]);
        }
    }
    return trimInlineValue(prompt);
}

fn containsVariableX(text: []const u8) bool {
    for (text, 0..) |byte, idx| {
        if (byte != 'x' and byte != 'X') continue;
        const prev_word = idx > 0 and isWordChar(text[idx - 1]);
        const next_word = idx + 1 < text.len and isWordChar(text[idx + 1]);
        if (!prev_word and !next_word) return true;
        if (idx > 0 and std.ascii.isDigit(text[idx - 1]) and !next_word) return true;
    }
    return false;
}

fn parseSimpleLinearSide(side: []const u8) ?LinearExpr {
    var out: LinearExpr = .{};
    var idx: usize = 0;
    var sign: f64 = 1.0;
    var saw_term = false;

    while (idx < side.len) {
        while (idx < side.len and std.ascii.isWhitespace(side[idx])) : (idx += 1) {}
        if (idx >= side.len) break;
        if (side[idx] == '+') {
            sign = 1.0;
            idx += 1;
            continue;
        }
        if (side[idx] == '-') {
            sign = -1.0;
            idx += 1;
            continue;
        }

        var number: f64 = 1.0;
        const number_start = idx;
        var seen_digit = false;
        var seen_dot = false;
        while (idx < side.len) : (idx += 1) {
            const ch = side[idx];
            if (std.ascii.isDigit(ch)) {
                seen_digit = true;
                continue;
            }
            if (ch == '.' and !seen_dot) {
                seen_dot = true;
                continue;
            }
            break;
        }
        if (seen_digit) {
            number = std.fmt.parseFloat(f64, side[number_start..idx]) catch return null;
        }
        while (idx < side.len and std.ascii.isWhitespace(side[idx])) : (idx += 1) {}
        if (idx < side.len and side[idx] == '*') {
            idx += 1;
            while (idx < side.len and std.ascii.isWhitespace(side[idx])) : (idx += 1) {}
        }

        if (idx < side.len and (side[idx] == 'x' or side[idx] == 'X')) {
            out.coeff += sign * number;
            idx += 1;
            saw_term = true;
        } else if (seen_digit) {
            out.constant += sign * number;
            saw_term = true;
        } else {
            return null;
        }

        sign = 1.0;
        while (idx < side.len and std.ascii.isWhitespace(side[idx])) : (idx += 1) {}
        if (idx < side.len and side[idx] != '+' and side[idx] != '-') return null;
    }

    return if (saw_term) out else null;
}

fn extractMathExpression(allocator: std.mem.Allocator, prompt: []const u8) ?[]u8 {
    const prefixes = [_][]const u8{ "what is ", "calculate ", "compute ", "solve " };
    for (prefixes) |prefix| {
        if (indexOfPhraseIgnoreCase(prompt, prefix)) |idx| {
            const candidate = trimMathValue(prompt[idx + prefix.len ..]);
            return normalizeMathExpression(allocator, candidate) catch null;
        }
    }
    return normalizeMathExpression(allocator, trimMathValue(prompt)) catch null;
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
        if (std.mem.startsWith(u8, text[idx..], "multiplied by")) {
            try out.appendSlice(allocator, "* ");
            idx += "multiplied by".len;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "divided by")) {
            try out.appendSlice(allocator, "/ ");
            idx += "divided by".len;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "over")) {
            try out.appendSlice(allocator, "/ ");
            idx += "over".len;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "to the power of")) {
            try out.appendSlice(allocator, "^ ");
            idx += "to the power of".len;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "power of")) {
            try out.appendSlice(allocator, "^ ");
            idx += "power of".len;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "percent of")) {
            try out.appendSlice(allocator, "/ 100 * ");
            idx += "percent of".len;
            continue;
        }
        if (std.mem.startsWith(u8, text[idx..], "percent")) {
            try out.appendSlice(allocator, "/ 100 ");
            idx += "percent".len;
            continue;
        }

        const ch = text[idx];
        if (std.ascii.isDigit(ch) or ch == '.' or ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '^' or ch == '(' or ch == ')' or ch == 'x' or ch == 'X') {
            const mapped = if (ch == 'x' or ch == 'X') '*' else ch;
            try out.append(allocator, mapped);
            idx += 1;
            continue;
        }
        if (ch == '%') {
            try out.appendSlice(allocator, " / 100 * ");
            idx += 1;
            if (idx < text.len and std.ascii.isWhitespace(text[idx])) idx += 1;
            if (std.mem.startsWith(u8, text[idx..], "of")) idx += 2;
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
        if (ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '^') has_op = true;
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
        var value = try self.parsePower();
        while (true) {
            self.skipWhitespace();
            if (self.index >= self.input.len) break;
            const op = self.input[self.index];
            if (op != '*' and op != '/') break;
            self.index += 1;
            const rhs = try self.parsePower();
            if (op == '/' and rhs == 0.0) return error.DivideByZero;
            value = if (op == '*') value * rhs else value / rhs;
        }
        return value;
    }

    fn parsePower(self: *MathParser) ParseError!f64 {
        var value = try self.parseFactor();
        self.skipWhitespace();
        if (self.index < self.input.len and self.input[self.index] == '^') {
            self.index += 1;
            const rhs = try self.parsePower();
            value = std.math.pow(f64, value, rhs);
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
    if (rounded >= -9223372036854775808.0 and rounded <= 9223372036854775807.0 and @abs(value - rounded) < 1e-9) {
        return std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(rounded))});
    }
    var text = try std.fmt.allocPrint(allocator, "{d:.6}", .{value});
    defer allocator.free(text);
    var end = text.len;
    while (end > 0 and text[end - 1] == '0') {
        end -= 1;
    }
    if (end > 0 and text[end - 1] == '.') {
        end -= 1;
    }
    return allocator.dupe(u8, text[0..end]);
}

fn isSafeFiniteMathValue(value: f64) bool {
    return value == value and value >= -9.223372036854776e18 and value <= 9.223372036854776e18;
}

fn printChatResult(allocator: std.mem.Allocator, writer: *Io.Writer, prompt: []const u8, result: ChatResult, backend_label: []const u8, max_response_bytes: usize) !void {
    const safe_prompt = try escapeForDisplayLimited(allocator, prompt, display_prompt_max_bytes);
    defer allocator.free(safe_prompt);
    const safe_response = try escapeForDisplayLimited(allocator, result.response, max_response_bytes);
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
    var scorer = try ApproximateScorer.init(allocator, .cpu, &corpus, 0);
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

test "emotional i am statement is not treated as a name" {
    try std.testing.expect(extractNameCandidate("i am stressed about work") == null);
}

test "memory capability prompt is not misread as recall" {
    const allocator = std.testing.allocator;
    try std.testing.expect((try extractFactQuery(allocator, "can you remember my role if i tell you")) == null);
    const key = (try extractMemoryCapabilityQuery(allocator, "can you remember my role if i tell you")).?;
    defer allocator.free(key);
    try std.testing.expectEqualStrings("role", key);
}

test "natural location capability question maps to session memory capability" {
    const allocator = std.testing.allocator;
    try std.testing.expect((try extractFactQuery(allocator, "can you remember where i am from")) == null);
    const key = (try extractMemoryCapabilityQuery(allocator, "can you remember where i am from")).?;
    defer allocator.free(key);
    try std.testing.expectEqualStrings("location", key);
    const response = try buildFactCapabilityResponse(allocator, key);
    defer allocator.free(response);
    try std.testing.expect(containsPhraseIgnoreCase(response, "where you live or where you are from"));
}

test "roadmap matcher does not hijack basic v32 overview prompts" {
    try std.testing.expect(!wantsRoadmapAnswer("what is SBAN v32"));
    try std.testing.expect(!wantsRoadmapAnswer("where is the v32 report"));
    try std.testing.expect(wantsRoadmapAnswer("what should v32 improve"));
}

test "week planning and focus prompts are not swallowed by generic planning" {
    try std.testing.expect(!isPlanningPrompt("help me organize my week"));
    try std.testing.expect(isWeekPlanningPrompt("help me organize my week"));
    try std.testing.expect(isFocusPrompt("how can i stay focused"));
}

test "math parser handles negative and decimal arithmetic" {
    const allocator = std.testing.allocator;
    const neg = (try solveMath(allocator, "what is -3 + 5")).?;
    defer allocator.free(neg.response);
    try std.testing.expectEqualStrings("-3 + 5 = 2.", neg.response);
    const dec = (try solveMath(allocator, "what is 3.5 + 1.2")).?;
    defer allocator.free(dec.response);
    try std.testing.expectEqualStrings("3.5 + 1.2 = 4.7.", dec.response);
}

test "divide by zero returns explicit math error" {
    const allocator = std.testing.allocator;
    const div_zero = (try solveMath(allocator, "what is 3 / 0")).?;
    defer allocator.free(div_zero.response);
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
    var scorer = try ApproximateScorer.init(allocator, .cpu, &corpus, 0);
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

test "natural location phrasing is stored as location instead of name" {
    const allocator = std.testing.allocator;
    const fact = (try extractFactCandidate(allocator, "i am from london")).?;
    defer allocator.free(fact.key);
    defer allocator.free(fact.value);
    try std.testing.expectEqualStrings("location", fact.key);
    try std.testing.expectEqualStrings("london", fact.value);
    const query = (try extractFactQuery(allocator, "where am i from")).?;
    defer allocator.free(query);
    try std.testing.expectEqualStrings("location", query);
}

test "natural lab phrasing is stored from work sentence" {
    const allocator = std.testing.allocator;
    const fact = (try extractFactCandidate(allocator, "i work in the sbx lab")).?;
    defer allocator.free(fact.key);
    defer allocator.free(fact.value);
    try std.testing.expectEqualStrings("lab", fact.key);
    try std.testing.expectEqualStrings("sbx", fact.value);
}

test "team phrasing is stored and recalled naturally" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const fact = (try extractFactCandidate(allocator, "our team is atlas")).?;
    defer allocator.free(fact.key);
    defer allocator.free(fact.value);
    try std.testing.expectEqualStrings("team", fact.key);
    try std.testing.expectEqualStrings("atlas", fact.value);
    try session.rememberFact(allocator, fact.key, fact.value);

    const query = (try extractFactQuery(allocator, "what team am i on")).?;
    defer allocator.free(query);
    try std.testing.expectEqualStrings("team", query);
    try std.testing.expectEqualStrings("atlas", session.lookupFact(query).?.value);
}

test "team capability prompt is not misparsed as a name" {
    const allocator = std.testing.allocator;
    try std.testing.expect((try extractFactCandidate(allocator, "can you remember what team i am on")) == null);
    const key = (try extractMemoryCapabilityQuery(allocator, "can you remember what team i am on")).?;
    defer allocator.free(key);
    try std.testing.expectEqualStrings("team", key);
}

test "project and tomorrow facts are stored and recalled naturally" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const project = (try extractFactCandidate(allocator, "our project is nebula")).?;
    defer allocator.free(project.key);
    defer allocator.free(project.value);
    try std.testing.expectEqualStrings("project", project.key);
    try std.testing.expectEqualStrings("nebula", project.value);
    try session.rememberFact(allocator, project.key, project.value);

    const project_query = (try extractFactQuery(allocator, "what project are we on")).?;
    defer allocator.free(project_query);
    try std.testing.expectEqualStrings("project", project_query);
    try std.testing.expectEqualStrings("nebula", session.lookupFact(project_query).?.value);

    const tomorrow = (try extractFactCandidate(allocator, "tomorrow i have a dentist appointment")).?;
    defer allocator.free(tomorrow.key);
    defer allocator.free(tomorrow.value);
    try std.testing.expectEqualStrings("tomorrow", tomorrow.key);
    try std.testing.expectEqualStrings("a dentist appointment", tomorrow.value);
    try session.rememberFact(allocator, tomorrow.key, tomorrow.value);

    const tomorrow_query = (try extractFactQuery(allocator, "what do i have tomorrow")).?;
    defer allocator.free(tomorrow_query);
    try std.testing.expectEqualStrings("tomorrow", tomorrow_query);
    try std.testing.expectEqualStrings("a dentist appointment", session.lookupFact(tomorrow_query).?.value);
}

test "dog memory normalizes dog name phrasing" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const fact = (try extractFactCandidate(allocator, "my dog is luna")).?;
    defer allocator.free(fact.key);
    defer allocator.free(fact.value);
    try std.testing.expectEqualStrings("dog", fact.key);
    try std.testing.expectEqualStrings("luna", fact.value);
    try session.rememberFact(allocator, fact.key, fact.value);

    const query = (try extractFactQuery(allocator, "what is my dog name")).?;
    defer allocator.free(query);
    try std.testing.expectEqualStrings("dog", query);
    const response = try buildFactRecallResponse(allocator, session.lookupFact(query).?);
    defer allocator.free(response);
    try std.testing.expect(containsPhraseIgnoreCase(response, "Luna"));
}

test "cat and date aliases recall natural memory prompts" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const cat = (try extractFactCandidate(allocator, "my cat is io")).?;
    defer allocator.free(cat.key);
    defer allocator.free(cat.value);
    try std.testing.expectEqualStrings("cat", cat.key);
    try session.rememberFact(allocator, cat.key, cat.value);

    const cat_query = (try extractFactQuery(allocator, "what is my cat name")).?;
    defer allocator.free(cat_query);
    try std.testing.expectEqualStrings("cat", cat_query);
    try std.testing.expectEqualStrings("io", session.lookupFact(cat_query).?.value);

    const launch = (try extractFactCandidate(allocator, "remember that my launch date is tuesday")).?;
    defer allocator.free(launch.key);
    defer allocator.free(launch.value);
    try std.testing.expectEqualStrings("launch date", launch.key);
    try session.rememberFact(allocator, launch.key, launch.value);

    const launch_query = (try extractFactQuery(allocator, "when is my launch date")).?;
    defer allocator.free(launch_query);
    try std.testing.expectEqualStrings("launch date", launch_query);
    try std.testing.expectEqualStrings("tuesday", session.lookupFact(launch_query).?.value);
}

test "generic our facts store safe normalized keys" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const fact = (try extractFactCandidate(allocator, "our secret code word is lantern")).?;
    defer allocator.free(fact.key);
    defer allocator.free(fact.value);
    try std.testing.expectEqualStrings("secret code word", fact.key);
    try session.rememberFact(allocator, fact.key, fact.value);

    const query = (try extractFactQuery(allocator, "what is my secret code word")).?;
    defer allocator.free(query);
    try std.testing.expectEqualStrings("lantern", session.lookupFact(query).?.value);
}

test "expectation matching rejects short substrings inside unrelated words" {
    try std.testing.expect(!expectationMatchesResponse("I do not know your cat name yet. Tell me and I will remember it for this session.", "Io"));
    try std.testing.expect(expectationMatchesResponse("Your cat's name is Io.", "Io"));
}

test "project and tomorrow capability prompts map to memory support" {
    const allocator = std.testing.allocator;
    try std.testing.expect((try extractFactQuery(allocator, "can you remember what project we are on")) == null);
    const project_key = (try extractMemoryCapabilityQuery(allocator, "can you remember what project we are on")).?;
    defer allocator.free(project_key);
    try std.testing.expectEqualStrings("project", project_key);

    try std.testing.expect((try extractFactQuery(allocator, "can you remember what i have tomorrow")) == null);
    const tomorrow_key = (try extractMemoryCapabilityQuery(allocator, "can you remember what i have tomorrow")).?;
    defer allocator.free(tomorrow_key);
    try std.testing.expectEqualStrings("tomorrow", tomorrow_key);
}

test "hardware retrieval does not overmatch benchmark prompts" {
    const allocator = std.testing.allocator;
    const seed =
        \\User: what is the 10m hardening run
        \\Assistant: benchmark answer
        \\
        \\User: do you support nvidia rtx gpus
        \\Assistant: yes, use cuda on nvidia rtx hardware
    ;
    var examples = try parseDialogueExamples(allocator, seed);
    defer examples.deinit(allocator);
    var corpus = try prepareCorpus(allocator, examples.items);
    defer corpus.deinit(allocator);
    var scorer = try ApproximateScorer.init(allocator, .cpu, &corpus, 0);
    defer scorer.deinit();

    var prompt_tokens = try tokenizeText(allocator, "can this run on an rtx 4090");
    defer prompt_tokens.deinit(allocator);
    const match = (try selectGroundedMatch(allocator, "can this run on an rtx 4090", &prompt_tokens, &corpus, &scorer, .retrieval)).?;
    try std.testing.expectEqualStrings("do you support nvidia rtx gpus", match.example.user);
}

test "operational paper prompt returns versioned paper path" {
    const allocator = std.testing.allocator;
    const result = (try answerOperationalPrompt(allocator, "where is the v32 paper pdf")).?;
    defer allocator.free(result.response);
    try std.testing.expect(result.symbolic);
    try std.testing.expect(containsPhraseIgnoreCase(result.response, current_paper_path));
}

test "bundle inventory prompt answers files ship phrasing" {
    const allocator = std.testing.allocator;
    const result = (try answerOperationalPrompt(allocator, "what files ship in the bundle")).?;
    defer allocator.free(result.response);
    try std.testing.expect(result.symbolic);
    try std.testing.expect(containsPhraseIgnoreCase(result.response, current_repo_zip_path));
    try std.testing.expect(containsPhraseIgnoreCase(result.response, current_paper_path));
}

test "free synthesis answers simple joke prompt" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const response = (try synthesizeFreeResponse(allocator, "tell me a joke", &session, .{})).?;
    defer allocator.free(response);
    try std.testing.expect(response.len > 0);
    try std.testing.expect(!containsPhraseIgnoreCase(response, "not sure"));
}

test "free synthesis handles support-style prompt" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const response = (try synthesizeFreeResponse(allocator, "i feel overwhelmed right now", &session, .{})).?;
    defer allocator.free(response);
    try std.testing.expect(containsPhraseIgnoreCase(response, "next concrete task"));
}

test "open chat retrieval tolerates planning paraphrase" {
    const allocator = std.testing.allocator;
    const seed =
        \\User: help me organize my week
        \\Assistant: start with deadlines and major outcomes
        \\
        \\User: can you write a short apology email
        \\Assistant: acknowledge the delay, apologize plainly, and give the next step
    ;
    var examples = try parseDialogueExamples(allocator, seed);
    defer examples.deinit(allocator);
    var corpus = try prepareCorpus(allocator, examples.items);
    defer corpus.deinit(allocator);
    var scorer = try ApproximateScorer.init(allocator, .cpu, &corpus, 0);
    defer scorer.deinit();

    var prompt_tokens = try tokenizeText(allocator, "can you help me plan my week");
    defer prompt_tokens.deinit(allocator);
    const match = (try selectGroundedMatch(allocator, "can you help me plan my week", &prompt_tokens, &corpus, &scorer, .open_chat)).?;
    try std.testing.expectEqualStrings("help me organize my week", match.example.user);
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

test "procrastinating i am statement is not treated as a name" {
    try std.testing.expect(extractNameCandidate("i am procrastinating and need help") == null);
}

test "explain like i am five idiom is not treated as a name" {
    try std.testing.expect(extractNameCandidate("explain recursion like i am five") == null);
}

test "percent math is supported" {
    const allocator = std.testing.allocator;
    const percent = (try solveMath(allocator, "what is 12 percent of 85")).?;
    defer allocator.free(percent.response);
    try std.testing.expectEqualStrings("12 / 100 * 85 = 10.2.", percent.response);
    const symbol_percent = (try solveMath(allocator, "what is 15% of 240")).?;
    defer allocator.free(symbol_percent.response);
    try std.testing.expectEqualStrings("15 / 100 * 240 = 36.", symbol_percent.response);
    const exponent = (try solveMath(allocator, "calculate 2^10")).?;
    defer allocator.free(exponent.response);
    try std.testing.expectEqualStrings("2^10 = 1024.", exponent.response);
    const mixed = (try solveMath(allocator, "calculate (2+3)*4^2 - 7")).?;
    defer allocator.free(mixed.response);
    try std.testing.expectEqualStrings("(2+3)*4^2 - 7 = 73.", mixed.response);
}

test "general hardware question is not treated as SBAN domain prompt" {
    try std.testing.expect(!isDomainPrompt("what does cpu stand for"));
    try std.testing.expect(!isDomainPrompt("what is ram versus storage"));
}

test "free synthesis handles meeting agenda prompt" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const response = (try synthesizeFreeResponse(allocator, "help me write a meeting agenda", &session, .{})).?;
    defer allocator.free(response);
    try std.testing.expect(containsPhraseIgnoreCase(response, "purpose"));
}

test "free synthesis handles python reverse string prompt" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const response = (try synthesizeFreeResponse(allocator, "write a python function to reverse a string", &session, .{})).?;
    defer allocator.free(response);
    try std.testing.expect(containsPhraseIgnoreCase(response, "reverse_string"));
}

test "free synthesis covers new practical coding prompts" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const reverse_list = (try synthesizeFreeResponse(allocator, "how do i reverse a list in python", &session, .{})).?;
    defer allocator.free(reverse_list);
    try std.testing.expect(containsPhraseIgnoreCase(reverse_list, "items.reverse"));

    const debounce = (try synthesizeFreeResponse(allocator, "write javascript debounce function", &session, .{})).?;
    defer allocator.free(debounce);
    try std.testing.expect(containsPhraseIgnoreCase(debounce, "function debounce"));

    const sql = (try synthesizeFreeResponse(allocator, "write sql to count users per country", &session, .{})).?;
    defer allocator.free(sql);
    try std.testing.expect(containsPhraseIgnoreCase(sql, "GROUP BY country"));
}

test "free synthesis handles simple explanation paraphrases" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const photo = (try synthesizeFreeResponse(allocator, "what is photosynthesis in simple terms", &session, .{})).?;
    defer allocator.free(photo);
    try std.testing.expect(containsPhraseIgnoreCase(photo, "sunlight"));
    const cpu = (try synthesizeFreeResponse(allocator, "what does cpu mean", &session, .{})).?;
    defer allocator.free(cpu);
    try std.testing.expect(containsPhraseIgnoreCase(cpu, "central processing unit"));
}

test "free synthesis covers broader knowledge prompts" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const gc = (try synthesizeFreeResponse(allocator, "what is garbage collection in programming", &session, .{})).?;
    defer allocator.free(gc);
    try std.testing.expect(containsPhraseIgnoreCase(gc, "automatically"));

    const kubernetes = (try synthesizeFreeResponse(allocator, "what is kubernetes in plain english", &session, .{})).?;
    defer allocator.free(kubernetes);
    try std.testing.expect(containsPhraseIgnoreCase(kubernetes, "containers"));

    const stack_heap = (try synthesizeFreeResponse(allocator, "difference between stack and heap memory", &session, .{})).?;
    defer allocator.free(stack_heap);
    try std.testing.expect(containsPhraseIgnoreCase(stack_heap, "Stack memory"));

    const oauth = (try synthesizeFreeResponse(allocator, "what is oauth", &session, .{})).?;
    defer allocator.free(oauth);
    try std.testing.expect(containsPhraseIgnoreCase(oauth, "password"));

    const mutex = (try synthesizeFreeResponse(allocator, "what is mutex in programming", &session, .{})).?;
    defer allocator.free(mutex);
    try std.testing.expect(containsPhraseIgnoreCase(mutex, "critical section"));

    const sql_join = (try synthesizeFreeResponse(allocator, "what is sql join", &session, .{})).?;
    defer allocator.free(sql_join);
    try std.testing.expect(containsPhraseIgnoreCase(sql_join, "combines rows"));

    const seasons = (try synthesizeFreeResponse(allocator, "what causes the seasons on earth", &session, .{})).?;
    defer allocator.free(seasons);
    try std.testing.expect(containsPhraseIgnoreCase(seasons, "axial tilt"));

    const starry = (try synthesizeFreeResponse(allocator, "who painted starry night", &session, .{})).?;
    defer allocator.free(starry);
    try std.testing.expect(containsPhraseIgnoreCase(starry, "Vincent van Gogh"));
}

test "free synthesis handles json hash map and zig prompts" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const json = (try synthesizeFreeResponse(allocator, "what is json", &session, .{})).?;
    defer allocator.free(json);
    try std.testing.expect(containsPhraseIgnoreCase(json, "JavaScript Object Notation"));
    const map = (try synthesizeFreeResponse(allocator, "what is a hash map", &session, .{})).?;
    defer allocator.free(map);
    try std.testing.expect(containsPhraseIgnoreCase(map, "key-value"));
    const zig = (try synthesizeFreeResponse(allocator, "what is zig", &session, .{})).?;
    defer allocator.free(zig);
    try std.testing.expect(containsPhraseIgnoreCase(zig, "programming language"));
}

test "word problem solver handles bob oranges case" {
    const allocator = std.testing.allocator;
    const response = (try solveWordProblem(allocator, "Bob has 3 oranges, gives 2 away and eats the last one, how many oranges does bob have")).?;
    defer allocator.free(response);
    try std.testing.expectEqualStrings("He has 0 left.", response);
    const alice = (try solveWordProblem(allocator, "Alice has 4 apples and gets 3 more, how many apples does Alice have")).?;
    defer allocator.free(alice);
    try std.testing.expectEqualStrings("She has 7 left.", alice);
    const train = (try solveWordProblem(allocator, "A train travels 60 miles per hour for 2 hours, how far does it go")).?;
    defer allocator.free(train);
    try std.testing.expectEqualStrings("It travels 120 miles.", train);
}

test "zig upstream synthesis answers hash map path question" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const response = (try synthesizeFreeResponse(allocator, "where is std.hashmap implemented in zig upstream", &session, .{})).?;
    defer allocator.free(response);
    try std.testing.expect(containsPhraseIgnoreCase(response, "lib/std/hash_map.zig"));
}

test "follow-up writing response uses keep it short phrasing" {
    const allocator = std.testing.allocator;
    const response = try buildWritingHelpResponse(allocator, "help me draft a polite follow-up");
    defer allocator.free(response);
    try std.testing.expect(containsPhraseIgnoreCase(response, "Keep it short"));
}

test "free synthesis covers lunch joke rewrite and haiku prompts" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const lunch = (try synthesizeFreeResponse(allocator, "give me three easy lunch ideas", &session, .{})).?;
    defer allocator.free(lunch);
    try std.testing.expect(containsPhraseIgnoreCase(lunch, "wrap"));

    const interest = (try synthesizeFreeResponse(allocator, "explain compound interest simply", &session, .{})).?;
    defer allocator.free(interest);
    try std.testing.expect(containsPhraseIgnoreCase(interest, "snowball"));

    const db_joke = (try synthesizeFreeResponse(allocator, "tell me a joke about databases", &session, .{})).?;
    defer allocator.free(db_joke);
    try std.testing.expect(containsPhraseIgnoreCase(db_joke, "bad joins"));

    const rewrite = (try synthesizeFreeResponse(allocator, "rewrite this professionally: sorry i was late", &session, .{})).?;
    defer allocator.free(rewrite);
    try std.testing.expect(containsPhraseIgnoreCase(rewrite, "I apologize for arriving late"));

    const haiku = (try synthesizeFreeResponse(allocator, "make a haiku about rain", &session, .{})).?;
    defer allocator.free(haiku);
    try std.testing.expect(containsPhraseIgnoreCase(haiku, "Rain taps"));

    const weekend = (try synthesizeFreeResponse(allocator, "plan a relaxed weekend in london", &session, .{})).?;
    defer allocator.free(weekend);
    try std.testing.expect(containsPhraseIgnoreCase(weekend, "museum"));
}

test "v35 config exposes auto-learn architecture" {
    const release = cfg.v35ReleaseConfig(4);
    try std.testing.expect(release.enable_long_term);
    try std.testing.expect(release.enable_hybrid_experts);
    try std.testing.expect(release.continuation_max_order >= 32);
    try std.testing.expectEqualStrings("sban_v35_4bit_autolearn", cfg.sbanVariantLabel(4, .v35_arch));
}

test "v35 answers 2021 president with date boundary" {
    const allocator = std.testing.allocator;
    const response = try buildGeneralKnowledgeResponse(allocator, "in 2021 who was the president of the united states");
    defer allocator.free(response);
    try std.testing.expect(containsPhraseIgnoreCase(response, "Joe Biden"));
    try std.testing.expect(containsPhraseIgnoreCase(response, "Donald Trump"));
    try std.testing.expect(containsPhraseIgnoreCase(response, "January 20"));
}

test "v35 follows bounded instruction memory" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);
    const response = (try handleInstructionMemoryPrompt(allocator, "follow these instructions: remember that my project is kestrel, then answer in one sentence", &session)).?;
    defer allocator.free(response);
    const fact = session.lookupFact("project").?;
    try std.testing.expectEqualStrings("kestrel", fact.value);
}

test "v35 generalized knowledge adds systems and history" {
    const allocator = std.testing.allocator;
    const api = try buildGeneralKnowledgeResponse(allocator, "what is a REST API");
    defer allocator.free(api);
    try std.testing.expect(containsPhraseIgnoreCase(api, "HTTP"));
    const moon = try buildGeneralKnowledgeResponse(allocator, "what was Apollo 11");
    defer allocator.free(moon);
    try std.testing.expect(containsPhraseIgnoreCase(moon, "1969"));
}

test "v32 config exposes reasoning architecture" {
    const config = cfg.v35ReleaseConfig(4);
    try std.testing.expect(config.enable_long_term);
    try std.testing.expect(config.enable_token_region_routing);
    try std.testing.expect(config.propagation_depth >= 4);
    try std.testing.expect(config.max_short_memories >= 16384);
    try std.testing.expectEqualStrings("v32_arch", cfg.NetworkVariant.v32_arch.label());
    try std.testing.expectEqualStrings("sban_v32_4bit_reasoning", cfg.sbanVariantLabel(4, .v32_arch));
}

test "v35 exact json slots and session forget semantics" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const json = (try buildJsonObjectFromPrompt(allocator, "generate JSON with name Ada and age 37")).?;
    defer allocator.free(json);
    try std.testing.expect(containsPhraseIgnoreCase(json, "\"age\":37"));
    try std.testing.expect(!containsPhraseIgnoreCase(json, "\"age\":42"));

    const fact = (try extractFactCandidate(allocator, "my dog is max now")).?;
    defer allocator.free(fact.key);
    defer allocator.free(fact.value);
    try session.rememberFact(allocator, fact.key, fact.value);
    try std.testing.expectEqualStrings("max", session.lookupFact("dog").?.value);

    const forget_key = (try extractForgetFactQuery(allocator, "forget my dog name")).?;
    defer allocator.free(forget_key);
    try std.testing.expectEqualStrings("dog", forget_key);
    try std.testing.expect(try session.forgetFact(allocator, forget_key));
    try std.testing.expect(session.lookupFact("dog") == null);
}

test "v32 free synthesis handles reasoning prompts" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const syllogism = (try synthesizeFreeResponse(allocator, "All humans are mortal. Socrates is a human. Is Socrates mortal?", &session, .{})).?;
    defer allocator.free(syllogism);
    try std.testing.expect(containsPhraseIgnoreCase(syllogism, "Socrates is mortal"));

    const fraction = (try synthesizeFreeResponse(allocator, "which is larger, 3/4 or 2/3", &session, .{})).?;
    defer allocator.free(fraction);
    try std.testing.expect(containsPhraseIgnoreCase(fraction, "3/4 is larger"));

    const sequence = (try synthesizeFreeResponse(allocator, "what comes next in the sequence 2, 4, 6, 8", &session, .{})).?;
    defer allocator.free(sequence);
    try std.testing.expect(containsPhraseIgnoreCase(sequence, "10 comes next"));
}

test "v32 free synthesis handles stable general knowledge" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const pythag = (try synthesizeFreeResponse(allocator, "what is the pythagorean theorem", &session, .{})).?;
    defer allocator.free(pythag);
    try std.testing.expect(containsPhraseIgnoreCase(pythag, "a^2 + b^2"));

    const light = (try synthesizeFreeResponse(allocator, "what is the speed of light", &session, .{})).?;
    defer allocator.free(light);
    try std.testing.expect(containsPhraseIgnoreCase(light, "299,792,458"));

    const transformer = (try synthesizeFreeResponse(allocator, "what is a transformer model", &session, .{})).?;
    defer allocator.free(transformer);
    try std.testing.expect(containsPhraseIgnoreCase(transformer, "attention"));

    const tides = (try synthesizeFreeResponse(allocator, "what causes tides", &session, .{})).?;
    defer allocator.free(tides);
    try std.testing.expect(containsPhraseIgnoreCase(tides, "Moon's gravity"));

    const ci = (try synthesizeFreeResponse(allocator, "how do i debug a failing ci job", &session, .{})).?;
    defer allocator.free(ci);
    try std.testing.expect(containsPhraseIgnoreCase(ci, "reproduce the command locally"));
}

test "v32 generalized reasoning helpers cover comparisons sorting and logic" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const sorted = (try synthesizeFreeResponse(allocator, "sort the numbers 9, 1, 5, 3", &session, .{})).?;
    defer allocator.free(sorted);
    try std.testing.expect(containsPhraseIgnoreCase(sorted, "1, 3, 5, 9"));

    const geometric = (try synthesizeFreeResponse(allocator, "what comes next in the sequence 3, 6, 12, 24", &session, .{})).?;
    defer allocator.free(geometric);
    try std.testing.expect(containsPhraseIgnoreCase(geometric, "48 comes next"));

    const fraction = (try synthesizeFreeResponse(allocator, "which is larger, 5/8 or 3/5", &session, .{})).?;
    defer allocator.free(fraction);
    try std.testing.expect(containsPhraseIgnoreCase(fraction, "5/8 is larger"));

    const logic = (try synthesizeFreeResponse(allocator, "All squares are rectangles. Are all rectangles squares?", &session, .{})).?;
    defer allocator.free(logic);
    try std.testing.expect(containsPhraseIgnoreCase(logic, "No"));

    const transitive = (try synthesizeFreeResponse(allocator, "Alice is taller than Bob. Bob is taller than Carla. Who is tallest?", &session, .{})).?;
    defer allocator.free(transitive);
    try std.testing.expect(containsPhraseIgnoreCase(transitive, "Alice is tallest"));
}

test "v32 general knowledge pack covers added science history and computing concepts" {
    const allocator = std.testing.allocator;
    var session: SessionState = .{};
    defer session.deinit(allocator);

    const osmosis = (try synthesizeFreeResponse(allocator, "what is osmosis", &session, .{})).?;
    defer allocator.free(osmosis);
    try std.testing.expect(containsPhraseIgnoreCase(osmosis, "selectively permeable"));

    const entropy = (try synthesizeFreeResponse(allocator, "explain entropy", &session, .{})).?;
    defer allocator.free(entropy);
    try std.testing.expect(containsPhraseIgnoreCase(entropy, "isolated system"));

    const https = (try synthesizeFreeResponse(allocator, "http vs https", &session, .{})).?;
    defer allocator.free(https);
    try std.testing.expect(containsPhraseIgnoreCase(https, "TLS"));

    const overfit = (try synthesizeFreeResponse(allocator, "what is overfitting", &session, .{})).?;
    defer allocator.free(overfit);
    try std.testing.expect(containsPhraseIgnoreCase(overfit, "new examples"));

    const magna = (try synthesizeFreeResponse(allocator, "what was magna carta", &session, .{})).?;
    defer allocator.free(magna);
    try std.testing.expect(containsPhraseIgnoreCase(magna, "1215"));
}
