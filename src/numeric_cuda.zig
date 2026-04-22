const std = @import("std");
const builtin = @import("builtin");

pub const NumericCudaUnavailable = error{
    NoCudaLoader,
    NoCudaDevice,
    InvalidKernel,
    CudaFailure,
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
const CuLaunchKernelFn = *const fn(cu_function, u32, u32, u32, u32, u32, u32, u32, ?*anyopaque, *const [4]?*anyopaque, ?*const anyopaque) callconv(.c) cu_result;
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

pub const SparseScoreCudaRuntime = struct {
    allocator: std.mem.Allocator,
    lib: DynamicLibrary,
    api: CudaApi,
    context: cu_context,
    module: cu_module,
    function: cu_function,
    index_buffer: cu_device_ptr = 0,
    value_buffer: cu_device_ptr = 0,
    output_buffer: cu_device_ptr,
    capacity: usize = 0,
    output_len: usize,
    zero_output: []i32,
    device_name: []u8,
    platform_name: []u8,

    pub fn init(allocator: std.mem.Allocator, output_len: usize) !SparseScoreCudaRuntime {
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
        try checkCuda(api, api.module_load_data_ex(&module, @ptrCast(cuda_sparse_score_kernel_ptx.ptr), 0, null, null));
        errdefer _ = api.module_unload(module);
        errdefer _ = api.ctx_destroy(context);

        var function: cu_function = null;
        try checkCuda(api, api.module_get_function(&function, module, "accumulate_sparse_scores_cuda"));

        var output_buffer: cu_device_ptr = 0;
        try checkCuda(api, api.mem_alloc(&output_buffer, output_len * @sizeOf(i32)));
        errdefer _ = api.mem_free(output_buffer);

        const zero_output = try allocator.alloc(i32, output_len);
        errdefer allocator.free(zero_output);
        @memset(zero_output, 0);

        return .{
            .allocator = allocator,
            .lib = lib,
            .api = api,
            .context = context,
            .module = module,
            .function = function,
            .output_buffer = output_buffer,
            .output_len = output_len,
            .zero_output = zero_output,
            .device_name = device_name,
            .platform_name = platform_name,
        };
    }

    pub fn deinit(self: *SparseScoreCudaRuntime) void {
        if (self.value_buffer != 0) _ = self.api.mem_free(self.value_buffer);
        if (self.index_buffer != 0) _ = self.api.mem_free(self.index_buffer);
        _ = self.api.mem_free(self.output_buffer);
        _ = self.api.module_unload(self.module);
        _ = self.api.ctx_destroy(self.context);
        self.lib.close();
        self.allocator.free(self.zero_output);
        self.allocator.free(self.device_name);
        self.allocator.free(self.platform_name);
    }

    fn ensureCapacity(self: *SparseScoreCudaRuntime, contribution_count: usize) !void {
        if (contribution_count <= self.capacity) return;
        if (self.value_buffer != 0) _ = self.api.mem_free(self.value_buffer);
        if (self.index_buffer != 0) _ = self.api.mem_free(self.index_buffer);
        self.index_buffer = 0;
        self.value_buffer = 0;
        self.capacity = 0;

        var next_capacity = if (self.capacity == 0) contribution_count else self.capacity;
        if (next_capacity < contribution_count) next_capacity = contribution_count;
        var index_buffer: cu_device_ptr = 0;
        try checkCuda(self.api, self.api.mem_alloc(&index_buffer, next_capacity * @sizeOf(u32)));
        errdefer _ = self.api.mem_free(index_buffer);
        var value_buffer: cu_device_ptr = 0;
        try checkCuda(self.api, self.api.mem_alloc(&value_buffer, next_capacity * @sizeOf(i32)));
        self.index_buffer = index_buffer;
        self.value_buffer = value_buffer;
        self.capacity = next_capacity;
    }

    pub fn score(self: *SparseScoreCudaRuntime, indices: []const u32, values: []const i32, output: []i32) !void {
        if (indices.len != values.len or output.len != self.output_len) return error.InvalidArgument;
        @memset(output, 0);
        if (indices.len == 0) return;

        try self.ensureCapacity(indices.len);
        try checkCuda(self.api, self.api.memcpy_htod(self.output_buffer, @ptrCast(self.zero_output.ptr), self.zero_output.len * @sizeOf(i32)));
        try checkCuda(self.api, self.api.memcpy_htod(self.index_buffer, @ptrCast(indices.ptr), indices.len * @sizeOf(u32)));
        try checkCuda(self.api, self.api.memcpy_htod(self.value_buffer, @ptrCast(values.ptr), values.len * @sizeOf(i32)));

        var index_arg = self.index_buffer;
        var value_arg = self.value_buffer;
        var output_arg = self.output_buffer;
        var count_arg: u32 = @intCast(indices.len);
        var kernel_params = [_]?*anyopaque{
            @ptrCast(&index_arg),
            @ptrCast(&value_arg),
            @ptrCast(&output_arg),
            @ptrCast(&count_arg),
        };

        const block_x: u32 = 256;
        const grid_x: u32 = @intCast(@divTrunc(indices.len + block_x - 1, block_x));
        try checkCuda(self.api, self.api.launch_kernel(self.function, grid_x, 1, 1, block_x, 1, 1, 0, null, &kernel_params, null));
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

const cuda_sparse_score_kernel_ptx: [:0]const u8 =
    \\.version 6.0
    \\.target sm_30
    \\.address_size 64
    \\
    \\.visible .entry accumulate_sparse_scores_cuda(
    \\    .param .u64 index_ptr,
    \\    .param .u64 value_ptr,
    \\    .param .u64 out_ptr,
    \\    .param .u32 contribution_count
    \\)
    \\{
    \\    .reg .pred %p<2>;
    \\    .reg .b32 %r<7>;
    \\    .reg .b64 %rd<8>;
    \\
    \\    ld.param.u64 %rd1, [index_ptr];
    \\    ld.param.u64 %rd2, [value_ptr];
    \\    ld.param.u64 %rd3, [out_ptr];
    \\    ld.param.u32 %r1, [contribution_count];
    \\
    \\    mov.u32 %r2, %ctaid.x;
    \\    mov.u32 %r3, %ntid.x;
    \\    mov.u32 %r4, %tid.x;
    \\    mad.lo.s32 %r5, %r2, %r3, %r4;
    \\    setp.ge.u32 %p1, %r5, %r1;
    \\    @%p1 bra DONE;
    \\
    \\    mul.wide.u32 %rd4, %r5, 4;
    \\    add.s64 %rd5, %rd1, %rd4;
    \\    add.s64 %rd6, %rd2, %rd4;
    \\    ld.global.u32 %r6, [%rd5];
    \\    ld.global.s32 %r2, [%rd6];
    \\    mul.wide.u32 %rd7, %r6, 4;
    \\    add.s64 %rd7, %rd3, %rd7;
    \\    atom.global.add.s32 %r3, [%rd7], %r2;
    \\DONE:
    \\    ret;
    \\}
;
