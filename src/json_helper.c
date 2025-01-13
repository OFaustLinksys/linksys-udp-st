#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "json_helper.h"

void output_status_json(speedtest_config_t *config) {
    const char *status_str;
    switch (config->status) {
        case TEST_STATUS_IDLE:
            status_str = "idle";
            break;
        case TEST_STATUS_RUNNING:
            status_str = "running";
            break;
        case TEST_STATUS_COMPLETED:
            status_str = "completed";
            break;
        case TEST_STATUS_FAILED:
            status_str = "failed";
            break;
        default:
            status_str = "unknown";
    }

    printf("{\n");
    printf("    \"status\": \"%s\",\n", status_str);
    if (config->status == TEST_STATUS_RUNNING) {
        printf("    \"throughput\": %lu,\n", config->throughput);
        printf("    \"unit\": \"bps\"\n");
    }
    printf("}\n");
}

void output_result_json(speedtest_config_t *config) {
    printf("{\n");
    printf("    \"test_config\": {\n");
    printf("        \"src_ip\": \"%s\",\n", config->src_ip);
    printf("        \"dst_ip\": \"%s\",\n", config->dst_ip);
    printf("        \"src_port\": %d,\n", config->src_port);
    printf("        \"dst_port\": %d,\n", config->dst_port);
    printf("        \"protocol\": \"%s\",\n", config->protocol);
    printf("        \"direction\": \"%s\"\n", config->direction);
    printf("    },\n");
    printf("    \"results\": {\n");
    printf("        \"throughput\": %lu,\n", config->throughput);
    printf("        \"unit\": \"bps\"\n");
    printf("    }\n");
    printf("}\n");
}

void output_error_json(const char *error_message) {
    printf("{\n");
    printf("    \"error\": \"%s\"\n", error_message);
    printf("}\n");
}
