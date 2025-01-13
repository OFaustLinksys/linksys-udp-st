#ifndef MODULE_OPS_H
#define MODULE_OPS_H

#include <stdbool.h>
#include "linksys-udp-st.h"

// Error checking macros
#define CHECK_NULL(ptr, msg) do { \
    if (!(ptr)) { \
        fprintf(stderr, "%s\n", (msg)); \
        return -1; \
    } \
} while(0)

#define CHECK_ERROR(cond, msg) do { \
    if (cond) { \
        fprintf(stderr, "%s\n", (msg)); \
        return -1; \
    } \
} while(0)

// Module management functions
int load_kernel_module(void);
int unload_kernel_module(void);

// Test configuration and control
int configure_test(speedtest_config_t *config);
int start_test(void);
int stop_test(void);
int get_test_results(speedtest_config_t *config);

#endif // MODULE_OPS_H