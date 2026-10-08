# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A **relocatable customer-application workspace** for the SIMCOM OpenSDK on the A1903 RTOS series
(ASR 1903SR, module `A8272E`). It contains almost no code of its own — it holds `customer_code/`
and two build scripts, and it builds by **copying `customer_code/` into an external SDK**, building
there with the SDK's own `build.py`, then copying the firmware back.

The SDK is *not* in this repo. On this machine it sits alongside it:

```
SDK_DIR=/home/zhenyu/Jack/A8272E/2508027B01V01A8272M7B_SDK_260826/simcom_sdk
```

`SDK_DIR` is hardcoded at the top of [build.sh](build.sh) (Linux) and [build.bat](build.bat)
(Windows). Each script carries its own path; neither derives anything from the other.

The upstream repo is `https://github.com/SIMComWireless/A82XX-OpenSDK.git`.

`README.md` is self-contained: the first half documents this workspace, and everything from
[SDK reference] onward is a copy of the OpenSDK manual. Per-peripheral guides (GPIO, UART, I2C, SPI,
PWM, ADC, TCP/UDP, MQTT, HTTP, SSL, FOTA, filesystem, low-power…) are Chinese-language PDFs in
`../2508027B01V01A8272M7B_SDK_260826/Doc/`.

## Commands

```bash
./build.sh              # build, incremental (default)
./build.sh rebuild      # clean this module, then build
./build.sh clean        # delete the build output
./build.sh menuconfig   # feature configuration, text UI
./build.sh guiconfig    # feature configuration, GUI (needs tkinter)
./build.sh restore      # put the SDK's original files back
./build.sh help
```

`build.bat` is the Windows/git-bash equivalent with the same commands. Raw SDK commands, for
reference — these are what `build.sh` wraps:

```bash
cd "$SDK_DIR" && python3 build.py A8272E_CXSN1000_1903_V101_OPENSDK_app   # app only
python3 build.py clean                                                     # clean generated files
```

Target suffixes: `_app` (application only), `_clean` (clean that module), `_clean_app`. There is no
`_kernel` target — the kernel ships as prebuilt binaries — and no `_package` target; packaging is a
`POST_BUILD` step of the app build.

**There is no test suite.** The only verification is the build itself.

### Reading a build result

`build.py` **always exits 0**, even when the compiler fails. A build only succeeded if
`output/build_<module>.log` contains `>>>>> build successed. <<<<<`. `build.sh` performs exactly
this check and prints a `BUILD SUCCEEDED` / `BUILD FAILED` banner — trust the banner, not `$?` or
the absence of compiler errors. The script also skips copying firmware on failure, so a failed
build never leaves stale binaries in `output/`.

## How the build works

Each run, `build.sh`:

1. Backs up `AL/APP/main.c` → `main.c.simcom` and `AL/APP/CMakeLists.txt` → `CMakeLists.txt.simcom`
   in the SDK (first run only).
2. Deletes `<SDK>/AL/APP/customer_code/` and re-copies `customer_code/` into it, so deleted files
   do not linger.
3. Copies `customer_code/main.c` over `<SDK>/AL/APP/main.c`.
4. Appends an `add_subdirectory(customer_code)` block to `<SDK>/AL/APP/CMakeLists.txt` (once).
5. Builds with `python3 build.py <module>_app` in the SDK root.
6. Copies firmware, logs and the flash package back into `output/`.

This is the entire footprint on the SDK. `build.sh restore` undoes steps 1–4. **The SDK is therefore
not read-only in practice** — prefer `restore` over hand-editing, and do not delete the `.simcom`
backups. The SDK currently on this machine is already patched (both `.simcom` files and
`AL/APP/customer_code/` exist).

This workspace folder is not part of the SDK tree and nothing in it is tied to its location.

## Architecture

### Layer stack

The SDK exposes hardware and network capability as layered C APIs, all rooted at `SDK_DIR`:

- `HAL` driver layer, `MAL` modem layer, `SAL` application-leaning layer, `PL` protocol layer, `Pub`
  common utilities, `ThirdLibrary` (mbedtls, cJSON, zlib, wakaama).
