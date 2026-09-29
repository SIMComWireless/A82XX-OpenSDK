# Customer_Application - the customer's own source code.
#
# This directory is copied verbatim into <SDK_DIR>\AL\APP\customer_code\ by
# build.bat, and AL\APP\CMakeLists.txt then pulls it in with
# add_subdirectory(customer_code). It is built as a static library and linked
# into customer_app.elf together with the SDK libraries.
#
# Everything below the PACKAGE_* block is the standard module pattern; see
# README.md section 7.2 of the SDK documentation.

set(PACKAGE_NAME CUSTOMER-APP)

# Warnings are errors, as for the SDK's own modules.
set(PACKAGE_PRIVATE_C_FLAGS "-Werror")

set(PACKAGE_D_FLAGS)
set(PACKAGE_INC_PATHS)
set(PACKAGE_SRC_FILES)

list(APPEND PACKAGE_INC_PATHS
    ${CMAKE_CURRENT_SOURCE_DIR}/inc
    ${CMAKE_CURRENT_SOURCE_DIR}/../../demo   # userspaceConfig.h
    ${SIMCOM_PUBLIC_DIR}/AL/sAPI
    ${SIMCOM_PUBLIC_DIR}/AL/cmd_ui_protocol
    ${SIMCOM_PUBLIC_DIR}/SAL/inc
    ${SIMCOM_PUBLIC_DIR}/SAL/src
    ${SIMCOM_PUBLIC_DIR}/SAL/${CHIP_VENDOR}
    ${SIMCOM_PUBLIC_DIR}/MAL/inc
    ${SIMCOM_PUBLIC_DIR}/MAL/${CHIP_VENDOR}
    ${SIMCOM_PUBLIC_DIR}/HAL/inc
    ${SIMCOM_PUBLIC_DIR}/HAL/${CHIP_VENDOR}
    ${SIMCOM_PUBLIC_DIR}/PL
    ${SIMCOM_PUBLIC_DIR}/Pub
)

# All sources under src\, so new files are picked up without editing this file.
aux_source_directory(${CMAKE_CURRENT_SOURCE_DIR}/src PACKAGE_SRC_FILES)

sc_build_and_link_module(${PACKAGE_NAME} "${PACKAGE_SRC_FILES}" "${PACKAGE_INC_PATHS}" "${PACKAGE_D_FLAGS}" "${PACKAGE_PRIVATE_C_FLAGS}" "" "" "")
