#ifndef LINKSYS_UDP_ST_H
#define LINKSYS_UDP_ST_H

#include <stdbool.h>

#define NSS_UDP_ST_MODULE "nss_udp_st"
#define DEFAULT_TEST_TIME 20
#define DEFAULT_BUFFER_SIZE 4096

typedef enum {
    TEST_STATUS_IDLE,
    TEST_STATUS_RUNNING,
    TEST_STATUS_COMPLETED,
    TEST_STATUS_FAILED
} test_status_t;

typedef struct {
    char src_ip[16];
    char dst_ip[16];
    int src_port;
    int dst_port;
    char protocol[8];
    char direction[16];
    test_status_t status;
    unsigned long throughput;
} speedtest_config_t;

// Main command functions
int handle_start_command(speedtest_config_t *config);
int handle_status_command(speedtest_config_t *config);
int handle_stop_command(speedtest_config_t *config);

// Utility functions
void print_usage(void);
bool is_test_running(void);
void cleanup_resources(void);

#endif // LINKSYS_UDP_ST_H