- `AL/` is the application layer: `APP/` (entry point + demos), `sAPI/` (legacy API implemented as
  wrappers over HAL/MAL/SAL/PL), `cmd_ui_protocol/` (PC-tool protocol, usable but undocumented
  beyond the demo), `AT/`.

Consumer code in `customer_code/` includes headers from all of these layers; its `CMakeLists.txt`
lists the include paths explicitly.

### Split compilation scheme

Application and kernel are compiled and flashed separately and **cannot call each other's
functions** — application code may only use the APIs SIMCOM releases. The kernel ships as prebuilt
`cp.bin`/`cp.elf` under `kernel/`. Because of this scheme, four globals in `AL/APP/main.c` control
creation of the entry task and **must be kept**:

`g_app_version[20]`, `g_main_stack`, `g_main_stack_size`, `g_main_task_priority`.

### Entry-point chain

```
userspace_main(void *args)   # customer_code/main.c, replaces SDK AL/APP/main.c, runs as a task
  -> open_at_init()          # SDK: AT command server
  -> simcom_demo_init()      # SDK stock demo menu, guarded by CONFIG_HAS_DEMO
  -> customer_app_main()     # customer_code/src/app_main.c — your code starts here
```

`userspace_main` runs as a task with a 4K default stack and `sal_task_priority_low_1`; when it
returns, the task is deleted. `customer_app_main()` therefore spawns its own long-lived task. The
shipped starter body creates a task that logs a heartbeat every `CUSTOMER_TICK_MS`.

### Where code goes

- **`customer_code/src/`** — all sources. Picked up automatically (`aux_source_directory`), so
  adding files needs no `CMakeLists.txt` edit.
- **`customer_code/inc/`** — headers, already on the include path. Configuration macros live in
  [app_config.h](customer_code/inc/app_config.h), all wrapped in `#ifndef` so they can be overridden
  from the command line: `CUSTOMER_LOG_MODULE`, `CUSTOMER_TASK_STACK`, `CUSTOMER_TICK_MS`.
- **`customer_code/main.c`** — the one special file, deliberately *outside* `src/`. `aux_source_directory`
  only scans `src/`, so it is **not** compiled into the customer library; it is a replacement for an
  SDK file and is compiled by the SDK's own `AL/APP/CMakeLists.txt`. Only edit it to change the entry
  task's stack/priority or to drop `simcom_demo_init()`.

### Two traps when adding code

- **`aux_source_directory` does not recurse.** Sources in subdirectories of `src/` are silently not
  compiled — add them explicitly with `list(APPEND PACKAGE_SRC_FILES ...)`.
- **`-Werror` is on** for the customer library (`PACKAGE_PRIVATE_C_FLAGS`), as for the SDK's own
  modules. Warnings break the build.

### Kconfig

`menuconfig` / `guiconfig` drive the SDK's own Kconfig tree, so switches edited there are the ones
the build reads. By default only the demos and open-source libraries can be trimmed; SDK feature
modules are configured automatically unless you enable *"Configure modules compilation manually."*
**A configuration change has no effect until `./build.sh rebuild`** — an SDK restriction.

### Logging and debugging

Log with `sal_log_info` / `sal_log_error` / `sal_log` / `sal_log_trace`, taking a module-name string
as the first argument (the starter uses `CUSTOMER_LOG_MODULE`). Captured over the module's USB port
with CATStudio; its database file is
`<SDK>/kernel/A8272E_CXSN1000_1903_V101_OPENSDK/cp.mdb`, and searching for `SIMCOM` filters the
useful lines.

## Build output

`output/` (gitignored) receives `customer_app.elf` (+ `.map`, `.map.json`), `customer_app.bin`,
`customer_app_crc.bin`, `customer_app_lzma.bin`, `customer_app_lzma_crc.bin`, the logs, and
`output/package/<module>/` — the flash package, whose `1903SC_NOR.blf` is selected in the
`A76XX_A79XX_A82XX_MADL` flashing tool. `output/build_<module>.log` is the link log and the source of
the success marker; `output/simcom_build.log` is the compile log.

## Linux host prerequisites

