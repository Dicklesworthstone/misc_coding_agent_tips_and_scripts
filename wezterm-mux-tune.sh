#!/usr/bin/env bash
#
# wezterm-mux-tune.sh - Auto-tune wezterm for AI agent swarms
#
# Detects system RAM and calculates optimal performance settings using
# linear interpolation. Backs up existing config before modification.
#
# Usage:
#   ./wezterm-mux-tune.sh              # Auto-detect RAM, interpolate settings
#   ./wezterm-mux-tune.sh --dry-run    # Show what would be done
#   ./wezterm-mux-tune.sh --restore    # Restore from backup
#   ./wezterm-mux-tune.sh --profile 256  # Force specific profile (64/128/256/512)
#   ./wezterm-mux-tune.sh --ram 200    # Calculate for specific RAM amount
#
# See: WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CONFIG_FILE="${HOME}/.wezterm.lua"
BACKUP_FILE="${HOME}/.wezterm.lua.pre-tune-backup"

# Detect RAM in GB
detect_ram_gb() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}'
    else
        grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}'
    fi
}

# Linear interpolation between two points
# Usage: lerp x x1 y1 x2 y2
lerp() {
    local x=$1 x1=$2 y1=$3 x2=$4 y2=$5
    # y = y1 + (x - x1) * (y2 - y1) / (x2 - x1)
    echo $(( y1 + (x - x1) * (y2 - y1) / (x2 - x1) ))
}

# Interpolate a setting based on RAM
# Uses piecewise linear interpolation across 4 anchor points
# Extrapolates linearly beyond the defined range
interpolate_setting() {
    local ram=$1
    local v64=$2 v128=$3 v256=$4 v512=$5

    if (( ram <= 64 )); then
        # Extrapolate below 64GB (floor at 32GB worth)
        local v32=$(( v64 / 2 ))
        lerp "$ram" 32 "$v32" 64 "$v64"
    elif (( ram <= 128 )); then
        lerp "$ram" 64 "$v64" 128 "$v128"
    elif (( ram <= 256 )); then
        lerp "$ram" 128 "$v128" 256 "$v256"
    elif (( ram <= 512 )); then
        lerp "$ram" 256 "$v256" 512 "$v512"
    else
        # Extrapolate above 512GB
        lerp "$ram" 256 "$v256" 512 "$v512"
    fi
}

# Round to nice numbers for readability
round_nice() {
    local val=$1
    if (( val >= 1000000 )); then
        # Round to nearest 100,000
        echo $(( (val + 50000) / 100000 * 100000 ))
    elif (( val >= 10000 )); then
        # Round to nearest 1,000
        echo $(( (val + 500) / 1000 * 1000 ))
    elif (( val >= 1000 )); then
        # Round to nearest 256 (power of 2 friendly)
        echo $(( (val + 128) / 256 * 256 ))
    else
        echo "$val"
    fi
}

# Calculate all settings for a given RAM amount
calculate_settings() {
    local ram=$1

    # Anchor points: 64GB, 128GB, 256GB, 512GB
    # scrollback_lines
    SCROLLBACK=$(interpolate_setting "$ram" 1000000 2000000 5000000 10000000)
    SCROLLBACK=$(round_nice "$SCROLLBACK")

    # mux_output_parser_buffer_size (in MB, will convert to expression)
    local buf_mb=$(interpolate_setting "$ram" 2 4 8 16)
    BUFFER_SIZE=$buf_mb

    # mux_output_parser_coalesce_delay_ms
    if (( ram < 96 )); then
        COALESCE_DELAY=2
    else
        COALESCE_DELAY=1
    fi

    # ratelimit_mux_line_prefetches_per_second
    PREFETCH_RATE=$(interpolate_setting "$ram" 500 750 500 1000)
    PREFETCH_RATE=$(round_nice "$PREFETCH_RATE")
    # Clamp to reasonable range
    (( PREFETCH_RATE < 500 )) && PREFETCH_RATE=500
    (( PREFETCH_RATE > 2000 )) && PREFETCH_RATE=2000

    # Cache sizes (all use same scaling)
    SHAPE_CACHE=$(interpolate_setting "$ram" 8192 16384 32768 65536)
    SHAPE_CACHE=$(round_nice "$SHAPE_CACHE")
    LINE_STATE_CACHE=$SHAPE_CACHE
    LINE_QUAD_CACHE=$SHAPE_CACHE
    LINE_ELE_CACHE=$SHAPE_CACHE

    # glyph_cache_image_cache_size (different scale)
    GLYPH_CACHE=$(interpolate_setting "$ram" 512 1024 2048 4096)
    GLYPH_CACHE=$(round_nice "$GLYPH_CACHE")
}

