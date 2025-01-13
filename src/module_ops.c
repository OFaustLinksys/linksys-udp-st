#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <stdbool.h>
#include <ctype.h>
#include <stdarg.h>
#include "module_ops.h"

#define NSS_UDP_ST_CMD "nss-udp-st"

static void debug_log(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fprintf(stderr, "DEBUG: ");
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
    va_end(args);
}

static int execute_command(const char *command) {
    debug_log("Executing command: %s", command);
    int status = system(command);
    if (status == -1) {
        debug_log("Failed to execute command: %s", strerror(errno));
        return -1;
    }
    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    debug_log("Command exit code: %d", exit_code);
    return exit_code;
}

int load_kernel_module(void) {
    char cmd[512];

    // Initialize the module
    snprintf(cmd, sizeof(cmd), "%s --mode init --rate 1000 --buffer_sz 1500 --dscp 0 --net_dev eth4", 
             NSS_UDP_ST_CMD);
    if (execute_command(cmd) != 0) {
        return -1;
    }
    return 0;
}

int unload_kernel_module(void) {
    char cmd[512];

    // Make sure to stop and cleanup in all cases
    debug_log("Stopping test...");
    snprintf(cmd, sizeof(cmd), "%s --mode stop", NSS_UDP_ST_CMD);
    execute_command(cmd);  // Ignore errors, try to cleanup

    debug_log("Finalizing...");
    snprintf(cmd, sizeof(cmd), "%s --mode final", NSS_UDP_ST_CMD);
    execute_command(cmd);  // Ignore errors, try to cleanup

    debug_log("Clearing...");
    snprintf(cmd, sizeof(cmd), "%s --mode clear", NSS_UDP_ST_CMD);
    execute_command(cmd);  // Ignore errors, try to cleanup

    return 0;  // Return success to ensure cleanup is considered done
}

int configure_test(speedtest_config_t *config) {
    char cmd[512];

    // Create the test configuration
    snprintf(cmd, sizeof(cmd), 
             "%s --mode create --sip %s --dip %s --sport %d --dport %d --version 4",
             NSS_UDP_ST_CMD,
             config->src_ip, config->dst_ip,
             config->src_port, config->dst_port);

    return execute_command(cmd);
}

int start_test(void) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "%s --mode start --type tx", NSS_UDP_ST_CMD);
    return execute_command(cmd);
}

int stop_test(void) {
    char cmd[512];
    bool success = true;

    // First try to get final stats
    debug_log("Getting final stats...");
    snprintf(cmd, sizeof(cmd), "%s --mode stats --type tx", NSS_UDP_ST_CMD);
    if (execute_command(cmd) != 0) {
        debug_log("Warning: Failed to get final stats");
        success = false;
    }

    // Stop the test
    debug_log("Stopping test...");
    snprintf(cmd, sizeof(cmd), "%s --mode stop", NSS_UDP_ST_CMD);
    if (execute_command(cmd) != 0) {
        debug_log("Warning: Failed to stop test");
        success = false;
    }

    // Always try to cleanup
    debug_log("Cleaning up...");
    if (unload_kernel_module() != 0) {
        debug_log("Warning: Failed to cleanup completely");
        success = false;
    }

    return success ? 0 : -1;
}

int get_test_results(speedtest_config_t *config) {
    char cmd[512];
    char stats_file[] = "/tmp/nss-udp-st/tx_stats";

    // Get latest stats
    snprintf(cmd, sizeof(cmd), "%s --mode stats --type tx", NSS_UDP_ST_CMD);
    if (execute_command(cmd) != 0) {
        return -1;
    }

    // Read from stats file
    FILE *fp = fopen(stats_file, "r");
    if (!fp) {
        debug_log("Failed to open %s: %s", stats_file, strerror(errno));
        return -1;
    }

    char line[256];
    unsigned long throughput = 0;
    bool found_throughput = false;

    // Print entire file content for debugging
    debug_log("Stats file contents:");
    while (fgets(line, sizeof(line), fp)) {
        debug_log("> %s", line);

        // Make a copy for parsing
        char parse_line[256];
        strncpy(parse_line, line, sizeof(parse_line));

        // Convert to lowercase for case-insensitive matching
        for (char *p = parse_line; *p; ++p) *p = tolower(*p);

        // Look for various possible throughput indicators
        if (strstr(parse_line, "throughput:") || 
            strstr(parse_line, "rate:") || 
            strstr(parse_line, "speed:") ||
            strstr(parse_line, "mbps:") ||
            strstr(parse_line, "gbps:")) {

            // Try to find any number in the line
            char *p = parse_line;
            while (*p) {
                if (isdigit(*p)) {
                    throughput = strtoul(p, NULL, 10);
                    found_throughput = true;
                    debug_log("Found throughput: %lu", throughput);
                    break;
                }
                p++;
            }
            if (found_throughput) break;
        }
    }

    fclose(fp);

    if (!found_throughput) {
        debug_log("Failed to parse throughput from stats file");
        return -1;
    }

    config->throughput = throughput;
    return 0;
}