/*
 * SDK application entry point.
 *
 * build.bat copies this file over <SDK_DIR>\AL\APP\main.c, replacing the stock
 * entry point. The SDK's original is kept as main.c.simcom, and
 * "build.bat restore" puts it back.
 *
 * NOTE: this file is deliberately NOT inside src\. CMakeLists.txt only scans
 * src\ (aux_source_directory), so this file is not compiled into the customer
 * library - it is a replacement for one SDK file, and is compiled by the SDK's
 * own AL\APP\CMakeLists.txt instead.
 *
 * This file mirrors the stock main.c and only adds the call to
 * customer_app_main(), which lives in src\app_main.c.
 */

#include <stdio.h>

#include "sal_os.h"
#include "sal_log.h"
#include "userspaceConfig.h"


extern void open_at_init(void);
extern void customer_app_main(void);

#define LOG(...)       sal_log("APP-MAIN", ##__VA_ARGS__)
#define LOG_ERROR(...) sal_log_error("APP-MAIN", ##__VA_ARGS__)
#define LOG_INFO(...)  sal_log_info("APP-MAIN", ##__VA_ARGS__)
#define LOG_TRACE(...) sal_log_trace("APP-MAIN", ##__VA_ARGS__)


/** Detached app task parameters. */
char g_app_version[20];
char *g_main_stack;  // if NULL, stack will be malloc auto.
unsigned int g_main_stack_size = SAL_8K;
enum sal_task_priority g_main_task_priority = sal_task_priority_low_1;
/** Detached app task parameters End. */

/**
 * @brief User APP entrance. It will run as a task. Default stack is 4K. Default priority is sal_task_priority_low_1. When the entrance returned, the task will be deleted automatically.
 *
 */
void userspace_main(void *args)
{
    LOG_INFO("customer application starting");

    open_at_init();

#ifdef HAS_DEMO
    /* Keeps the stock demo menu reachable from simcomDemoLinkerV2.exe.
     * Delete this call to ship without the demos. */
    extern void simcom_demo_init(void);
    simcom_demo_init();
#endif

    /* The customer's own code. */
    customer_app_main();
}
