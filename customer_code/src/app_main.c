/*
 * Customer application main.
 *
 * Called from userspace_main() in main.c, after open_at_init() and the stock
 * demo menu have been started.
 */

#include <stddef.h>

#include "sal_os.h"
#include "sal_log.h"

#include "app_config.h"


#define LOG_INFO(...)  sal_log_info(CUSTOMER_LOG_MODULE, ##__VA_ARGS__)
#define LOG_ERROR(...) sal_log_error(CUSTOMER_LOG_MODULE, ##__VA_ARGS__)


/*
 * Example task: prints a heartbeat once per CUSTOMER_TICK_MS.
 *
 * Replace the body with the real application. Read the HAL/MAL/SAL/PL headers
 * under the SDK root for what is available; the guides in ../Doc cover each
 * peripheral.
 */
static void customer_app_task(void *args)
{
    LOG_INFO("customer task running");

    for (;;) {
        LOG_INFO("customer task heartbeat");
        sal_task_sleep(CUSTOMER_TICK_MS);
    }
}

void customer_app_main(void)
{
    sal_task_ref task = NULL;

    if (SAL_OS_SUCCESS != sal_task_create(&task,
                                          NULL,
                                          CUSTOMER_TASK_STACK,
                                          sal_task_priority_low_1,
                                          "cust_app",
                                          customer_app_task,
                                          NULL)) {
        LOG_ERROR("cannot create the customer task");
        return;
    }

    LOG_INFO("customer application ready");
}
