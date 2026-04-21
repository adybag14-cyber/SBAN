const std = @import("std");

pub const max_segments: usize = 8;
pub const score_scale: i32 = 128;
pub const invalid_region: u16 = std.math.maxInt(u16);
pub const default_bit_widths = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
pub const default_ablation_bits: u8 = 4;
pub const default_stress_bits: u8 = 4;
pub const default_release_mode: []const u8 = "debug_fallback";

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
        1 => "sban_v17_1bit",
        2 => "sban_v17_2bit",
        3 => "sban_v17_3bit",
        4 => "sban_v17_4bit",
        5 => "sban_v17_5bit",
        6 => "sban_v17_6bit",
        7 => "sban_v17_7bit",
        8 => "sban_v17_8bit",
        else => "sban_v17_custom",
    };
}

pub fn sbanVariantLabel(bits: u8, variant: NetworkVariant) []const u8 {
    if (variant == .default) return sbanBitLabel(bits);
    return switch (bits) {
        1 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v17_1bit_no_bridge",
            .fixed_capacity => "sban_v17_1bit_fixed_capacity",
            .single_region => "sban_v17_1bit_single_region",
            .no_reputation => "sban_v17_1bit_no_reputation",
        },
        2 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v17_2bit_no_bridge",
            .fixed_capacity => "sban_v17_2bit_fixed_capacity",
            .single_region => "sban_v17_2bit_single_region",
            .no_reputation => "sban_v17_2bit_no_reputation",
        },
        3 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v17_3bit_no_bridge",
            .fixed_capacity => "sban_v17_3bit_fixed_capacity",
            .single_region => "sban_v17_3bit_single_region",
            .no_reputation => "sban_v17_3bit_no_reputation",
        },
        4 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v17_4bit_no_bridge",
            .fixed_capacity => "sban_v17_4bit_fixed_capacity",
            .single_region => "sban_v17_4bit_single_region",
            .no_reputation => "sban_v17_4bit_no_reputation",
        },
        5 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v17_5bit_no_bridge",
            .fixed_capacity => "sban_v17_5bit_fixed_capacity",
            .single_region => "sban_v17_5bit_single_region",
            .no_reputation => "sban_v17_5bit_no_reputation",
        },
        6 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v17_6bit_no_bridge",
            .fixed_capacity => "sban_v17_6bit_fixed_capacity",
            .single_region => "sban_v17_6bit_single_region",
            .no_reputation => "sban_v17_6bit_no_reputation",
        },
        7 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v17_7bit_no_bridge",
            .fixed_capacity => "sban_v17_7bit_fixed_capacity",
            .single_region => "sban_v17_7bit_single_region",
            .no_reputation => "sban_v17_7bit_no_reputation",
        },
        8 => switch (variant) {
            .default => unreachable,
            .no_bridge => "sban_v17_8bit_no_bridge",
            .fixed_capacity => "sban_v17_8bit_fixed_capacity",
            .single_region => "sban_v17_8bit_single_region",
            .no_reputation => "sban_v17_8bit_no_reputation",
        },
        else => "sban_v17_custom_variant",
    };
}

