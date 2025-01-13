#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <stdbool.h>
#include "module_ops.h"

#define NSS_UDP_ST_CMD "nss-udp-st"

static int execute_command(const char *command) {
    int status = system(command);
    if (status == -1) {
        fprintf(stderr, "Failed to execute command: %s\n", strerror(errno));
        return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
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

    // Stop test if running
    snprintf(cmd, sizeof(cmd), "%s --mode stop", NSS_UDP_ST_CMD);
    execute_command(cmd);

    // Finalize and clear
    snprintf(cmd, sizeof(cmd), "%s --mode final", NSS_UDP_ST_CMD);
    execute_command(cmd);

    snprintf(cmd, sizeof(cmd), "%s --mode clear", NSS_UDP_ST_CMD);
    return execute_command(cmd);
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
    snprintf(cmd, sizeof(cmd), "%s --mode stop", NSS_UDP_ST_CMD);
    return execute_command(cmd);
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
        fprintf(stderr, "Failed to open %s: %s\n", stats_file, strerror(errno));
        return -1;
    }

    char line[256];
    unsigned long throughput = 0;
    bool found_throughput = false;

    while (fgets(line, sizeof(line), fp)) {
        if (strstr(line, "Throughput:")) {
            if (sscanf(line, "Throughput: %lu", &throughput) == 1) {
                found_throughput = true;
                break;
            }
        }
    }

    fclose(fp);

    if (!found_throughput) {
        fprintf(stderr, "Failed to parse throughput from stats file\n");
        return -1;
    }

    config->throughput = throughput;
    return 0;
}