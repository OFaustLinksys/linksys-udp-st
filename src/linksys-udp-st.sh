#!/bin/sh

# Debug mode (set to 1 to enable debug output)
DEBUG=0

# Constants
NSS_UDP_ST_CMD="nss-udp-st"
STATS_DIR="/tmp/nss-udp-st"
MODULE_NAME="nss_udp_st"
CONFIG_FILE="/tmp/linksys-udp-st.conf"
DEFAULT_NET_DEV="eth4"

# Debug logging
debug_log() {
    if [ $DEBUG -eq 1 ]; then
        echo "DEBUG: $1" >&2
    fi
}

# Execute command and log output
execute_cmd() {
    local cmd="$1"
    debug_log "Executing command: $cmd"
    output=$(eval "$cmd" 2>&1)
    ret=$?
    debug_log "Command exit code: $ret"
    if [ -n "$output" ]; then
        debug_log "Command output: $output"
    fi
    return $ret
}

# Parse command line parameters
parse_params() {
    SRC_IP=""
    DST_IP=""
    SRC_PORT=""
    DST_PORT=""
    PROTOCOL=""
    DIRECTION=""
    NET_DEV="$DEFAULT_NET_DEV"

    while [ $# -gt 1 ]; do
        case "$2" in
            --src-ip) SRC_IP=$3 ;;
            --dst-ip) DST_IP=$3 ;;
            --src-port) SRC_PORT=$3 ;;
            --dst-port) DST_PORT=$3 ;;
            --protocol) PROTOCOL=$3 ;;
            --direction) DIRECTION=$3 ;;
            --net-dev) NET_DEV=$3 ;;
        esac
        shift 2
    done
}

# Check if module is loaded
is_module_loaded() {
    lsmod | grep -q "^${MODULE_NAME}"
    return $?
}

# Save test configuration
save_config() {
    debug_log "Saving test configuration..."
    cat > "$CONFIG_FILE" << EOF
SRC_IP=$1
DST_IP=$2
SRC_PORT=$3
DST_PORT=$4
PROTOCOL=$5
DIRECTION=$6
NET_DEV=$7
EOF
}

# Load test configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        debug_log "Loading test configuration..."
        . "$CONFIG_FILE"
        return 0
    fi
    debug_log "Configuration file not found: $CONFIG_FILE"
    return 1
}

# Output JSON formatted error message
output_error() {
    echo "{"
    echo "    \"error\": \"$1\""
    echo "}"
}

# Output JSON formatted status
output_status() {
    local status=$1
    local throughput=$2

    echo "{"
    echo "    \"status\": \"$status\","
    if [ "$status" = "running" ]; then
        echo "    \"throughput\": $throughput,"
        echo "    \"unit\": \"bps\""
    fi
    echo "}"
}

# Output JSON formatted results
output_results() {
    local direction=$1
    local src_ip=$2
    local dst_ip=$3
    local src_port=$4
    local dst_port=$5
    local protocol=$6
    local throughput=$7

    echo "{"
    echo "    \"test_config\": {"
    echo "        \"src_ip\": \"${src_ip:-}\","
    echo "        \"dst_ip\": \"${dst_ip:-}\","
    echo "        \"src_port\": ${src_port:-0},"
    echo "        \"dst_port\": ${dst_port:-0},"
    echo "        \"protocol\": \"${protocol:-}\","
    echo "        \"direction\": \"${direction:-}\""
    echo "    },"
    echo "    \"results\": {"
    echo "        \"throughput\": $throughput,"
    echo "        \"unit\": \"bps\""
    echo "    }"
    echo "}"
}

# Get current test type from running process
get_current_test_type() {
    ps | grep "[n]ss-udp-st.*--mode start" | grep -o "type [^ ]*" | cut -d' ' -f2
}

# Get throughput from stats file
get_throughput() {
    local type=$1
    local stats_file="${STATS_DIR}/${type}_stats"

    # Try to update stats file
    execute_cmd "$NSS_UDP_ST_CMD --mode stats --type $type"
    if [ ! -f "$stats_file" ]; then
        debug_log "Stats file not found: $stats_file"
        return 1
    fi

    debug_log "Stats file contents:"
    while IFS= read -r line; do
        debug_log "> $line"
        if echo "$line" | grep -q "throughput.*=.*Mbps"; then
            local mbps
            mbps=$(echo "$line" | grep -o '[0-9]\+')
            if [ -n "$mbps" ]; then
                debug_log "Found throughput: $mbps Mbps (converted to $((mbps * 1000000)) bps)"
                echo $((mbps * 1000000))
                return 0
            fi
        fi
    done < "$stats_file"

    debug_log "No throughput found in stats file"
    return 1
}

