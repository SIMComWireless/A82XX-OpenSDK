# Customer_Application

**English** | [简体中文](README_CN.md)

A relocatable workspace that turns the code in `customer_code/` into flashable firmware using the **SIMCOM
OpenSDK** for the A1903 RTOS series (ASR 1903SR / `A8272E`).

Point it at an SDK and run `build.bat`: your code is copied into the SDK, built there with the SDK's own
toolchain, and the firmware is copied back into `output/`. The folder works from any location, and the only trace
it leaves in the SDK is backed up and reversible with `build.bat restore`.

The first half of this document describes this folder. From [SDK reference](#sdk-reference) on, it is the OpenSDK
manual itself — included so that this folder is self-contained.

---

## Table of contents

- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Project structure](#project-structure)
- [Writing your code](#writing-your-code)
- [Build output](#build-output)
- [How the build works](#how-the-build-works)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [SDK reference](#sdk-reference)
  - [The split compilation scheme](#the-split-compilation-scheme)
  - [SDK directory layout](#sdk-directory-layout)
  - [SDK packages](#sdk-packages)
  - [Setting up the build environment](#setting-up-the-build-environment)
  - [Building from the SDK root](#building-from-the-sdk-root)
  - [Adding modules the SDK-native way](#adding-modules-the-sdk-native-way)
  - [Debug version](#debug-version)
- [Documentation](#documentation)

---

## Requirements

| Tool | Notes |
| --- | --- |
| **Python 3** | SIMCOM uses 3.8.5; higher versions are generally compatible. Install from [python.org](https://www.python.org/) and make sure `python` is on the system PATH — set it manually if the installer does not. |
| **Python packages** | `pip install kconfiglib windows-curses`. The `kconfiglib` script directory must also be on the system PATH. On a default Windows 10 + Python 3.8 install that is `C:\Users\<user>\AppData\Local\Programs\Python\Python38\Scripts\`. |
| **Git** | Provides **git bash**. Install with all defaults. |
| **SDK tools package** | The SDK's `tools/win32/` must be unpacked — see [SDK packages](#sdk-packages). |

Some of the chip vendor's build steps are shell scripts, so SIMCOM requires the build to run in a Linux-like shell
— git bash rather than the native Windows terminal. `build.bat` handles the invocation for you.

---

## Quick start

1. Open [build.bat](build.bat) and set `SDK_DIR` to the SDK root — the folder containing `build.py` and `kernel/`:

   ```bat
   set "SDK_DIR=E:\OpenSDK\2508027B01V01A8272M7B_SDK_260826\simcom_sdk"
   ```

   That is the only line you have to change. `APP_TARGET` below it can stay empty; the module name is detected from
   the SDK's `kernel/` directory. Set it only to build for one specific module.

2. Put your sources in `customer_code\src\` — see [Writing your code](#writing-your-code).

3. Run `build.bat`.

4. Collect the firmware from `output\` — see [Build output](#build-output).

---

## Commands

```bat
build.bat                REM build, incremental             (default)
build.bat rebuild        REM clean this module, then build
build.bat clean          REM delete the build output
build.bat menuconfig     REM configure features, text UI
build.bat guiconfig      REM configure features, GUI
build.bat restore        REM put the SDK's original files back
build.bat help           REM show usage
```

Run it from `cmd.exe` — double-clicked, from this folder, or from anywhere else.

---

## Project structure

```text
Customer_Application
|- build.bat            the build script; SDK_DIR is set at the top
|- customer_code        ALL the code — this is the part you edit
|  |- main.c            the SDK entry point (copied over AL\APP\main.c)
|  |- CMakeLists.txt    builds everything under src\ into one library
|  |- inc               headers
|  |- src               sources
|- output               build artifacts, written by build.bat
```

Nothing here is tied to this location — the whole folder can be copied or moved.

---

## Writing your code

- **Sources** — anywhere under `customer_code\src\`. All `.c` files are picked up automatically by
  `aux_source_directory`, so adding a file needs no edit to `CMakeLists.txt`. Subdirectories are *not* scanned; add
  them explicitly with `list(APPEND PACKAGE_SRC_FILES ...)` if you want them.
- **Headers** — `customer_code\inc\`, which is already on the include path.
- **Configuration switches** — `customer_code\inc\app_config.h`.
- **Entry point** — `customer_app_main()` in `customer_code\src\app_main.c`. It runs as a task, right after the
  SDK's `open_at_init()` and the stock demo menu have been started. The starter body creates a `sal_task` that logs
  a heartbeat every 5 seconds; replace it with your application.
- **`customer_code\main.c`** — one special file, and the only one outside `src\`. The SDK's entry point
  `userspace_main()` and the four split-scheme globals live in `<SDK>\AL\APP\main.c`, and the SDK offers no other
  hook to run customer code, so this file is a copy of it with a single `customer_app_main()` call added. Edit it
  only if you need to change the entry-task stack/priority or drop `simcom_demo_init()`. Because
  `aux_source_directory` only scans `src\`, this copy is *not* compiled into the customer library — `build.bat`
  copies it over `<SDK>\AL\APP\main.c`, and the SDK compiles it there.

The HAL / MAL / SAL / PL headers under the SDK root document what the SDK offers (GPIO, UART, I2C, SPI, PWM, ADC,
networking, sockets, TLS, MQTT, HTTP, file system, FOTA, ...). The guides in `../../Doc/` cover each peripheral.

---

## Build output

After a successful build, this folder contains:

| Path | Description |
| --- | --- |
| `output\customer_app.elf` | Application ELF, with debug information |
| `output\customer_app.elf.map` | Map file |
| `output\customer_app.elf.map.json` | Memory usage, parsed from the map file |
| `output\customer_app.bin` | Binary |
| `output\customer_app_crc.bin` | Binary with CRC |
| `output\customer_app_lzma.bin` | LZMA-compressed binary |
| `output\customer_app_lzma_crc.bin` | LZMA-compressed binary with CRC |
| `output\package\<module>\` | Flash package: `customer_app.bin`, `customer_app_lzma.bin`, kernel burn files |
| `output\build_<module>.log` | Link log |
| `output\simcom_build.log` | Compile log |

These are copies of what the SDK wrote under its own `output/<module>/APP/` — see
[Build outputs](#build-outputs) for that layout. The flash package is produced automatically as part of the
application build; there is no separate package step in this SDK.

---

## How the build works

Every build performs these steps:

1. Backs up `<SDK>\AL\APP\main.c` → `main.c.simcom` and `CMakeLists.txt` → `CMakeLists.txt.simcom`, the first time
   only.
2. Deletes `<SDK>\AL\APP\customer_code\` and re-copies `customer_code\` into it, so removed files do not linger.
3. Copies `customer_code\main.c` over `<SDK>\AL\APP\main.c`.
4. Appends an `add_subdirectory(customer_code)` block to `<SDK>\AL\APP\CMakeLists.txt`, once.
5. Builds with the SDK's own `python build.py <module>_app`.
6. Copies the firmware, the logs and the flash package back into `output\`.

That is the entire footprint on the SDK. `build.bat restore` undoes steps 1–4 and puts the SDK back exactly as
shipped.

### Demos

Because the build is an ordinary SDK build, the SDK's demo menu (`V2`) stays intact and is still reachable from the
PC tool `simcomDemoLinkerV2.exe`. `customer_code\main.c` calls `simcom_demo_init()` for that reason; delete that
call if you want a firmware without the demos.

---

## Configuration

Feature trimming uses the SDK's own Kconfig tree, so the switches you edit here are the ones the SDK build reads:

```bat
build.bat guiconfig      REM graphical interface
build.bat menuconfig     REM command-line interface
```

In `guiconfig`, a green cross next to an entry means it participates in the build; otherwise it is excluded.
**By default only the demos and the open-source libraries can be trimmed** — built-in SDK feature modules are
configured automatically by the build system. To trim those by hand, first enable the
**"Configure modules compilation manually."** entry, then save and close.

> After changing the configuration you must run `build.bat rebuild`, otherwise the change does not take effect.
> This is a restriction of the SDK, not of this script.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `ERROR: no build.py under SDK_DIR` or `no kernel\ directory under SDK_DIR` | `SDK_DIR` at the top of `build.bat` does not point at an SDK root. It must be the folder containing `build.py` and `kernel/`. |
| `ERROR: cannot detect the module name` | No module directory was found under `<SDK>\kernel\`. Set `APP_TARGET` explicitly at the top of `build.bat`. |
| `ERROR: python is not on PATH` | Install Python 3 and put it on the PATH — see [Requirements](#requirements). |
| The build fails while extracting `cmake.zip` / `cross_tool.zip` | The SDK's `tools/win32/` package is missing — see [SDK packages](#sdk-packages). |
| A configuration change had no effect | Run `build.bat rebuild`. The SDK requires a clean after a Kconfig change. |
| The build failed but the log looks fine | `build.py` always exits `0`, even when the compiler fails; it only prints a marker. `build.bat` reads `>>>>> build successed. <<<<<` from `output\build_<module>.log` to decide, so trust the `BUILD SUCCEEDED` / `BUILD FAILED` banner it prints. |
| You want to undo the SDK edits | Run `build.bat restore`. It restores `AL\APP\main.c` and `AL\APP\CMakeLists.txt` from the `.simcom` backups and removes `AL\APP\customer_code\`. |

---

## SDK reference

Everything from here on describes the SDK, not this folder. The SDK is SIMCOM's secondary-development package for
the A1903 RTOS series: it exposes the module's hardware and network capabilities through a layered C API, so that
application code can be written and built independently of the vendor firmware.

| | |
| --- | --- |
| Target module name | `A8272E` |
| Chip platform | ASR 1903SR |
| Compiler target | ARM Cortex-R5 |
| Compilation scheme | **split** — application and kernel are compiled and flashed separately |

### The split compilation scheme

Under the split scheme, application code and kernel code are **partitioned and compiled separately**, producing two
independent binaries that are flashed to different partitions.

How the SDK is delivered:

- The **kernel** is released as prebuilt binaries only (`cp.bin` / `cp.elf` under `kernel/`).
- The **application** layer is released in two parts — closed-source parts as static libraries, open-source parts
  as source.

The build then works like this: open-source application sources are compiled into libraries, those libraries are
linked together with the closed-source libraries into an ELF file, and the flashable binary is generated from that
ELF.

Because the scheme deliberately strips away the chip vendor's original build framework, **the SDK root directory
*is* the secondary-development entry root**.

> **Important:** application and kernel occupy separate code spaces and **cannot call each other's functions**.
> Application code may only use the APIs SIMCOM releases.

### SDK directory layout

```text
SIMCOM_SDK
|- HAL                      Driver-layer standard API wrappers
|- MAL                      Modem-layer standard API wrappers
|- SAL                      Application-leaning standard API wrappers
|- PL                       Protocol-layer standard API wrappers
|- AL                       Application layer
|  |- APP                   OpenSDK application-layer code
|  |  |- demo               OpenSDK sample code, driven over a PC tool (shipped in tools/)
|  |  |  |- V2              V2 samples (using the legacy API in sAPI)
|  |  |  |- V3              V3 samples (not yet implemented; uses the standard HAL/MAL/SAL/PL API)
|  |  |- main.c             OpenSDK code entry point
|  |- cmd_ui_protocol       PC tool communication protocol. Usable by customer code;
|  |                        see the demo for usage — no separate documentation is provided.
|  |- sAPI                  Legacy API implementation (wrappers over HAL/MAL/SAL/PL)
|- Pub                      Common utility implementations, optional; no documentation support
|- ThirdLibrary             Open-source libraries
|- configs                  OpenSDK configuration files
|- tools                    Build tooling
|  |- script                Build scripts
|  |- linux                 Tools for building on Linux (not supported by every SDK)
|  |- win32                 Tools for building on Windows
|- kernel                   Kernel output files
|- output                   Build output directory
|- CMakeLists.txt           Build script entry point
|- build.py                 Build command entry point
```

This `Customer_Application/` folder is **not** part of that tree — it sits alongside the SDK and is copied into
`AL/APP/` by `build.bat` (see [How the build works](#how-the-build-works)).

The `linux` and `win32` tool directories are **released separately** from the main SDK package — see
[SDK packages](#sdk-packages).

#### Key files

| Path | Purpose |
| --- | --- |
| `build.py` | The build command entry point. Run it with no arguments to print the usage manual. |
| `CMakeLists.txt` | Top-level CMake entry, drives the per-layer subdirectories. |
| `AL/APP/main.c` | Application entry point (`userspace_main`). |
| `configs/<VENDOR>/<MODEL>/Kconfig` | Feature configuration source; drives `guiconfig` / `menuconfig`. |
| `tools/script/` | Build helper scripts (Kconfig parsing, link-script generation, map-file accounting). |

### SDK packages

Because the tool directories are large and rarely change, they are extracted into separate archives. The SDK
therefore ships as **three packages**:

1. The **main package** — the SDK with the tools stripped out, as a quick start you can get from this link: [Main Package](https://1drv.ms/u/c/1964fa2b798f638e/IQCBbMDSRD_YT5amv-ughj0iAcUL4Iw01Ja6k6wzwOoLQSg?e=b3ajug)
2. The **Linux tools package**, you can get from this link: [Linux Tools Package](https://1drv.ms/u/c/1964fa2b798f638e/IQDgdDYVqxguSbFFxFarbI1rAYkev2LrM_oHaLoq0FPK8RI?e=cb14MI)
3. The **Windows tools package**, you can get from this link: [Windows Tools Package](https://1drv.ms/u/c/1964fa2b798f638e/IQCXJmuOsnJtQLeha68vZz7rAS_4iGl4n06BC-9SrG9ZOKU?e=B0yQnZ)

After receiving the SDK, unpack the tool archives and place them at the paths shown in
[SDK directory layout](#sdk-directory-layout) — i.e. `tools/linux/` and `tools/win32/` respectively.

> A copy of the SDK unpacked from the main package alone contains only `tools/script/`. `tools/win32/` or
> `tools/linux/` must be added before the build will run.

### Setting up the build environment

The standard build environment consists of **Python, CMake and Ninja**. Python is the main entry point, CMake is
the build-script generator, and Ninja performs the actual compilation.

CMake and Ninja are bundled in the tools package. **Python must be installed by the customer.** Some chip-vendor
build steps use shell scripts, so the build must run in a Linux-like shell environment — SIMCOM uses **git bash**,
which means **git must also be installed**. Once a build starts, tool configuration is handled automatically by
the Python scripts.

See [Requirements](#requirements) for the full list of tools and packages.

### Building from the SDK root

These are the raw SDK commands. `build.bat` in this folder wraps them — see [Commands](#commands).

1. Open **git bash** in the SDK root directory.

2. Run `./build.py` with no arguments to print the usage manual. If you hit permission problems, use
   `python build.py` instead. Either form works; prefer `./build.py` and fall back to `python build.py`.

3. Build a module by passing the target name:

   ```bash
   ./build.py A8272E_CXSN1000_1903_V101_OPENSDK
   ```

   Finished artifacts appear in `output/` under the SDK root.

4. Clean the generated files:

   ```bash
   ./build.py clean
   ```

#### Target naming

A target may be a bare module name, or a module name with a suffix:

| Suffix | Meaning |
| --- | --- |
| *(none)* | Full build |
| `_app` | Application only |
| `_clean` | Clean that module |
| `_clean_app` | Clean the application build only |

There are also standalone clean targets — `clean`, `clean_config`, `clean_all` — and configuration targets
`menuconfig` (text) and `guiconfig` (graphical).

> **Note on the kernel.** This SDK is released in prebuilt form, so the CP kernel cannot be rebuilt from it — the
> `kernel/` directory contains the finished binaries. There is therefore no `_kernel` target, and the kernel step
> of a full build is skipped automatically. (`_kernel`, `_install`, `install` and `upgrade` exist only in
> non-release development SDKs.)
>
> **Note on packaging.** There is no `_package` target either — the flash package is produced automatically as a
> `POST_BUILD` step of the application build, so `_app` alone gives you the package under
> `output/package/<module-name>/`.

Optional arguments:

| Argument | Meaning |
| --- | --- |
| `J=<n>` | Number of parallel compilation jobs; defaults to the CPU count. |
| `-c` | Clean the target before building. |

#### Build outputs

For the ASR series, building `A8272E_CXSN1000_1903_V101_OPENSDK` produces, under
`output/A8272E_CXSN1000_1903_V101_OPENSDK/`:

| File | Description |
| --- | --- |
| `APP/customer_app.elf` | Application target file, **with debug information** |
| `APP/customer_app.elf.map` | Map file |
| `APP/customer_app.bin` | Binary |
| `APP/customer_app_crc.bin` | Binary with CRC |
| `APP/customer_app_lzma.bin` | LZMA-compressed binary |
| `APP/customer_app_lzma_crc.bin` | LZMA-compressed binary with CRC |
| `APP/sc_buildlog.txt` | Link log |
| `simcom_build.log` | Compile log |

Any other files inside `APP/` are intermediate build artifacts.

#### Flash package path

For the ASR 18 and 19 series, the flash package is written to:

```text
./output/package/<module-name>/
```

### Adding modules the SDK-native way

This is the SDK's own extension mechanism: code lives **inside** the SDK tree under `AL/APP/`. If you would rather
keep your code in its own directory or its own repository, use this workspace instead — see
[Quick start](#quick-start).

#### The secondary-development entry point

The entry point for secondary-development code is the `void userspace_main(void *args)` function in
`AL/APP/main.c` (see [Key files](#key-files) for its path).

This function serves as the entry point of a task. That task has a default stack size of 4K and a default
priority of `sal_task_priority_low_1`. **When the function returns, the task is deleted automatically.**

To remove the stock `main.c`:

1. Delete `main.c`.
2. In the `CMakeLists.txt` in the same directory, delete everything except the `add_subdirectory(demo)` line and
   its enclosing `if` condition.
3. If the demo is not needed either, clear out the entire contents of that `CMakeLists.txt` — but **the file
   itself must not be deleted**.

You must then implement your own `void userspace_main(void *args)` in your own code.

Under the split scheme you must additionally declare the following global variables, mirroring `main.c`:

| Variable | Purpose |
| --- | --- |
| `char g_app_version[20];` | Application version number (reserved). |
| `char *g_main_stack;` | Stack for the entry task; `NULL` means allocate automatically. |
| `unsigned int g_main_stack_size = SAL_8K;` | Stack size for the entry task. If `g_main_stack` is non-`NULL`, allocate this much space. |
| `enum sal_task_priority g_main_task_priority = sal_task_priority_low_1;` | Priority of the entry task. |

These four globals control the creation of the entry task in the split scheme. The integrated scheme does not
require them, and cannot control entry-task creation parameters.

#### Adding a sub-application

By default, application code belongs under `./AL/APP`.

Using an application named `new_app` as an example:

1. Create a `new_app` directory under `./AL/APP`.
2. Add your source files to `./AL/APP/new_app`.
3. Add a `CMakeLists.txt` file to `./AL/APP/new_app`.
4. Write the build script in `./AL/APP/new_app/CMakeLists.txt`.
5. Add `add_subdirectory(new_app)` to `./AL/APP/CMakeLists.txt`.

Resulting layout:

```text
./AL/APP
|- new_app
|  |- sourc1.c
|  |- source2.c
|  |- source3.c
|  |- header1.h
|  |- header2.h
|  |- CMakeLists.txt
|  |- sub_dir
|     |- source4.c
|     |- sources5.c
|     |- header3.h
```

Example `./AL/APP/new_app/CMakeLists.txt`:

```cmake
# Set the app name; this becomes the compiled library name.
set(PACKAGE_NAME new_app)

# Set compilation options. "-Werror" treats all warnings as errors.
set(PACKAGE_PRIVATE_C_FLAGS "-Werror")

set(PACKAGE_INC_PATHS)
set(PACKAGE_SRC_FILES)

# Set header search paths.
list(APPEND PACKAGE_INC_PATHS
    ./
    ./sub_dir
    ../../sAPI
    ../../../SAL/inc
    ../../../SAL/${CHIP_VENDOR}
    ../../../MAL/inc
    ../../../MAL/${CHIP_VENDOR}
    ../../../HAL/inc
    ../../../HAL/${CHIP_VENDOR}
    ../../../PL
    ../../../Pub
)

# Add all source files in this directory to PACKAGE_SRC_FILES.
aux_source_directory(${CMAKE_CURRENT_SOURCE_DIR} PACKAGE_SRC_FILES)

# Add source4.c and sources5.c from the sub_dir subdirectory.
list(APPEND PACKAGE_SRC_FILES
    ./sub_dir/source4.c
    ${CMAKE_CURRENT_SOURCE_DIR}/sub_dir/sources5.c
)

# Compile everything in PACKAGE_SRC_FILES into a library.
sc_build_and_link_module(${PACKAGE_NAME} "${PACKAGE_SRC_FILES}" "${PACKAGE_INC_PATHS}" "" "${PACKAGE_PRIVATE_C_FLAGS}" "" "" "")
```

### Debug version

**Enabling it.** Build the debug version by enabling the debug option in `guiconfig`.

**What it does.** The debug version accounts for OS interface usage using a linked list. Every newly allocated
resource is recorded in the list, and removed from it when released.

Because of this extra list bookkeeping, the debug version **consumes additional memory and worsens memory
fragmentation**. Its purpose is debugging — tracking down memory leaks. **It must never be enabled in a production
build.**

**Using it.** The debug version provides an AT command to print the statistics:

```text
AT+MEMORYINFO
```

Because it is triggered by AT, an AT port must be available to issue the command.

---

## Documentation

Additional application guides are provided alongside the SDK (in `../../Doc/`), covering individual peripherals
and features:

- Device API, GPIO, UART, I2C, SPI, ADC, PWM
- RTOS development, low-power development
- Network registration, TCP/UDP networking, SSL, HTTP, FTP, MQTT, NTP/HTP
- File system, FOTA
- Call, SMS, SIM
- Cell-based positioning