pub const NetworkConfig = struct {
    vocab_size: u16 = 256,
    weight_bits: u8 = 4,
    history_lags: u8 = 8,
    max_lag_parents: u8 = 5,
    propagation_depth: u8 = 2,
    max_hidden_per_hop: u16 = 32,
    max_carry_memories: u16 = 48,
    max_parents_per_new_memory: u16 = 8,
    min_parents_for_birth: u16 = 3,
    birth_margin: i32 = 22,
    birth_pressure_soft_threshold: u16 = 512,
    birth_pressure_parent_boost: u16 = 1,
    birth_pressure_threshold_bonus: i32 = 96,
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
    carry_precision_gate_ppm: u16 = 560,
    carry_low_precision_penalty: i16 = 96,
    carry_support_bonus: i16 = 4,
    carry_signature_diversity: bool = true,
    carry_persistence_bonus: i16 = 24,
    carry_quality_bonus: i16 = 10,
    birth_saturation_soft_ppm: u32 = 850_000,
    birth_saturation_threshold_bonus: i32 = 96,
    birth_saturation_parent_boost: u16 = 1,
    long_term_bonus_ppm: u16 = 1040,
    long_term_bonus_precision_ppm: u16 = 620,
    long_term_low_precision_scale_ppm: u16 = 780,
    long_term_quality_penalty: i16 = 96,
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
    bridge_error_gate_ppm: u16 = 560,
    bridge_error_gap_ppm: u16 = 90,
    bridge_fallback_diversity: u8 = 3,
    bridge_retire_error_slack_ppm: u16 = 40,
    collapse_confident_ppm: u32 = 900_000,
    collapse_surprise_ppm: u32 = 120_000,
    collapse_shrink_step: u16 = 384,
    region_merge_live_threshold: u16 = 192,
    region_merge_idle: u32 = 4096,
    enable_region_compaction: bool = true,
    enable_long_term: bool = true,
    use_reputation: bool = true,
    use_homeostasis: bool = true,
    enable_elasticity: bool = true,
    enable_bridge_memories: bool = true,
    enable_hybrid_experts: bool = true,
    markov1_bonus_ppm: u16 = 340,
    markov2_bonus_ppm: u16 = 760,
    markov3_bonus_ppm: u16 = 900,
    recent_markov2_bonus_ppm: u16 = 960,
    burst_bonus_ppm: u16 = 520,
    recent_expert_window: u32 = 32768,
    hybrid_weight_min: i16 = 160,
    hybrid_weight_max: i16 = 2048,
    hybrid_reward: i16 = 18,
    hybrid_penalty: i16 = 6,
    hybrid_decay: i16 = 1,
    hybrid_share_ppm: u16 = 32,
    hybrid_recent_drift_bonus: i16 = 14,
    hybrid_support_prior: u16 = 3,
    hybrid_evidence_prior: u16 = 4,
    burst_max_age: u32 = 32768,
    burst_min_streak: u8 = 2,
    reset_local_experts_on_boundary: bool = true,
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

pub fn v17ReleaseConfig(bits: u8) NetworkConfig {
    var config = configForVariant(bits, .default);
    config.enable_long_term = true;
    config.birth_margin = 20;
    config.min_parents_for_birth = 4;
    config.max_carry_memories = 64;
    config.max_hidden_per_hop = 48;
    config.propagation_depth = 3;
    config.long_term_bonus_ppm = 1120;
    config.long_term_bonus_precision_ppm = 580;
    config.birth_pressure_threshold_bonus = 0;
    config.birth_saturation_threshold_bonus = 0;
    config.birth_saturation_parent_boost = 0;
    config.hybrid_share_ppm = 0;
    config.hybrid_recent_drift_bonus = 0;
    config.recent_markov2_bonus_ppm = 0;
    config.burst_bonus_ppm = 520;
    config.markov1_bonus_ppm = 340;
    config.markov2_bonus_ppm = 760;
    config.markov3_bonus_ppm = 1900;
    config.hybrid_support_prior = 1;
    config.hybrid_evidence_prior = 0;
    return config;
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes") or std.ascii.eqlIgnoreCase(value, "on")) return true;
    if (std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "no") or std.ascii.eqlIgnoreCase(value, "off")) return false;
    return error.InvalidBooleanOverride;
}

