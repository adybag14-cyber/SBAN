const std = @import("std");
const builtin = @import("builtin");

pub const NumericCudaUnavailable = error{
    NoCudaLoader,
    NoCudaDevice,
    InvalidKernel,
    CudaFailure,
    InvalidArgument,
};

pub const cu_result = i32;
pub const cu_device = i32;
pub const cu_context = ?*anyopaque;
pub const cu_module = ?*anyopaque;
pub const cu_function = ?*anyopaque;
pub const cu_device_ptr = u64;

const CuInitFn = *const fn(u32) callconv(.c) cu_result;
const CuDeviceGetCountFn = *const fn(*i32) callconv(.c) cu_result;
const CuDeviceGetFn = *const fn(*cu_device, i32) callconv(.c) cu_result;
const CuDeviceGetNameFn = *const fn([*]u8, i32, cu_device) callconv(.c) cu_result;
const CuCtxCreateFn = *const fn(*cu_context, u32, cu_device) callconv(.c) cu_result;
const CuCtxDestroyFn = *const fn(cu_context) callconv(.c) cu_result;
const CuModuleLoadDataExFn = *const fn(*cu_module, *const anyopaque, u32, ?*const anyopaque, ?*const anyopaque) callconv(.c) cu_result;
const CuModuleGetFunctionFn = *const fn(*cu_function, cu_module, [*:0]const u8) callconv(.c) cu_result;
const CuModuleUnloadFn = *const fn(cu_module) callconv(.c) cu_result;
const CuMemAllocFn = *const fn(*cu_device_ptr, usize) callconv(.c) cu_result;
const CuMemFreeFn = *const fn(cu_device_ptr) callconv(.c) cu_result;
const CuMemcpyHtoDFn = *const fn(cu_device_ptr, *const anyopaque, usize) callconv(.c) cu_result;
const CuMemcpyDtoHFn = *const fn(*anyopaque, cu_device_ptr, usize) callconv(.c) cu_result;
const CuLaunchKernelFn = *const fn(cu_function, u32, u32, u32, u32, u32, u32, u32, ?*anyopaque, ?*anyopaque, ?*const anyopaque) callconv(.c) cu_result;
const CuCtxSynchronizeFn = *const fn() callconv(.c) cu_result;
const CuGetErrorNameFn = *const fn(cu_result, *?[*:0]const u8) callconv(.c) cu_result;
const CuGetErrorStringFn = *const fn(cu_result, *?[*:0]const u8) callconv(.c) cu_result;

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

const DynamicLibrary = if (builtin.os.tag == .windows) WindowsDynamicLibrary else PosixDynamicLibrary;