# Clean up resources
cleanup() {
    debug_log "Cleaning up..."

    # Try to get final stats before cleanup
    debug_log "Getting final stats..."
    execute_cmd "$NSS_UDP_ST_CMD --mode stats --type tx"
    execute_cmd "$NSS_UDP_ST_CMD --mode stats --type rx"

    # Stop any running test
    debug_log "Stopping test..."
    execute_cmd "$NSS_UDP_ST_CMD --mode stop"

    # Finalize and clear
    debug_log "Finalizing..."
    execute_cmd "$NSS_UDP_ST_CMD --mode final"

    debug_log "Clearing..."
    execute_cmd "$NSS_UDP_ST_CMD --mode clear"

    # Remove configuration file
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
}

# Handle start command
handle_start() {
    # Check if module is already loaded
    if is_module_loaded; then
        debug_log "Cleaning up previous test state..."
        cleanup
    fi

    # Save configuration for later use
    save_config "$1" "$2" "$3" "$4" "$5" "$6" "$7"

    # Initialize module with network device
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode init --rate 1000 --buffer_sz 1500 --dscp 0 --net_dev $7"; then
        output_error "Failed to initialize module"
        cleanup
        return 1
    fi

    # Configure test
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode create --sip $1 --dip $2 --sport $3 --dport $4 --version 4"; then
        output_error "Failed to configure test"
        cleanup
        return 1
    fi

    # Start test with correct type based on direction
    local type=$([ "$6" = "upstream" ] && echo "tx" || echo "rx")
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode start --type $type"; then
        output_error "Failed to start test"
        cleanup
        return 1
    fi

    # Output initial status
    output_status "running" 0
    return 0
}

# Handle status command
handle_status() {
    load_config
    # If module not loaded, test is not running
    if ! is_module_loaded; then
        output_status "idle" 0
        return 0
    fi

    # Get current test type from running process
    local type
    if [ "$DIRECTION" = "upstream" ]; then
        type="tx"
    else
        type="rx"
    fi

    # Get current throughput
    local throughput
    throughput=$(get_throughput "$type")
    if [ $? -eq 0 ]; then
        output_status "running" "$throughput"
        return 0
    fi

    output_status "idle" 0
    return 0
}

# Handle stop command
handle_stop() {
    # If module not loaded, no test was running
    if ! is_module_loaded; then
        output_error "No test running"
        return 1
    fi

    # Get current test type and direction
    load_config
    local type
    if [ "$DIRECTION" = "upstream" ]; then
        type="tx"
    else
        type="rx"
    fi

    # Load saved configuration
    if ! load_config; then
        debug_log "Warning: Could not load test configuration"
    fi

    local direction
    direction=$([ "$type" = "tx" ] && echo "upstream" || echo "downstream")

    # Get final throughput before cleanup
    local throughput
    throughput=$(get_throughput "$type")
    local ret=$?

    # Always attempt cleanup
    cleanup

    # Output results if we got valid throughput
    if [ $ret -eq 0 ] && [ -n "$throughput" ]; then
        output_results "$direction" "$SRC_IP" "$DST_IP" \
                      "$SRC_PORT" "$DST_PORT" "$PROTOCOL" \
                      "$throughput"
        return 0
    else
        output_error "Failed to get final results"
        return 1
    fi
}

# Parse command line parameters
parse_params "$@"

# Main script
case "$1" in
    "start")
        handle_start "$SRC_IP" "$DST_IP" "$SRC_PORT" "$DST_PORT" \
                    "$PROTOCOL" "$DIRECTION" "$NET_DEV"
        ;;

    "status")
        handle_status
        ;;

    "stop")
        handle_stop
        ;;

    *)
        output_error "Unknown command. Please use 'start', 'status', or 'stop'."
        exit 1
        ;;
esac

exit 0