pub fn applyOverride(config: *NetworkConfig, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "weight_bits")) {
        config.weight_bits = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "history_lags")) {
        config.history_lags = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "max_lag_parents")) {
        config.max_lag_parents = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "propagation_depth")) {
        config.propagation_depth = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "max_hidden_per_hop")) {
        config.max_hidden_per_hop = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "max_carry_memories")) {
        config.max_carry_memories = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "max_parents_per_new_memory")) {
        config.max_parents_per_new_memory = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "min_parents_for_birth")) {
        config.min_parents_for_birth = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "birth_margin")) {
        config.birth_margin = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "birth_pressure_soft_threshold")) {
        config.birth_pressure_soft_threshold = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "birth_pressure_parent_boost")) {
        config.birth_pressure_parent_boost = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "birth_pressure_threshold_bonus")) {
        config.birth_pressure_threshold_bonus = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "birth_cooldown")) {
        config.birth_cooldown = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "prune_interval")) {
        config.prune_interval = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "synapse_init_permanence")) {
        config.synapse_init_permanence = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "synapse_max_permanence")) {
        config.synapse_max_permanence = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "synapse_bad_reputation")) {
        config.synapse_bad_reputation = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "short_idle_prune")) {
        config.short_idle_prune = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "long_idle_prune")) {
        config.long_idle_prune = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "promotion_support")) {
        config.promotion_support = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "promotion_reputation")) {
        config.promotion_reputation = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "promotion_precision_ppm")) {
        config.promotion_precision_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "demotion_reputation")) {
        config.demotion_reputation = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "demotion_precision_ppm")) {
        config.demotion_precision_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "neuron_min_utility")) {
        config.neuron_min_utility = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "short_min_reputation")) {
        config.short_min_reputation = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "long_min_reputation")) {
        config.long_min_reputation = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "max_short_memories")) {
        config.max_short_memories = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "max_long_memories")) {
        config.max_long_memories = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "min_short_survivors")) {
        config.min_short_survivors = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "min_long_survivors")) {
        config.min_long_survivors = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "max_outgoing_per_node")) {
        config.max_outgoing_per_node = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "min_outgoing_to_keep")) {
        config.min_outgoing_to_keep = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "carry_precision_gate_ppm")) {
        config.carry_precision_gate_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "carry_low_precision_penalty")) {
        config.carry_low_precision_penalty = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "carry_support_bonus")) {
        config.carry_support_bonus = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "long_term_bonus_ppm")) {
        config.long_term_bonus_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "long_term_bonus_precision_ppm")) {
        config.long_term_bonus_precision_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "long_term_low_precision_scale_ppm")) {
        config.long_term_low_precision_scale_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "long_term_quality_penalty")) {
        config.long_term_quality_penalty = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "long_term_threshold_discount_ppm")) {
        config.long_term_threshold_discount_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "max_regions")) {
        config.max_regions = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "initial_regions")) {
        config.initial_regions = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "initial_short_target")) {
        config.initial_short_target = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "min_short_target")) {
        config.min_short_target = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "region_split_load")) {
        config.region_split_load = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "region_min_survivors")) {
        config.region_min_survivors = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "elasticity_interval")) {
        config.elasticity_interval = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "growth_surprise_ppm")) {
        config.growth_surprise_ppm = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "shrink_surprise_ppm")) {
        config.shrink_surprise_ppm = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "growth_utilization_ppm")) {
        config.growth_utilization_ppm = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "growth_birth_threshold")) {
        config.growth_birth_threshold = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "shrink_birth_threshold")) {
        config.shrink_birth_threshold = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "growth_step")) {
        config.growth_step = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "shrink_step")) {
        config.shrink_step = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "bridge_threshold_bonus")) {
        config.bridge_threshold_bonus = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "bridge_activation_bonus")) {
        config.bridge_activation_bonus = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "bridge_bonus_ppm")) {
        config.bridge_bonus_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "bridge_birth_min_diversity")) {
        config.bridge_birth_min_diversity = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "bridge_error_gate_ppm")) {
        config.bridge_error_gate_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "bridge_error_gap_ppm")) {
        config.bridge_error_gap_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "bridge_fallback_diversity")) {
        config.bridge_fallback_diversity = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "bridge_retire_error_slack_ppm")) {
        config.bridge_retire_error_slack_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "collapse_confident_ppm")) {
        config.collapse_confident_ppm = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "collapse_surprise_ppm")) {
        config.collapse_surprise_ppm = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "collapse_shrink_step")) {
        config.collapse_shrink_step = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "region_merge_live_threshold")) {
        config.region_merge_live_threshold = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "region_merge_idle")) {
        config.region_merge_idle = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "carry_signature_diversity")) {
        config.carry_signature_diversity = try parseBool(value);
    } else if (std.mem.eql(u8, key, "carry_persistence_bonus")) {
        config.carry_persistence_bonus = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "carry_quality_bonus")) {
        config.carry_quality_bonus = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "birth_saturation_soft_ppm")) {
        config.birth_saturation_soft_ppm = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "birth_saturation_threshold_bonus")) {
        config.birth_saturation_threshold_bonus = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "birth_saturation_parent_boost")) {
        config.birth_saturation_parent_boost = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "markov1_bonus_ppm")) {
        config.markov1_bonus_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "markov2_bonus_ppm")) {
        config.markov2_bonus_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "markov3_bonus_ppm")) {
        config.markov3_bonus_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "recent_markov2_bonus_ppm")) {
        config.recent_markov2_bonus_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "burst_bonus_ppm")) {
        config.burst_bonus_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "recent_expert_window")) {
        config.recent_expert_window = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_weight_min")) {
        config.hybrid_weight_min = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_weight_max")) {
        config.hybrid_weight_max = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_reward")) {
        config.hybrid_reward = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_penalty")) {
        config.hybrid_penalty = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_decay")) {
        config.hybrid_decay = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_share_ppm")) {
        config.hybrid_share_ppm = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_recent_drift_bonus")) {
        config.hybrid_recent_drift_bonus = try std.fmt.parseInt(i16, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_support_prior")) {
        config.hybrid_support_prior = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "hybrid_evidence_prior")) {
        config.hybrid_evidence_prior = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, key, "burst_max_age")) {
        config.burst_max_age = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "burst_min_streak")) {
        config.burst_min_streak = try std.fmt.parseInt(u8, value, 10);
    } else if (std.mem.eql(u8, key, "enable_region_compaction")) {
        config.enable_region_compaction = try parseBool(value);
    } else if (std.mem.eql(u8, key, "enable_long_term")) {
        config.enable_long_term = try parseBool(value);
    } else if (std.mem.eql(u8, key, "use_reputation")) {
        config.use_reputation = try parseBool(value);
    } else if (std.mem.eql(u8, key, "use_homeostasis")) {
        config.use_homeostasis = try parseBool(value);
    } else if (std.mem.eql(u8, key, "enable_elasticity")) {
        config.enable_elasticity = try parseBool(value);
    } else if (std.mem.eql(u8, key, "enable_bridge_memories")) {
        config.enable_bridge_memories = try parseBool(value);
    } else if (std.mem.eql(u8, key, "enable_hybrid_experts")) {
        config.enable_hybrid_experts = try parseBool(value);
    } else if (std.mem.eql(u8, key, "reset_local_experts_on_boundary")) {
        config.reset_local_experts_on_boundary = try parseBool(value);
    } else {
        return error.UnknownConfigOverride;
    }
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
        try std.testing.expect(std.mem.startsWith(u8, sbanBitLabel(bits), "sban_v17_"));
        var cfg_local = configForVariant(bits, .default);
        try applyOverride(&cfg_local, "history_lags", "9");
        try std.testing.expectEqual(@as(u8, 9), cfg_local.history_lags);
    }
}