const WindowsDynamicLibrary = struct {
    handle: ?*anyopaque,

    extern "kernel32" fn LoadLibraryA(path: [*:0]const u8) callconv(.c) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(handle: ?*anyopaque, name: [*:0]const u8) callconv(.c) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(handle: ?*anyopaque) callconv(.c) i32;

    fn open(path: [:0]const u8) !WindowsDynamicLibrary {
        const handle = LoadLibraryA(path.ptr) orelse return NumericCudaUnavailable.NoCudaLoader;
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

fn deviceOffset(base: cu_device_ptr, byte_offset: usize) cu_device_ptr {
    return base + @as(cu_device_ptr, @intCast(byte_offset));
}

pub const NumericCudaRuntime = struct {
    allocator: std.mem.Allocator,
    lib: DynamicLibrary,
    api: CudaApi,
    context: cu_context,
    module: cu_module,
    resident_function: cu_function,
    output_index_buffer: cu_device_ptr,
    output_value_buffer: cu_device_ptr,
    output_count_buffer: cu_device_ptr,
    active_id_buffer: cu_device_ptr = 0,
    active_region_base_buffer: cu_device_ptr = 0,
    active_long_scale_buffer: cu_device_ptr = 0,
    active_bridge_scale_buffer: cu_device_ptr = 0,
    output_buffer: cu_device_ptr,
    active_capacity: usize = 0,
    max_neurons: usize,
    max_outgoing_per_node: usize,
    output_len: usize,
    zero_output: []i32,
    zero_counts: []u32,
    device_name: []u8,
    platform_name: []u8,

    pub fn init(allocator: std.mem.Allocator, output_len: usize, max_neurons: usize, max_outgoing_per_node: usize) !NumericCudaRuntime {
        var lib = try openCudaLibrary();
        errdefer lib.close();
        const api = try loadCudaApi(&lib);

        try checkCuda(api, api.init(0));

        var device_count: i32 = 0;
        try checkCuda(api, api.device_get_count(&device_count));
        if (device_count <= 0) return NumericCudaUnavailable.NoCudaDevice;

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
        try checkCuda(api, api.module_load_data_ex(&module, @ptrCast(cuda_resident_score_kernel_ptx.ptr), 0, null, null));
        errdefer _ = api.module_unload(module);
        errdefer _ = api.ctx_destroy(context);

        var resident_function: cu_function = null;
        try checkCuda(api, api.module_get_function(&resident_function, module, "score_resident_output_edges_cuda"));

        var output_index_buffer: cu_device_ptr = 0;
        try checkCuda(api, api.mem_alloc(&output_index_buffer, max_neurons * max_outgoing_per_node * @sizeOf(u32)));
        errdefer _ = api.mem_free(output_index_buffer);

        var output_value_buffer: cu_device_ptr = 0;
        try checkCuda(api, api.mem_alloc(&output_value_buffer, max_neurons * max_outgoing_per_node * @sizeOf(i32)));
        errdefer _ = api.mem_free(output_value_buffer);
        errdefer _ = api.mem_free(output_index_buffer);

        var output_count_buffer: cu_device_ptr = 0;
        try checkCuda(api, api.mem_alloc(&output_count_buffer, max_neurons * @sizeOf(u32)));
        errdefer _ = api.mem_free(output_count_buffer);
        errdefer _ = api.mem_free(output_value_buffer);
        errdefer _ = api.mem_free(output_index_buffer);

        var output_buffer: cu_device_ptr = 0;
        try checkCuda(api, api.mem_alloc(&output_buffer, output_len * @sizeOf(i32)));
        errdefer _ = api.mem_free(output_buffer);
        errdefer _ = api.mem_free(output_count_buffer);
        errdefer _ = api.mem_free(output_value_buffer);
        errdefer _ = api.mem_free(output_index_buffer);

        const zero_output = try allocator.alloc(i32, output_len);
        errdefer allocator.free(zero_output);
        @memset(zero_output, 0);

        const zero_counts = try allocator.alloc(u32, max_neurons);
        errdefer allocator.free(zero_counts);
        @memset(zero_counts, 0);
        try checkCuda(api, api.memcpy_htod(output_count_buffer, @ptrCast(zero_counts.ptr), zero_counts.len * @sizeOf(u32)));

        return .{
            .allocator = allocator,
            .lib = lib,
            .api = api,
            .context = context,
            .module = module,
            .resident_function = resident_function,
            .output_index_buffer = output_index_buffer,
            .output_value_buffer = output_value_buffer,
            .output_count_buffer = output_count_buffer,
            .output_buffer = output_buffer,
            .max_neurons = max_neurons,
            .max_outgoing_per_node = max_outgoing_per_node,
            .output_len = output_len,
            .zero_output = zero_output,
            .zero_counts = zero_counts,
            .device_name = device_name,
            .platform_name = platform_name,
        };
    }

    pub fn deinit(self: *NumericCudaRuntime) void {
        if (self.active_bridge_scale_buffer != 0) _ = self.api.mem_free(self.active_bridge_scale_buffer);
        if (self.active_long_scale_buffer != 0) _ = self.api.mem_free(self.active_long_scale_buffer);
        if (self.active_region_base_buffer != 0) _ = self.api.mem_free(self.active_region_base_buffer);
        if (self.active_id_buffer != 0) _ = self.api.mem_free(self.active_id_buffer);
        _ = self.api.mem_free(self.output_buffer);
        _ = self.api.mem_free(self.output_count_buffer);
        _ = self.api.mem_free(self.output_value_buffer);
        _ = self.api.mem_free(self.output_index_buffer);
        _ = self.api.module_unload(self.module);
        _ = self.api.ctx_destroy(self.context);
        self.lib.close();
        self.allocator.free(self.zero_output);
        self.allocator.free(self.zero_counts);
        self.allocator.free(self.device_name);
        self.allocator.free(self.platform_name);
    }

    fn ensureActiveCapacity(self: *NumericCudaRuntime, active_count: usize) !void {
        if (active_count <= self.active_capacity) return;
        if (self.active_bridge_scale_buffer != 0) _ = self.api.mem_free(self.active_bridge_scale_buffer);
        if (self.active_long_scale_buffer != 0) _ = self.api.mem_free(self.active_long_scale_buffer);
        if (self.active_region_base_buffer != 0) _ = self.api.mem_free(self.active_region_base_buffer);
        if (self.active_id_buffer != 0) _ = self.api.mem_free(self.active_id_buffer);
        self.active_bridge_scale_buffer = 0;
        self.active_long_scale_buffer = 0;
        self.active_region_base_buffer = 0;
        self.active_id_buffer = 0;
        self.active_capacity = 0;

        var active_id_buffer: cu_device_ptr = 0;
        try checkCuda(self.api, self.api.mem_alloc(&active_id_buffer, active_count * @sizeOf(u32)));
        errdefer _ = self.api.mem_free(active_id_buffer);
        var active_region_base_buffer: cu_device_ptr = 0;
        try checkCuda(self.api, self.api.mem_alloc(&active_region_base_buffer, active_count * @sizeOf(u32)));
        errdefer _ = self.api.mem_free(active_region_base_buffer);
        errdefer _ = self.api.mem_free(active_id_buffer);
        var active_long_scale_buffer: cu_device_ptr = 0;
        try checkCuda(self.api, self.api.mem_alloc(&active_long_scale_buffer, active_count * @sizeOf(u32)));
        errdefer _ = self.api.mem_free(active_long_scale_buffer);
        errdefer _ = self.api.mem_free(active_region_base_buffer);
        errdefer _ = self.api.mem_free(active_id_buffer);
        var active_bridge_scale_buffer: cu_device_ptr = 0;
        try checkCuda(self.api, self.api.mem_alloc(&active_bridge_scale_buffer, active_count * @sizeOf(u32)));

        self.active_id_buffer = active_id_buffer;
        self.active_region_base_buffer = active_region_base_buffer;
        self.active_long_scale_buffer = active_long_scale_buffer;
        self.active_bridge_scale_buffer = active_bridge_scale_buffer;
        self.active_capacity = active_count;
    }

    pub fn syncNeuronOutputEdges(self: *NumericCudaRuntime, neuron_id: u32, logical_indices: []const u32, base_values: []const i32) !void {
        if (logical_indices.len != base_values.len) return NumericCudaUnavailable.InvalidArgument;
        if (logical_indices.len > self.max_outgoing_per_node) return NumericCudaUnavailable.InvalidArgument;
        if (neuron_id >= self.max_neurons) return NumericCudaUnavailable.InvalidArgument;

        const row_offset = @as(usize, neuron_id) * self.max_outgoing_per_node;
        const index_offset = deviceOffset(self.output_index_buffer, row_offset * @sizeOf(u32));
        const value_offset = deviceOffset(self.output_value_buffer, row_offset * @sizeOf(i32));
        const count_offset = deviceOffset(self.output_count_buffer, @as(usize, neuron_id) * @sizeOf(u32));

        if (logical_indices.len != 0) {
            try checkCuda(self.api, self.api.memcpy_htod(index_offset, @ptrCast(logical_indices.ptr), logical_indices.len * @sizeOf(u32)));
            try checkCuda(self.api, self.api.memcpy_htod(value_offset, @ptrCast(base_values.ptr), base_values.len * @sizeOf(i32)));
        }

        var count_value: u32 = @intCast(logical_indices.len);
        try checkCuda(self.api, self.api.memcpy_htod(count_offset, @ptrCast(&count_value), @sizeOf(u32)));
    }

    pub fn scoreResident(
        self: *NumericCudaRuntime,
        active_ids: []const u32,
        active_region_bases: []const u32,
        active_long_scales: []const u32,
        active_bridge_scales: []const u32,
        output: []i32,
    ) !void {
        if (output.len != self.output_len) return NumericCudaUnavailable.InvalidArgument;
        if (active_ids.len != active_region_bases.len or active_ids.len != active_long_scales.len or active_ids.len != active_bridge_scales.len) {
            return NumericCudaUnavailable.InvalidArgument;
        }

        @memset(output, 0);
        if (active_ids.len == 0) return;

        try self.ensureActiveCapacity(active_ids.len);
        try checkCuda(self.api, self.api.memcpy_htod(self.output_buffer, @ptrCast(self.zero_output.ptr), self.zero_output.len * @sizeOf(i32)));
        try checkCuda(self.api, self.api.memcpy_htod(self.active_id_buffer, @ptrCast(active_ids.ptr), active_ids.len * @sizeOf(u32)));
        try checkCuda(self.api, self.api.memcpy_htod(self.active_region_base_buffer, @ptrCast(active_region_bases.ptr), active_region_bases.len * @sizeOf(u32)));
        try checkCuda(self.api, self.api.memcpy_htod(self.active_long_scale_buffer, @ptrCast(active_long_scales.ptr), active_long_scales.len * @sizeOf(u32)));
        try checkCuda(self.api, self.api.memcpy_htod(self.active_bridge_scale_buffer, @ptrCast(active_bridge_scales.ptr), active_bridge_scales.len * @sizeOf(u32)));

        var output_index_arg = self.output_index_buffer;
        var output_value_arg = self.output_value_buffer;
        var output_count_arg = self.output_count_buffer;
        var active_id_arg = self.active_id_buffer;
        var active_region_base_arg = self.active_region_base_buffer;
        var active_long_scale_arg = self.active_long_scale_buffer;
        var active_bridge_scale_arg = self.active_bridge_scale_buffer;
        var output_arg = self.output_buffer;
        var active_count_arg: u32 = @intCast(active_ids.len);
        var max_edges_arg: u32 = @intCast(self.max_outgoing_per_node);
        var kernel_params = [_]?*anyopaque{
            @ptrCast(&output_index_arg),
            @ptrCast(&output_value_arg),
            @ptrCast(&output_count_arg),
            @ptrCast(&active_id_arg),
            @ptrCast(&active_region_base_arg),
            @ptrCast(&active_long_scale_arg),
            @ptrCast(&active_bridge_scale_arg),
            @ptrCast(&output_arg),
            @ptrCast(&active_count_arg),
            @ptrCast(&max_edges_arg),
        };

        const block_x: u32 = if (self.max_outgoing_per_node < 128) @intCast(self.max_outgoing_per_node) else 128;
        const grid_x: u32 = @intCast(active_ids.len);
        try checkCuda(self.api, self.api.launch_kernel(self.resident_function, grid_x, 1, 1, if (block_x == 0) 1 else block_x, 1, 1, 0, null, @ptrCast(&kernel_params), null));
        try checkCuda(self.api, self.api.ctx_synchronize());
        try checkCuda(self.api, self.api.memcpy_dtoh(output.ptr, self.output_buffer, output.len * @sizeOf(i32)));
    }
};

fn openCudaLibrary() !DynamicLibrary {
    if (builtin.os.tag == .windows) {
        return DynamicLibrary.open("nvcuda.dll");
    }
    return DynamicLibrary.open("libcuda.so.1") catch DynamicLibrary.open("libcuda.so");
}

fn loadCudaApi(lib: *DynamicLibrary) !CudaApi {
    return .{
        .init = lib.lookup(CuInitFn, "cuInit") orelse return NumericCudaUnavailable.NoCudaLoader,
        .device_get_count = lib.lookup(CuDeviceGetCountFn, "cuDeviceGetCount") orelse return NumericCudaUnavailable.NoCudaLoader,
        .device_get = lib.lookup(CuDeviceGetFn, "cuDeviceGet") orelse return NumericCudaUnavailable.NoCudaLoader,
        .device_get_name = lib.lookup(CuDeviceGetNameFn, "cuDeviceGetName") orelse return NumericCudaUnavailable.NoCudaLoader,
        .ctx_create = lib.lookup(CuCtxCreateFn, "cuCtxCreate_v2") orelse lib.lookup(CuCtxCreateFn, "cuCtxCreate") orelse return NumericCudaUnavailable.NoCudaLoader,
        .ctx_destroy = lib.lookup(CuCtxDestroyFn, "cuCtxDestroy_v2") orelse lib.lookup(CuCtxDestroyFn, "cuCtxDestroy") orelse return NumericCudaUnavailable.NoCudaLoader,
        .module_load_data_ex = lib.lookup(CuModuleLoadDataExFn, "cuModuleLoadDataEx") orelse return NumericCudaUnavailable.NoCudaLoader,
        .module_get_function = lib.lookup(CuModuleGetFunctionFn, "cuModuleGetFunction") orelse return NumericCudaUnavailable.NoCudaLoader,
        .module_unload = lib.lookup(CuModuleUnloadFn, "cuModuleUnload") orelse return NumericCudaUnavailable.NoCudaLoader,
        .mem_alloc = lib.lookup(CuMemAllocFn, "cuMemAlloc_v2") orelse lib.lookup(CuMemAllocFn, "cuMemAlloc") orelse return NumericCudaUnavailable.NoCudaLoader,
        .mem_free = lib.lookup(CuMemFreeFn, "cuMemFree_v2") orelse lib.lookup(CuMemFreeFn, "cuMemFree") orelse return NumericCudaUnavailable.NoCudaLoader,
        .memcpy_htod = lib.lookup(CuMemcpyHtoDFn, "cuMemcpyHtoD_v2") orelse lib.lookup(CuMemcpyHtoDFn, "cuMemcpyHtoD") orelse return NumericCudaUnavailable.NoCudaLoader,
        .memcpy_dtoh = lib.lookup(CuMemcpyDtoHFn, "cuMemcpyDtoH_v2") orelse lib.lookup(CuMemcpyDtoHFn, "cuMemcpyDtoH") orelse return NumericCudaUnavailable.NoCudaLoader,
        .launch_kernel = lib.lookup(CuLaunchKernelFn, "cuLaunchKernel") orelse return NumericCudaUnavailable.NoCudaLoader,
        .ctx_synchronize = lib.lookup(CuCtxSynchronizeFn, "cuCtxSynchronize") orelse return NumericCudaUnavailable.NoCudaLoader,
        .get_error_name = lib.lookup(CuGetErrorNameFn, "cuGetErrorName"),
        .get_error_string = lib.lookup(CuGetErrorStringFn, "cuGetErrorString"),
    };
}

fn checkCuda(api: CudaApi, result: cu_result) !void {
    if (result == 0) return;
    if (api.get_error_name) |get_error_name| {
        var name_ptr: ?[*:0]const u8 = null;
        if (get_error_name(result, &name_ptr) == 0 and name_ptr != null) {
            std.log.err("CUDA failure {d}: {s}", .{ result, std.mem.sliceTo(name_ptr.?, 0) });
        } else {
            std.log.err("CUDA failure {d}", .{result});
        }
    } else {
        std.log.err("CUDA failure {d}", .{result});
    }
    return NumericCudaUnavailable.CudaFailure;
}

const cuda_resident_score_kernel_ptx: [:0]const u8 =
    \\.version 6.0
    \\.target sm_30
    \\.address_size 64
    \\
    \\.visible .entry score_resident_output_edges_cuda(
    \\    .param .u64 output_index_ptr,
    \\    .param .u64 output_value_ptr,
    \\    .param .u64 output_count_ptr,
    \\    .param .u64 active_id_ptr,
    \\    .param .u64 active_region_base_ptr,
    \\    .param .u64 active_long_scale_ptr,
    \\    .param .u64 active_bridge_scale_ptr,
    \\    .param .u64 out_ptr,
    \\    .param .u32 active_count,
    \\    .param .u32 max_edges
    \\)
    \\{
    \\    .reg .pred %p<3>;
    \\    .reg .b32 %r<24>;
    \\    .reg .b64 %rd<14>;
    \\
    \\    ld.param.u64 %rd1, [output_index_ptr];
    \\    ld.param.u64 %rd2, [output_value_ptr];
    \\    ld.param.u64 %rd3, [output_count_ptr];
    \\    ld.param.u64 %rd4, [active_id_ptr];
    \\    ld.param.u64 %rd5, [active_region_base_ptr];
    \\    ld.param.u64 %rd6, [active_long_scale_ptr];
    \\    ld.param.u64 %rd7, [active_bridge_scale_ptr];
    \\    ld.param.u64 %rd8, [out_ptr];
    \\    ld.param.u32 %r1, [active_count];
    \\    ld.param.u32 %r2, [max_edges];
    \\
    \\    mov.u32 %r3, %ctaid.x;
    \\    mov.u32 %r4, %tid.x;
    \\    mov.u32 %r5, %ntid.x;
    \\    setp.ge.u32 %p1, %r3, %r1;
    \\    @%p1 bra DONE;
    \\
    \\    mul.wide.u32 %rd9, %r3, 4;
    \\    add.s64 %rd10, %rd4, %rd9;
    \\    add.s64 %rd11, %rd5, %rd9;
    \\    add.s64 %rd12, %rd6, %rd9;
    \\    add.s64 %rd13, %rd7, %rd9;
    \\    ld.global.u32 %r6, [%rd10];
    \\    ld.global.u32 %r7, [%rd11];
    \\    ld.global.u32 %r8, [%rd12];
    \\    ld.global.u32 %r9, [%rd13];
    \\
    \\    mul.lo.u32 %r10, %r6, %r2;
    \\    mul.wide.u32 %rd10, %r6, 4;
    \\    add.s64 %rd10, %rd3, %rd10;
    \\    ld.global.u32 %r11, [%rd10];
    \\
    \\LOOP:
    \\    setp.ge.u32 %p2, %r4, %r11;
    \\    @%p2 bra DONE;
    \\    add.u32 %r12, %r10, %r4;
    \\    mul.wide.u32 %rd10, %r12, 4;
    \\    add.s64 %rd11, %rd1, %rd10;
    \\    add.s64 %rd12, %rd2, %rd10;
    \\    ld.global.u32 %r13, [%rd11];
    \\    ld.global.s32 %r14, [%rd12];
    \\    setp.ne.u32 %p2, %r8, 1000;
    \\    @!%p2 bra SKIP_LONG;
    \\    mul.lo.s32 %r14, %r14, %r8;
    \\    div.s32 %r14, %r14, 1000;
    \\SKIP_LONG:
    \\    setp.ne.u32 %p2, %r9, 1000;
    \\    @!%p2 bra SKIP_BRIDGE;
    \\    mul.lo.s32 %r14, %r14, %r9;
    \\    div.s32 %r14, %r14, 1000;
    \\SKIP_BRIDGE:
    \\    add.u32 %r15, %r7, %r13;
    \\    mul.wide.u32 %rd10, %r15, 4;
    \\    add.s64 %rd10, %rd8, %rd10;
    \\    atom.global.add.s32 %r16, [%rd10], %r14;
    \\    add.u32 %r4, %r4, %r5;
    \\    bra LOOP;
    \\DONE:
    \\    ret;
    \\}
;
