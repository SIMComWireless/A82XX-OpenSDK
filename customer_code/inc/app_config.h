#ifndef __APP_CONFIG_H__
#define __APP_CONFIG_H__

/*
 * Customer application configuration.
 *
 * Every macro is wrapped in #ifndef, so a value can also be overridden from
 * the command line without editing this file.
 */

#include "sal_os.h"


/* Module name that shows up in the log output. */
#ifndef CUSTOMER_LOG_MODULE
#define CUSTOMER_LOG_MODULE "CUST-APP"
#endif

/* Stack size of the customer application task. */
#ifndef CUSTOMER_TASK_STACK
#define CUSTOMER_TASK_STACK SAL_8K
#endif

/* How often the example task prints its heartbeat, in milliseconds. */
#ifndef CUSTOMER_TICK_MS
#define CUSTOMER_TICK_MS 5000
#endif


#endif /* __APP_CONFIG_H__ */