# Generate config block
generate_config() {
    local ram=$1
    calculate_settings "$ram"

    local profile_label
    if (( ram >= 384 )); then
        profile_label="HIGH-RAM"
    elif (( ram >= 192 )); then
        profile_label="HIGH-RAM"
    else
        profile_label=""
    fi

    cat << EOF
-- ============================================================
-- ${profile_label}${profile_label:+ }PERFORMANCE TUNING (${ram}GB system) - Auto-generated
-- Settings interpolated for actual RAM by wezterm-mux-tune.sh
-- See: WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md
-- ============================================================
config.scrollback_lines = ${SCROLLBACK}
config.mux_output_parser_buffer_size = ${BUFFER_SIZE} * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = ${COALESCE_DELAY}
config.ratelimit_mux_line_prefetches_per_second = ${PREFETCH_RATE}
config.shape_cache_size = ${SHAPE_CACHE}
config.line_state_cache_size = ${LINE_STATE_CACHE}
config.line_quad_cache_size = ${LINE_QUAD_CACHE}
config.line_to_ele_shape_cache_size = ${LINE_ELE_CACHE}
config.glyph_cache_image_cache_size = ${GLYPH_CACHE}
EOF
}

# Generate fixed profile (for --profile flag compatibility)
generate_fixed_profile() {
    local profile=$1

    case $profile in
        64)
            cat << 'EOF'
-- ============================================================
-- PERFORMANCE TUNING (64GB system) - Auto-generated by wezterm-mux-tune.sh
-- See: WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md
-- ============================================================
config.scrollback_lines = 1000000
config.mux_output_parser_buffer_size = 2 * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = 2
config.ratelimit_mux_line_prefetches_per_second = 500
config.shape_cache_size = 8192
config.line_state_cache_size = 8192
config.line_quad_cache_size = 8192
config.line_to_ele_shape_cache_size = 8192
config.glyph_cache_image_cache_size = 512
EOF
            ;;
        128)
            cat << 'EOF'
-- ============================================================
-- PERFORMANCE TUNING (128GB system) - Auto-generated by wezterm-mux-tune.sh
-- See: WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md
-- ============================================================
config.scrollback_lines = 2000000
config.mux_output_parser_buffer_size = 4 * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = 1
config.ratelimit_mux_line_prefetches_per_second = 750
config.shape_cache_size = 16384
config.line_state_cache_size = 16384
config.line_quad_cache_size = 16384
config.line_to_ele_shape_cache_size = 16384
config.glyph_cache_image_cache_size = 1024
EOF
            ;;
        256)
            cat << 'EOF'
-- ============================================================
-- HIGH-RAM PERFORMANCE TUNING (256GB system) - Auto-generated by wezterm-mux-tune.sh
-- See: WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md
-- ============================================================
config.scrollback_lines = 5000000
config.mux_output_parser_buffer_size = 8 * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = 1
config.ratelimit_mux_line_prefetches_per_second = 500
config.shape_cache_size = 32768
config.line_state_cache_size = 32768
config.line_quad_cache_size = 32768
config.line_to_ele_shape_cache_size = 32768
config.glyph_cache_image_cache_size = 2048
EOF
            ;;
        512)
            cat << 'EOF'
-- ============================================================
-- HIGH-RAM PERFORMANCE TUNING (512GB system) - Auto-generated by wezterm-mux-tune.sh
-- See: WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md
-- ============================================================
config.scrollback_lines = 10000000
config.mux_output_parser_buffer_size = 16 * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = 1
config.ratelimit_mux_line_prefetches_per_second = 1000
config.shape_cache_size = 65536
config.line_state_cache_size = 65536
config.line_quad_cache_size = 65536
config.line_to_ele_shape_cache_size = 65536
config.glyph_cache_image_cache_size = 4096
EOF
            ;;
        *)
            echo "Unknown profile: $profile" >&2
            return 1
            ;;
    esac
}

# Check if config already has tuning
has_tuning() {
    grep -q "wezterm-mux-tune.sh\|PERFORMANCE TUNING.*system" "$CONFIG_FILE" 2>/dev/null
}

# Remove existing tuning block
remove_tuning() {
    local tmp_file
    tmp_file=$(mktemp)
    grep -v -E '^-- =+$|^-- (HIGH-RAM )?PERFORMANCE TUNING|^-- Settings interpolated|^-- See: WEZTERM_MUX_PERFORMANCE|^config\.scrollback_lines|^config\.mux_output_parser|^config\.ratelimit_mux_line_prefetches|^config\.shape_cache_size|^config\.line_state_cache_size|^config\.line_quad_cache_size|^config\.line_to_ele_shape_cache_size|^config\.glyph_cache_image_cache_size|^-- Scrollback and history$' "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
}

# Find insertion point (before "return config")
find_insertion_line() {
    grep -n "^return config" "$CONFIG_FILE" | head -1 | cut -d: -f1
}

# Insert config at line
insert_config() {
    local line_num=$1
    local config_block=$2
    local tmp_file=$(mktemp)

    head -n $((line_num - 1)) "$CONFIG_FILE" > "$tmp_file"
    echo "" >> "$tmp_file"
    echo "$config_block" >> "$tmp_file"
    echo "" >> "$tmp_file"
    tail -n +$line_num "$CONFIG_FILE" >> "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
}

