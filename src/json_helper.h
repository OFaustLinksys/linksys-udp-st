#ifndef JSON_HELPER_H
#define JSON_HELPER_H

#include <stdio.h>
#include "linksys-udp-st.h"

// Error checking macro for JSON output
#define CHECK_JSON_OUTPUT(cond, err_msg) do { \
    if (!(cond)) { \
        fprintf(stderr, "JSON output error: %s\n", (err_msg)); \
        return; \
    } \
} while(0)

// JSON output functions
void output_status_json(speedtest_config_t *config);
void output_result_json(speedtest_config_t *config);
void output_error_json(const char *error_message);

#endif // JSON_HELPER_H