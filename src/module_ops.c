#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <stdbool.h>  // Added for bool type
#include "module_ops.h"

#define MODPROBE_PATH "/sbin/modprobe"
#define RMMOD_PATH "/sbin/rmmod"
#define SYSFS_PATH "/sys/kernel/debug/nss_udp_st"
#define MAX_SYSFS_PATH 128

/**
 * Execute a shell command and return its exit status
 * @param command The command to execute
 * @return 0 on success, -1 on failure
 */
static int execute_command(const char *command) {
    int status = system(command);
    if (status == -1) {
        fprintf(stderr, "Failed to execute command: %s\n", strerror(errno));
        return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/**
 * Write a value to a sysfs file
 * @param filename The name of the file in the nss_udp_st sysfs directory
 * @param value The value to write
 * @return 0 on success, -1 on failure
 */
static int write_sysfs_file(const char *filename, const char *value) {
    char path[MAX_SYSFS_PATH];
    snprintf(path, sizeof(path), "%s/%s", SYSFS_PATH, filename);

    FILE *fp = fopen(path, "w");
    if (!fp) {
        fprintf(stderr, "Failed to open %s: %s\n", path, strerror(errno));
        return -1;
    }

    int ret = fprintf(fp, "%s\n", value);
    fclose(fp);

    return (ret < 0) ? -1 : 0;
}

int load_kernel_module(void) {
    char cmd[MAX_CMD_LEN];
    snprintf(cmd, sizeof(cmd), "%s %s", MODPROBE_PATH, NSS_UDP_ST_MODULE);
    return execute_command(cmd);
}

int unload_kernel_module(void) {
    char cmd[MAX_CMD_LEN];
    snprintf(cmd, sizeof(cmd), "%s %s", RMMOD_PATH, NSS_UDP_ST_MODULE);
    return execute_command(cmd);
}

int configure_test(speedtest_config_t *config) {
    char config_str[MAX_CMD_LEN];

    // Configure 5-tuple
    snprintf(config_str, sizeof(config_str), "%s %s %d %d %s",
             config->src_ip, config->dst_ip,
             config->src_port, config->dst_port,
             config->protocol);

    if (write_sysfs_file("config", config_str) != 0) {
        return -1;
    }

    // Set direction
    return write_sysfs_file("direction", config->direction);
}

int start_test(void) {
    return write_sysfs_file("start", "1");
}

int stop_test(void) {
    return write_sysfs_file("start", "0");
}

int get_test_results(speedtest_config_t *config) {
    char path[MAX_SYSFS_PATH];
    snprintf(path, sizeof(path), "%s/stats", SYSFS_PATH);

    FILE *fp = fopen(path, "r");
    if (!fp) {
        fprintf(stderr, "Failed to open %s: %s\n", path, strerror(errno));
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
        fprintf(stderr, "Failed to parse throughput from stats\n");
        return -1;
    }

    config->throughput = throughput;
    return 0;
}