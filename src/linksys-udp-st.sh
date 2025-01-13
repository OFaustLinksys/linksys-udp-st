#!/bin/bash

# Debug mode (set to 1 to enable debug output)
DEBUG=1

# Constants
NSS_UDP_ST_CMD="nss-udp-st"
STATS_DIR="/tmp/nss-udp-st"
MODULE_NAME="nss_udp_st"

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

# Check if module is loaded
is_module_loaded() {
    lsmod | grep -q "^${MODULE_NAME}"
    return $?
}

# Ensure module is loaded
ensure_module_loaded() {
    if ! is_module_loaded; then
        debug_log "Loading $MODULE_NAME module..."
        modprobe $MODULE_NAME
        if [ $? -ne 0 ]; then
            debug_log "Failed to load module $MODULE_NAME"
            return 1
        fi
    fi
    debug_log "Module $MODULE_NAME is loaded"
    return 0
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
    local direction=$3

    echo "{"
    echo "    \"status\": \"$status\","
    if [ "$status" = "running" ]; then
        echo "    \"direction\": \"$direction\","
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
    echo "        \"src_ip\": \"$src_ip\","
    echo "        \"dst_ip\": \"$dst_ip\","
    echo "        \"src_port\": $src_port,"
    echo "        \"dst_port\": $dst_port,"
    echo "        \"protocol\": \"$protocol\","
    echo "        \"direction\": \"$direction\""
    echo "    },"
    echo "    \"results\": {"
    echo "        \"throughput\": $throughput,"
    echo "        \"unit\": \"bps\""
    echo "    }"
    echo "}"
}

# Get current test type (tx/rx) from running process
get_current_test_type() {
    local ps_output
    ps_output=$(ps aux | grep "[n]ss-udp-st.*--mode start" | grep -o "type [^ ]*" | awk '{print $2}')
    if [ -n "$ps_output" ]; then
        echo "$ps_output"
        return 0
    fi
    return 1
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
    local in_throughput_section=0
    local throughput=""

    while IFS= read -r line; do
        debug_log "> $line"

        if [[ "$line" == *"Throughput Stats"* ]]; then
            in_throughput_section=1
            continue
        fi

        if [ $in_throughput_section -eq 1 ] && [[ "$line" == *"throughput  ="* ]]; then
            throughput=$(echo "$line" | grep -o '[0-9]\+')
            if [ -n "$throughput" ]; then
                debug_log "Found throughput: $throughput Mbps (converted to $((throughput * 1000000)) bps)"
                echo $((throughput * 1000000))
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

    # If module is loaded after cleanup, unload it
    if is_module_loaded; then
        debug_log "Module still loaded, unloading..."
        rmmod $MODULE_NAME 2>/dev/null
        if [ $? -ne 0 ]; then
            debug_log "Warning: Failed to unload module"
        fi
    fi
}

# Handle start command
handle_start() {
    local src_ip=$1
    local dst_ip=$2
    local src_port=$3
    local dst_port=$4
    local protocol=$5
    local direction=$6

    # Validate IP addresses
    if ! echo "$src_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        output_error "Invalid source IP address"
        return 1
    fi
    if ! echo "$dst_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        output_error "Invalid destination IP address"
        return 1
    fi

    # Validate ports
    if ! [[ "$src_port" =~ ^[0-9]+$ ]] || [ "$src_port" -lt 1 ] || [ "$src_port" -gt 65535 ]; then
        output_error "Invalid source port"
        return 1
    fi
    if ! [[ "$dst_port" =~ ^[0-9]+$ ]] || [ "$dst_port" -lt 1 ] || [ "$dst_port" -gt 65535 ]; then
        output_error "Invalid destination port"
        return 1
    fi

    # Validate protocol
    if [ "$protocol" != "tcp" ] && [ "$protocol" != "udp" ]; then
        output_error "Invalid protocol (must be 'tcp' or 'udp')"
        return 1
    fi

    # Validate direction
    if [ "$direction" != "upstream" ] && [ "$direction" != "downstream" ]; then
        output_error "Invalid direction (must be 'upstream' or 'downstream')"
        return 1
    fi

    # Always do cleanup first in case of leftover state
    if is_module_loaded; then
        debug_log "Cleaning up previous test state..."
        cleanup
    fi

    # Ensure module is loaded fresh
    if ! ensure_module_loaded; then
        output_error "Failed to load kernel module"
        return 1
    fi

    # Initialize module
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode init --rate 1000 --buffer_sz 1500 --dscp 0 --net_dev eth4"; then
        output_error "Failed to initialize module"
        cleanup
        return 1
    fi

    # Configure test
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode create --sip $src_ip --dip $dst_ip --sport $src_port --dport $dst_port --version 4"; then
        output_error "Failed to configure test"
        cleanup
        return 1
    fi

    # Start test with correct type based on direction
    local type=$([ "$direction" = "upstream" ] && echo "tx" || echo "rx")
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode start --type $type"; then
        output_error "Failed to start test"
        cleanup
        return 1
    fi

    # Output initial status
    output_status "running" 0 "$direction"
    return 0
}

