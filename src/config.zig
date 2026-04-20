const std = @import("std");

pub const max_segments: usize = 8;
pub const score_scale: i32 = 128;
pub const invalid_region: u16 = std.math.maxInt(u16);
pub const default_bit_widths = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
pub const default_ablation_bits: u8 = 4;
pub const default_stress_bits: u8 = 4;

pub const CorpusMode = enum {
    prefix,
    drift,
};

pub const NetworkVariant = enum {
    default,
    no_bridge,
    fixed_capacity,
    single_region,
    no_reputation,

    pub fn label(self: NetworkVariant) []const u8 {
        return switch (self) {
            .default => "default",
            .no_bridge => "no_bridge",
            .fixed_capacity => "fixed_capacity",
            .single_region => "single_region",
            .no_reputation => "no_reputation",
        };
    }
};

pub fn sbanBitLabel(bits: u8) []const u8 {
    return switch (bits) {
        1 => "sban_v4_1bit",
        2 => "sban_v4_2bit",
        3 => "sban_v4_3bit",
        4 => "sban_v4_4bit",
        5 => "sban_v4_5bit",
        6 => "sban_v4_6bit",
        7 => "sban_v4_7bit",
        8 => "sban_v4_8bit",
        else => "sban_v4_custom",
    };
}

pub fn sbanVariantLabel(bits: u8, variant: NetworkVariant) []const u8 {
    if (variant == .default) return sbanBitLabel(bits);
    return switch (bits) {
        1 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v4_1bit_no_bridge",
            .fixed_capacity => "sban_v4_1bit_fixed_capacity",
            .single_region => "sban_v4_1bit_single_region",
            .no_reputation => "sban_v4_1bit_no_reputation",
        },
        2 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v4_2bit_no_bridge",
            .fixed_capacity => "sban_v4_2bit_fixed_capacity",
            .single_region => "sban_v4_2bit_single_region",
            .no_reputation => "sban_v4_2bit_no_reputation",
        },
        3 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v4_3bit_no_bridge",
            .fixed_capacity => "sban_v4_3bit_fixed_capacity",
            .single_region => "sban_v4_3bit_single_region",
            .no_reputation => "sban_v4_3bit_no_reputation",
        },
        4 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v4_4bit_no_bridge",
            .fixed_capacity => "sban_v4_4bit_fixed_capacity",
            .single_region => "sban_v4_4bit_single_region",
            .no_reputation => "sban_v4_4bit_no_reputation",
        },
        5 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v4_5bit_no_bridge",
            .fixed_capacity => "sban_v4_5bit_fixed_capacity",
            .single_region => "sban_v4_5bit_single_region",
            .no_reputation => "sban_v4_5bit_no_reputation",
        },
        6 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v4_6bit_no_bridge",
            .fixed_capacity => "sban_v4_6bit_fixed_capacity",
            .single_region => "sban_v4_6bit_single_region",
            .no_reputation => "sban_v4_6bit_no_reputation",
        },
        7 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v4_7bit_no_bridge",
            .fixed_capacity => "sban_v4_7bit_fixed_capacity",
            .single_region => "sban_v4_7bit_single_region",
            .no_reputation => "sban_v4_7bit_no_reputation",
        },
        8 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v4_8bit_no_bridge",
            .fixed_capacity => "sban_v4_8bit_fixed_capacity",
            .single_region => "sban_v4_8bit_single_region",
            .no_reputation => "sban_v4_8bit_no_reputation",
        },
        else => "sban_v4_custom_variant",
    };
}

pub const NetworkConfig = struct {
    vocab_size: u16 = 256,
    weight_bits: u8 = 4,
    history_lags: u8 = 8,
    max_lag_parents: u8 = 5,
    propagation_depth: u8 = 2,
    max_hidden_per_hop: u16 = 32,
    max_carry_memories: u16 = 20,
    max_parents_per_new_memory: u16 = 8,
    min_parents_for_birth: u16 = 3,
    birth_margin: i32 = 22,
    birth_cooldown: u16 = 1,
    prune_interval: u16 = 2048,
    synapse_init_permanence: u8 = 3,
    synapse_max_permanence: u8 = 16,
    synapse_bad_reputation: i16 = -12,
    short_idle_prune: u32 = 4096,
    long_idle_prune: u32 = 32768,
    promotion_support: u16 = 10,
    promotion_reputation: i16 = 18,
    promotion_precision_ppm: u16 = 620,
    demotion_reputation: i16 = -10,
    demotion_precision_ppm: u16 = 480,
    neuron_min_utility: i16 = -6,
    short_min_reputation: i16 = -12,
    long_min_reputation: i16 = -20,
    max_short_memories: u32 = 8192,
    max_long_memories: u32 = 768,
    min_short_survivors: u16 = 192,
    min_long_survivors: u16 = 48,
    max_outgoing_per_node: u16 = 256,
    min_outgoing_to_keep: u16 = 2,
    long_term_bonus_ppm: u16 = 1040,
    long_term_threshold_discount_ppm: u16 = 940,
    max_regions: u16 = 8,
    initial_regions: u16 = 1,
    initial_short_target: u32 = 2048,
    min_short_target: u32 = 256,
    region_split_load: u16 = 1536,
    region_min_survivors: u16 = 2,
    elasticity_interval: u16 = 2048,
    growth_surprise_ppm: u32 = 540_000,
    shrink_surprise_ppm: u32 = 470_000,
    growth_utilization_ppm: u32 = 700_000,
    growth_birth_threshold: u16 = 128,
    shrink_birth_threshold: u16 = 12,
    growth_step: u16 = 512,
    shrink_step: u16 = 128,
    bridge_threshold_bonus: i32 = 128,
    bridge_activation_bonus: i32 = 24,
    bridge_bonus_ppm: u16 = 1000,
    bridge_birth_min_diversity: u8 = 2,
    enable_long_term: bool = true,
    use_reputation: bool = true,
    use_homeostasis: bool = true,
    enable_elasticity: bool = true,
    enable_bridge_memories: bool = true,
};

pub fn configForVariant(bits: u8, variant: NetworkVariant) NetworkConfig {
    var config = NetworkConfig{ .weight_bits = bits };
    switch (variant) {
        .default => {},
        .no_bridge => {
            config.enable_bridge_memories = false;
        },
        .fixed_capacity => {
            config.enable_elasticity = false;
            config.initial_short_target = 4096;
            config.min_short_target = 4096;
            config.initial_regions = 4;
            config.max_regions = 4;
        },
        .single_region => {
            config.initial_regions = 1;
            config.max_regions = 1;
            config.region_split_load = std.math.maxInt(u16);
        },
        .no_reputation => {
            config.use_reputation = false;
            config.promotion_reputation = 0;
            config.short_min_reputation = -64;
            config.long_min_reputation = -64;
            config.synapse_bad_reputation = -64;
        },
    }
    return config;
}

pub const CorpusConfig = struct {
    dataset_path: []const u8,
    mode: CorpusMode = .prefix,
    segment_len: usize = 50_000,
    segment_count: u8 = 4,
    checkpoint_interval: usize = 5_000,
    rolling_window: usize = 8_192,

    pub fn totalPredictions(self: CorpusConfig) usize {
        return self.segment_len * self.segment_count;
    }

    pub fn driftOffsets(self: CorpusConfig) [4]usize {
        _ = self;
        return .{ 0, 25_000_000, 50_000_000, 75_000_000 };
    }
};

test "bit labels cover default bit widths" {
    for (default_bit_widths) |bits| {
        try std.testing.expect(std.mem.startsWith(u8, sbanBitLabel(bits), "sban_v4_"));
    }
}
