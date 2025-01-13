#!/bin/bash

# Debug mode (set to 1 to enable debug output)
DEBUG=1

# Constants
NSS_UDP_ST_CMD="nss-udp-st"
STATS_DIR="/tmp/nss-udp-st"

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

# Check if test is running
is_test_running() {
    execute_cmd "$NSS_UDP_ST_CMD --mode stats --type tx" >/dev/null 2>&1
    return $?
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
    echo "    \"status\": \"$status\""
    if [ "$status" = "running" ]; then
        echo "    ,\"throughput\": $throughput,"
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

# Get throughput from stats file
get_throughput() {
    local direction=$1
    local type=$([ "$direction" = "upstream" ] && echo "tx" || echo "rx")
    local stats_file="${STATS_DIR}/${type}_stats"

    # Update stats file
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
                # Convert Mbps to bps
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
    debug_log "Getting final stats..."
    execute_cmd "$NSS_UDP_ST_CMD --mode stats --type tx"

    debug_log "Stopping test..."
    execute_cmd "$NSS_UDP_ST_CMD --mode stop"

    debug_log "Cleaning up..."
    execute_cmd "$NSS_UDP_ST_CMD --mode final"
    execute_cmd "$NSS_UDP_ST_CMD --mode clear"

    # Verify cleanup
    if is_test_running; then
        debug_log "Cleanup failed, forcing module unload..."
        rmmod nss_udp_st 2>/dev/null
    fi
}

# Handle start command
handle_start() {
    if is_test_running; then
        output_error "Test already running"
        return 1
    fi

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

    # Initialize module (force cleanup if needed)
    if is_test_running; then
        cleanup
    fi

    # Initialize module
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode init --rate 1000 --buffer_sz 1500 --dscp 0 --net_dev eth4"; then
        output_error "Failed to initialize module"
        return 1
    fi

    # Configure test
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode create --sip $src_ip --dip $dst_ip --sport $src_port --dport $dst_port --version 4"; then
        output_error "Failed to configure test"
        cleanup
        return 1
    fi

    # Start test
    if ! execute_cmd "$NSS_UDP_ST_CMD --mode start --type $([ "$direction" = "upstream" ] && echo "tx" || echo "rx")"; then
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
    local direction=$1

    if ! is_test_running; then
        output_status "idle" 0
        return 0
    fi

    local throughput
    throughput=$(get_throughput "$direction")
    if [ $? -eq 0 ]; then
        output_status "running" "$throughput"
        return 0
    else
        output_error "Failed to get test results"
        return 1
    fi
}

# Handle stop command
handle_stop() {
    local direction=$1
    local src_ip=$2
    local dst_ip=$3
    local src_port=$4
    local dst_port=$5
    local protocol=$6

    if ! is_test_running; then
        output_error "No test running"
        return 1
    fi

    # Get final throughput
    local throughput
    throughput=$(get_throughput "$direction")
    local ret=$?

    # Always attempt cleanup
    cleanup

    if [ $ret -eq 0 ] && [ -n "$throughput" ]; then
        output_results "$direction" "$src_ip" "$dst_ip" "$src_port" "$dst_port" "$protocol" "$throughput"
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
        src_ip=""
        dst_ip=""
        src_port=""
        dst_port=""
        protocol=""
        direction=""

        # Parse parameters
        while [ $# -gt 0 ]; do
            case "$1" in
                --src-ip) src_ip=$2 ;;
                --dst-ip) dst_ip=$2 ;;
                --src-port) src_port=$2 ;;
                --dst-port) dst_port=$2 ;;
                --protocol) protocol=$2 ;;
                --direction) direction=$2 ;;
            esac
            shift 2
        done

        handle_start "$src_ip" "$dst_ip" "$src_port" "$dst_port" "$protocol" "$direction"
        ;;

    "status")
        handle_status "$1"
        ;;

    "stop")
        handle_stop "$1" "$2" "$3" "$4" "$5" "$6"
        ;;

    *)
        output_error "Unknown command. Use 'start', 'status', or 'stop'"
        exit 1
        ;;
esac

exit 0