# Show help
show_help() {
    cat << 'EOF'
wezterm-mux-tune.sh - Auto-tune wezterm for AI agent swarms

USAGE:
    wezterm-mux-tune.sh [OPTIONS]

OPTIONS:
    --dry-run       Preview changes without applying
    --restore       Restore config from backup
    --profile NUM   Use fixed profile (64, 128, 256, or 512)
    --ram NUM       Calculate settings for specific RAM (GB)
    --help          Show this help

EXAMPLES:
    ./wezterm-mux-tune.sh              # Auto-detect RAM, interpolate
    ./wezterm-mux-tune.sh --dry-run    # Preview interpolated settings
    ./wezterm-mux-tune.sh --ram 200    # Calculate for 200GB system
    ./wezterm-mux-tune.sh --profile 256  # Use exact 256GB profile
    ./wezterm-mux-tune.sh --restore    # Restore original config

The script uses linear interpolation to calculate optimal settings
based on your actual RAM, rather than snapping to fixed tiers.
EOF
}

# Main
main() {
    local dry_run=false
    local restore=false
    local force_profile=""
    local force_ram=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --restore)
                restore=true
                shift
                ;;
            --profile)
                if [[ -z "${2:-}" ]]; then
                    echo -e "${RED}--profile requires an argument (64/128/256/512)${NC}"
                    exit 1
                fi
                force_profile=$2
                shift 2
                ;;
            --ram)
                if [[ -z "${2:-}" ]]; then
                    echo -e "${RED}--ram requires an argument (RAM in GB)${NC}"
                    exit 1
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Invalid RAM value: $2 (must be a positive integer)${NC}"
                    exit 1
                fi
                force_ram=$2
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Handle restore
    if $restore; then
        if [[ -f "$BACKUP_FILE" ]]; then
            cp "$BACKUP_FILE" "$CONFIG_FILE"
            echo -e "${GREEN}Restored config from backup${NC}"
            echo "Restart wezterm-mux-server to apply changes"
        else
            echo -e "${RED}No backup file found at $BACKUP_FILE${NC}"
            exit 1
        fi
        return
    fi

    # Check config exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}Config file not found: $CONFIG_FILE${NC}"
        echo "Create a basic wezterm config first"
        exit 1
    fi

    # Determine RAM and config generation method
    local ram_gb config_block

    if [[ -n "$force_profile" ]]; then
        # Validate and use fixed profile
        case $force_profile in
            64|128|256|512) ;;
            *)
                echo -e "${RED}Invalid profile: $force_profile (must be 64, 128, 256, or 512)${NC}"
                exit 1
                ;;
        esac
        echo -e "${BLUE}Using fixed profile: ${force_profile}GB${NC}"
        config_block=$(generate_fixed_profile "$force_profile")
    else
        # Use interpolation
        if [[ -n "$force_ram" ]]; then
            ram_gb=$force_ram
            echo -e "${BLUE}Using specified RAM: ${ram_gb}GB${NC}"
        else
            ram_gb=$(detect_ram_gb)
            echo -e "${BLUE}Detected RAM: ${ram_gb}GB${NC}"
        fi

        echo -e "${CYAN}Calculating interpolated settings...${NC}"
        config_block=$(generate_config "$ram_gb")
    fi

    # Dry run - just show what would happen
    if $dry_run; then
        echo -e "\n${YELLOW}Would apply the following configuration:${NC}\n"
        echo "$config_block"
        echo -e "\n${YELLOW}To apply, run without --dry-run${NC}"
        return
    fi

    # Create backup
    if [[ ! -f "$BACKUP_FILE" ]]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo -e "${GREEN}Created backup: $BACKUP_FILE${NC}"
    fi

    # Remove existing tuning if present
    if has_tuning; then
        echo -e "${YELLOW}Removing existing tuning configuration...${NC}"
        remove_tuning
    fi

    # Find insertion point
    local insert_line
    insert_line=$(find_insertion_line)
    if [[ -z "$insert_line" ]]; then
        echo -e "${RED}Could not find 'return config' in $CONFIG_FILE${NC}"
        exit 1
    fi

    # Insert new config
    echo -e "${GREEN}Inserting performance tuning at line $insert_line...${NC}"
    insert_config "$insert_line" "$config_block"

    echo -e "\n${GREEN}Configuration updated successfully!${NC}"
    echo ""
    echo "Settings applied:"
    echo "$config_block" | grep -E '^config\.' | sed 's/^/  /'
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Restart wezterm-mux-server:"
    echo "     pkill -9 -f wezterm-mux; wezterm-mux-server --daemonize"
    echo ""
    echo "  2. Reconnect your wezterm client"
    echo ""
    echo "  To restore original config:"
    echo "     $0 --restore"
}

main "$@"