`build.sh` preflights all of these and fails with an explanatory message rather than a traceback:

- **Python 3.6+** (SIMCOM's reference is 3.8.5) — `build.py` uses f-strings and PEP 526 annotations;
  there is no Python 2 path in the SDK.
- **`kconfiglib`** — needed on *every* build, not just `menuconfig` (`build.py` imports `base_func`,
  which imports it), plus the `genconfig` **executable** on `PATH`, which `pip install --user`
  (in `~/.local/bin`) and venvs routinely do not provide.
- **`cmake` and `ninja`** — `build.py` hardcodes the Ninja generator. The release's `tools/win32/`
  bundles both; `tools/linux/` bundles neither, so on Linux they must come from the system.
  `ninja` was installed to `~/.local/bin` via `pip install --user --break-system-packages ninja`
  (no passwordless sudo on this machine); the host `cmake` is 4.2.3, which satisfies the SDK's
  `cmake_minimum_required(VERSION 3.10)`.
- **`cross_tool.tar.bz2`** — the Linux package ships the cross toolchain packed, and `build.py` only
  ever looks for `cross_tool.zip`, so nothing would unpack it. `build.sh` extracts it into
  `tools/linux/` whenever `cross_tool/gcc-arm-none-eabi/bin` is absent (so a half-unpacked
  `cross_tool/` is repaired too). The archive stores the exec bits a copied directory loses, which
  makes leaving it packed the better resting state. `build.bat` has no equivalent need — the Windows
  package ships `.exe` tools and a `.zip` toolchain that `build.py` unpackages itself.
- **`crc_set` and `lzma`** from `tools/linux/` — the packaging step calls both by bare name
  (`CMakeLists.txt:167-169`, with `LZMA_EXE`/`CRC_SET` set in
  `configs/ASR/1903SR/toolchain.cmake:11-12`). On Linux the SDK ships the LZMA tool as
  **`lzma_asr_lnx`**, not `lzma`, so an alias is required: `tools/linux/lzma -> lzma_asr_lnx`.
  Otherwise the name `lzma` resolves to Ubuntu's `/usr/bin/lzma` from `xz-utils`, which has no `e`
  subcommand while the SDK runs `lzma e <in> <out>`. That failure looks like

  ```
  lzma: e: No such file or directory
  lzma: customer_app_lzma.bin: No such file or directory
  ```

  and then `ninja: build stopped: subcommand failed`. Those messages are **xz's**, not the SDK
  tool's, which is what identifies this. `build.py` only *appends* `tools/linux` to `PATH`
  (`build.py:117`), so it can never beat `/usr/bin`.

  **Both the alias and the tools' execute bits are fragile, and `build.sh` repairs them itself.**
  Re-extracting the tools package (or restoring the directory from a backup) drops Unix permissions,
  which defeats the alias too: on 2026-10-08 a refresh left `crc_set`, `lzma_asr_lnx`,
  `aboot/adownload` and `aboot/arelease` as `-rw-r--r--`. The non-obvious consequence is that
  `build.sh` then quietly stops preferring `tools/linux` at all, because its `[ -x ]` test fails —
  so it never prepends the directory and the host `xz` lzma wins. Its preflight now chmods those
  tools and creates the alias when missing, announcing each change with a ` Repaired : ...` line, so
  a reset `tools/linux` no longer needs hand-fixing:

  ```bash
  chmod +x tools/linux/{lzma_asr_lnx,crc_set,make_image.sh} tools/linux/aboot/{adownload,arelease}
  ln -sf lzma_asr_lnx tools/linux/lzma
  ```

  Missing `tools/win32/` or `tools/linux/` entirely (they are released as separate archives) still
  fails the build with the `cmake.zip` / `cross_tool.zip` extraction error in the README.

## Conventions

`build.sh` is written in an unusually heavy *rationale-comment* style: it explains why each check
exists and cites exact SDK line numbers (e.g. `build.py:81-82`, `base_func.py:186`) for behaviour it
is working around. When changing it, match that — a check without its reason documented, or a claim
about `build.py` without the line reference, is inconsistent with the file. Comments are ASCII only.