# Parse command line parameters
parse_params() {
    local -n params=$1
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --src-ip) params[src_ip]=$2 ;;
            --dst-ip) params[dst_ip]=$2 ;;
            --src-port) params[src_port]=$2 ;;
            --dst-port) params[dst_port]=$2 ;;
            --protocol) params[protocol]=$2 ;;
            --direction) params[direction]=$2 ;;
        esac
        shift 2
    done
}

# Handle status command
handle_status() {
    # If module not loaded, test is not running
    if ! is_module_loaded; then
        output_status "idle" 0 ""
        return 0
    fi

    # Get current test type from running process
    local type
    type=$(get_current_test_type)
    if [ $? -ne 0 ]; then
        debug_log "Could not determine test type"
        output_error "Could not determine test type"
        return 1
    fi
    debug_log "Current test type: $type"

    # Determine direction from type
    local direction
    direction=$([ "$type" = "tx" ] && echo "upstream" || echo "downstream")

    # Get current throughput
    local throughput
    throughput=$(get_throughput "$type")
    if [ $? -eq 0 ]; then
        output_status "running" "$throughput" "$direction"
        return 0
    else
        output_error "Failed to get test results"
        return 1
    fi
}

# Handle stop command
handle_stop() {
    # If module not loaded, no test is running
    if ! is_module_loaded; then
        output_error "No test running"
        return 1
    fi

    # Get current test type and direction
    local type
    type=$(get_current_test_type)
    if [ $? -ne 0 ]; then
        debug_log "Could not determine test type"
        output_error "Could not determine test type"
        return 1
    fi

    local direction
    direction=$([ "$type" = "tx" ] && echo "upstream" || echo "downstream")

    # Get final throughput before cleanup
    local throughput
    throughput=$(get_throughput "$type")
    local ret=$?

    # Parse parameters into array
    declare -A params
    parse_params params "$@"

    # Always attempt cleanup
    cleanup

    # Output results if we got valid throughput
    if [ $ret -eq 0 ] && [ -n "$throughput" ]; then
        output_results "$direction" "${params[src_ip]}" "${params[dst_ip]}" \
                      "${params[src_port]}" "${params[dst_port]}" "${params[protocol]}" \
                      "$throughput"
        return 0
    else
        output_error "Failed to get final results"
        return 1
    fi
}

# Main script
case "$1" in
    "start")
        shift
        declare -A params
        parse_params params "$@"
        handle_start "${params[src_ip]}" "${params[dst_ip]}" \
                    "${params[src_port]}" "${params[dst_port]}" \
                    "${params[protocol]}" "${params[direction]}"
        ;;

    "status")
        shift
        handle_status "$@"
        ;;

    "stop")
        shift
        handle_stop "$@"
        ;;

    *)
        output_error "Unknown command. Use 'start', 'status', or 'stop'"
        exit 1
        ;;
esac

exit 0