/**
 * Linksys UDP Speed Test Utility
 * A command-line wrapper for the NSS UDP Speed Test kernel module
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <arpa/inet.h>
#include <stdbool.h>
#include "linksys-udp-st.h"
#include "json_helper.h"
#include "module_ops.h"

static speedtest_config_t g_config;
static volatile sig_atomic_t g_running = 1;

/**
 * Signal handler for graceful shutdown
 */
static void signal_handler(int signum) {
    (void)signum;  // Unused parameter
    if (is_test_running()) {
        stop_test();
        unload_kernel_module();
    }
    g_running = 0;
}

/**
 * Validate IPv4 address format
 */
static bool validate_ip_address(const char *ip_str) {
    struct sockaddr_in sa;
    return inet_pton(AF_INET, ip_str, &(sa.sin_addr)) == 1;
}

/**
 * Validate port number range (1-65535)
 */
static bool validate_port(int port) {
    return port > 0 && port < 65536;
}

/**
 * Validate protocol string (tcp/udp)
 */
static bool validate_protocol(const char *protocol) {
    return (strcmp(protocol, "tcp") == 0 || strcmp(protocol, "udp") == 0);
}

/**
 * Validate direction string (upstream/downstream)
 */
static bool validate_direction(const char *direction) {
    return (strcmp(direction, "upstream") == 0 || strcmp(direction, "downstream") == 0);
}

/**
 * Validate all test configuration parameters
 */
static bool validate_config(speedtest_config_t *config) {
    if (!validate_ip_address(config->src_ip)) {
        output_error_json("Invalid source IP address");
        return false;
    }
    if (!validate_ip_address(config->dst_ip)) {
        output_error_json("Invalid destination IP address");
        return false;
    }
    if (!validate_port(config->src_port)) {
        output_error_json("Invalid source port");
        return false;
    }
    if (!validate_port(config->dst_port)) {
        output_error_json("Invalid destination port");
        return false;
    }
    if (!validate_protocol(config->protocol)) {
        output_error_json("Invalid protocol (must be 'tcp' or 'udp')");
        return false;
    }
    if (!validate_direction(config->direction)) {
        output_error_json("Invalid direction (must be 'upstream' or 'downstream')");
        return false;
    }
    return true;
}

/**
 * Handle the 'start' command
 * - Validates configuration
 * - Loads kernel module
 * - Configures and starts the test
 */
int handle_start_command(speedtest_config_t *config) {
    if (is_test_running()) {
        output_error_json("Test already running");
        return -1;
    }

    if (!validate_config(config)) {
        return -1;
    }

    if (load_kernel_module() != 0) {
        output_error_json("Failed to load kernel module");
        return -1;
    }

    if (configure_test(config) != 0) {
        output_error_json("Failed to configure test");
        unload_kernel_module();
        return -1;
    }

    if (start_test() != 0) {
        output_error_json("Failed to start test");
        unload_kernel_module();
        return -1;
    }

    config->status = TEST_STATUS_RUNNING;
    output_status_json(config);
    return 0;
}

/**
 * Handle the 'status' command
 * - Checks if test is running
 * - Returns current status and throughput
 */
int handle_status_command(speedtest_config_t *config) {
    if (!is_test_running()) {
        config->status = TEST_STATUS_IDLE;
        output_status_json(config);
        return 0;
    }

    if (get_test_results(config) != 0) {
        output_error_json("Failed to get test results");
        return -1;
    }

    output_status_json(config);
    return 0;
}

/**
 * Handle the 'stop' command
 * - Stops the test if running
 * - Outputs final results
 * - Cleans up resources
 */
int handle_stop_command(speedtest_config_t *config) {
    if (!is_test_running()) {
        output_error_json("No test running");
        return -1;
    }

    if (stop_test() != 0) {
        output_error_json("Failed to stop test");
        return -1;
    }

    if (get_test_results(config) != 0) {
        output_error_json("Failed to get final results");
        return -1;
    }

    config->status = TEST_STATUS_COMPLETED;
    output_result_json(config);

    unload_kernel_module();
    cleanup_resources();
    return 0;
}

void print_usage(void) {
    printf("Usage: linksys-udp-st <command> [options]\n");
    printf("Commands:\n");
    printf("  start --src-ip <ip> --dst-ip <ip> --src-port <port> --dst-port <port> \\\n");
    printf("        --protocol <tcp|udp> --direction <upstream|downstream>\n");
    printf("  status\n");
    printf("  stop\n");
    printf("\nExample:\n");
    printf("  linksys-udp-st start --src-ip 192.168.1.100 --dst-ip 192.168.1.200 \\\n");
    printf("                       --src-port 5201 --dst-port 5201 \\\n");
    printf("                       --protocol udp --direction upstream\n");
}

bool is_test_running(void) {
    return access("/sys/module/" NSS_UDP_ST_MODULE, F_OK) == 0;
}

void cleanup_resources(void) {
    if (is_test_running()) {
        unload_kernel_module();
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    // Set up signal handlers for graceful shutdown
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // Initialize configuration structure
    memset(&g_config, 0, sizeof(g_config));

    if (strcmp(argv[1], "start") == 0) {
        bool has_required_params = true;
        // Parse command line arguments for start
        for (int i = 2; i < argc; i += 2) {
            if (i + 1 >= argc) {
                has_required_params = false;
                break;
            }

            if (strcmp(argv[i], "--src-ip") == 0)
                strncpy(g_config.src_ip, argv[i + 1], sizeof(g_config.src_ip) - 1);
            else if (strcmp(argv[i], "--dst-ip") == 0)
                strncpy(g_config.dst_ip, argv[i + 1], sizeof(g_config.dst_ip) - 1);
            else if (strcmp(argv[i], "--src-port") == 0)
                g_config.src_port = atoi(argv[i + 1]);
            else if (strcmp(argv[i], "--dst-port") == 0)
                g_config.dst_port = atoi(argv[i + 1]);
            else if (strcmp(argv[i], "--protocol") == 0)
                strncpy(g_config.protocol, argv[i + 1], sizeof(g_config.protocol) - 1);
            else if (strcmp(argv[i], "--direction") == 0)
                strncpy(g_config.direction, argv[i + 1], sizeof(g_config.direction) - 1);
            else {
                has_required_params = false;
                break;
            }
        }

        if (!has_required_params) {
            output_error_json("Missing or invalid parameters");
            print_usage();
            return 1;
        }

        return handle_start_command(&g_config);
    } else if (strcmp(argv[1], "status") == 0) {
        return handle_status_command(&g_config);
    } else if (strcmp(argv[1], "stop") == 0) {
        return handle_stop_command(&g_config);
    } else {
        print_usage();
        return 1;
    }
}