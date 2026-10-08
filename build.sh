#!/usr/bin/env bash
#
# ============================================================================
#  Customer_Application build script (Linux / git bash)
#
#  POSIX counterpart of build.bat. Same scheme, same commands, same output:
#  the code in customer_code/ is copied into the SIMCOM OpenSDK, built there
#  with the SDK's own build.py, and the firmware is copied back into output/.
#
#  How it works (the "copy into the SDK" scheme):
#    1. customer_code/ is copied into <SDK_DIR>/AL/APP/customer_code/
#    2. customer_code/main.c is copied over <SDK_DIR>/AL/APP/main.c
#       (the SDK's originals are backed up as *.simcom on the first run)
#    3. the SDK is built with its own build.py
#    4. the firmware and the flash package are copied back into output/
#
#  Commands:
#    ./build.sh              build (incremental)          [default]
#    ./build.sh rebuild      clean this module, then build
#    ./build.sh clean        delete the build output
#    ./build.sh menuconfig   configure features, text UI
#    ./build.sh guiconfig    configure features, GUI
#    ./build.sh restore      put the SDK's original files back
#    ./build.sh help         show this text
#
#  NOTE: after changing the configuration you must run "./build.sh rebuild",
#        otherwise the change does not take effect.
#
#  Where this differs from build.bat, and why:
#    - SDK_DIR is defined on its own below. The two scripts are independent:
#      build.sh never reads build.bat, and its SDK path is not derived from
#      build.bat's path or from where this file happens to sit. Point each one
#      at the SDK as that machine sees it
#    - the interpreter is chosen at run time and version-checked, because
#      build.py is Python 3 only and older machines have both kinds around:
#      python3 first, then any versioned python3.x, then python - the first
#      that is 3.6 or newer wins. Python 2 is not a fallback (see the note
#      above PYTHON_MIN below)
#    - the tool package is picked from the host exactly the way build.py picks
#      it: tools/win32 on Windows (this script works there too, under git
#      bash), tools/linux everywhere else. Only the Linux side needs system
#      tools, because only the win32 package bundles them: a cmake, and a
#      ninja (build.py's generator and build command are both hardcoded to
#      Ninja, and build.py:81-82 is the only place that could be changed).
#      Both are checked up front, so the failure is a sentence rather than a
#      traceback out of cmake
#    - no "pause" at the end: a terminal already keeps the output on screen
# ============================================================================


# This folder, whatever it is called and wherever it sits.
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- The only path you normally need to change ----------------------------
# The SIMCOM OpenSDK root on THIS machine: the directory that holds build.py
# and kernel/. Deliberately independent of build.bat - each script carries its
# own path, nothing is derived from the other or from where this file sits.
# Set it to wherever the SDK lives on the Linux box.
SDK_DIR="/home/zhenyu/Jack/A8272E/2508027B01V01A8272M7B_SDK_260826/simcom_sdk"

# Leave APP_TARGET empty to detect the module from $SDK_DIR/kernel/.
# Set it explicitly to build for a specific module.
APP_TARGET=""
# ---------------------------------------------------------------------------

SDK_APP_DIR="$SDK_DIR/AL/APP"
OUT_DIR="$APP_DIR/output"


usage() {
    echo "Usage: build.sh [command]"
    echo
    echo "  (no command)   build, incremental             [default]"
    echo "  rebuild        clean this module, then build"
    echo "  clean          delete the build output"
    echo "  menuconfig     configure features, text UI"
    echo "  guiconfig      configure features, GUI"
    echo "  restore        put the SDK's original files back"
    echo "  help           show this text"
    echo
    echo "Before the first build, set SDK_DIR at the top of this script to your"
    echo "SIMCOM OpenSDK directory."
}


# ============================================================================
#  Command line
# ============================================================================
ACTION="build"
if [ $# -gt 0 ]; then
    case "$1" in
        build|app)       ACTION="build" ;;
        rebuild)         ACTION="rebuild" ;;
        clean)           ACTION="clean" ;;
        menuconfig)      ACTION="menuconfig" ;;
        guiconfig)       ACTION="guiconfig" ;;
        restore)         ACTION="restore" ;;
        help|-h|--help)  ACTION="help" ;;
        *)
            echo "ERROR: unknown command \"$1\"" >&2
            usage
            exit 1
            ;;
    esac
fi
if [ "$ACTION" = "help" ]; then
    usage
    exit 0
fi


# ============================================================================
#  Validate the environment
# ============================================================================
if [ ! -f "$SDK_DIR/build.py" ]; then
    echo "ERROR: no build.py under SDK_DIR:" >&2
    echo "       $SDK_DIR" >&2
    echo "       Fix SDK_DIR at the top of this script." >&2
    exit 1
fi
if [ ! -d "$SDK_DIR/kernel" ]; then
    echo "ERROR: no kernel/ directory under SDK_DIR:" >&2
    echo "       $SDK_DIR" >&2
    echo "       This does not look like a SIMCOM release OpenSDK." >&2
    exit 1
fi

# Detect the module name from the one directory under kernel/.
TARGET="$APP_TARGET"
if [ -z "$TARGET" ]; then
    for d in "$SDK_DIR"/kernel/*/; do
        [ -d "$d" ] || continue      # unmatched glob stays literal
        TARGET="$(basename "$d")"
        break
    done
fi
if [ -z "$TARGET" ]; then
    echo "ERROR: cannot detect the module name." >&2
    echo "       Set APP_TARGET at the top of this script." >&2
    exit 1
fi

APP_OUT="$SDK_DIR/output/$TARGET/APP"

# build.py chooses its tool directory from the host, not from a setting:
# Windows uses tools/win32 (and cmake from inside it), everything else uses
# tools/linux (and a bare "cmake" from PATH). Mirror that choice here so the
# preflight below matches what the SDK is actually going to do.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) TOOLS_PLAT="win32" ;;
    *)                    TOOLS_PLAT="linux" ;;
esac

echo
echo " SDK      : $SDK_DIR"
echo " Module   : $TARGET"
echo " App dir  : $APP_DIR"
echo " Tools    : tools/$TOOLS_PLAT"
echo " Command  : $ACTION"
echo


# ============================================================================
#  clean / restore
#  TARGET is always set by now, so the recursive deletes below cannot escape.
# ============================================================================
if [ "$ACTION" = "clean" ]; then
    rm -rf "$SDK_DIR/output/$TARGET"
    rm -rf "$SDK_DIR/output/package/$TARGET"
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"
    echo "Cleaned the build output of $TARGET."
    exit 0
fi

if [ "$ACTION" = "restore" ]; then
    if [ ! -f "$SDK_APP_DIR/main.c.simcom" ]; then
        echo "Nothing to restore - the SDK has not been patched by this script."
        exit 0
    fi
    cp -f "$SDK_APP_DIR/main.c.simcom" "$SDK_APP_DIR/main.c"
    if [ -f "$SDK_APP_DIR/CMakeLists.txt.simcom" ]; then
        cp -f "$SDK_APP_DIR/CMakeLists.txt.simcom" "$SDK_APP_DIR/CMakeLists.txt"
    else
        echo "WARNING: CMakeLists.txt.simcom is missing - AL/APP/CMakeLists.txt"
        echo "         still carries the appended add_subdirectory for customer_code."
    fi
    rm -rf "$SDK_APP_DIR/customer_code"
    rm -f "$SDK_APP_DIR/main.c.simcom"
    rm -f "$SDK_APP_DIR/CMakeLists.txt.simcom"
    echo "Restored the SDK originals in $SDK_APP_DIR"
    exit 0
fi


# ============================================================================
#  Check the tools up front, so a failure is obvious rather than cryptic.
# ============================================================================
# build.py is Python 3 only, and not in the vague sense: it uses f-strings and
# PEP 526 variable annotations (see "supported_targets:dict = ..." around line
# 265), both introduced in Python 3.6. There is no Python 2 path anywhere in
# this SDK - every .py in the build chain (build.py and tools/script/*.py) is
# 3.x, build.py's shebang is "#!/usr/bin/env python3", and its own usage text
# says "python3 build.py [target]". So the major version is not a choice to be
# made: it has to be 3. Python 2 cannot even parse the file. "Which scheme"
# therefore reduces to "which Python 3", and the answer is any 3.6 or newer,
# preferring an already-installed one over asking you to install anything.
#
# build.py has no version guard of its own, so a wrong interpreter does not say
# "your python is too old" - it dies with a bare "SyntaxError: invalid syntax"
# from deep inside the file. Hence check the version, not just whether the name
# resolves: a distro's "python3" can predate 3.6, and a bare "python" is still
# Python 2 on plenty of machines.
PYTHON_MIN="3.6"
PYTHON=""
PYTHON_SEEN=""
PYTHON2_SEEN=""
# Any versioned interpreters lying around, newest first, in case the default
# python3 turns out to be too old. (python2.* is deliberately not searched:
# finding one would not help.)
PYTHON_EXTRA=$(ls -1 /usr/bin/python3.* /usr/local/bin/python3.* 2>/dev/null | sort -rV)
for candidate in python3 $PYTHON_EXTRA python; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    ver=$("$candidate" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)
    [ -n "$ver" ] || continue
    # Remember a Python 2 so the error below can name it and rule it out,
    # rather than leaving it looking like an option that was merely skipped.
    case "${ver%%.*}" in
        2)  PYTHON2_SEEN="$PYTHON2_SEEN $candidate($ver)"
            continue ;;
    esac
    PYTHON_SEEN="$PYTHON_SEEN $candidate($ver)"
    # The tuple here must stay in step with PYTHON_MIN above.
    if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' 2>/dev/null; then
        PYTHON="$candidate"
        PYTHON_VER="$ver"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo "ERROR: no Python $PYTHON_MIN or newer on PATH." >&2
    [ -n "$PYTHON_SEEN" ]  && echo "       Found, Python 3 but too old:$PYTHON_SEEN" >&2
    [ -n "$PYTHON2_SEEN" ] && echo "       Found, Python 2:$PYTHON2_SEEN" >&2
    echo "       build.py is Python 3 only and needs $PYTHON_MIN+" >&2
    echo "       (SIMCOM's reference interpreter is 3.8.5)." >&2
    if [ -n "$PYTHON2_SEEN" ]; then
        echo "       Python 2 will not do. There is no 2.x path in this SDK and" >&2
        echo "       no fallback to select - build.py cannot even parse under 2.x." >&2
    fi
    echo "       Install a $PYTHON_MIN+ Python 3 and re-run, or put one that is" >&2
    echo "       already installed ahead of the old one on PATH." >&2
    if [ "$TOOLS_PLAT" = "win32" ]; then
        echo "       Then: python -m pip install kconfiglib windows-curses" >&2
    else
        echo "       Then: python3 -m pip install kconfiglib" >&2
        echo "       (guiconfig additionally needs tkinter, e.g. apt install python3-tk)" >&2
    fi
    exit 1
fi
echo " Python   : $PYTHON ($PYTHON_VER)"

# build.py imports base_func unconditionally, and base_func imports kconfiglib,
# so this is needed for every build - not just for menuconfig/guiconfig.
# Installing it for a different interpreter is an easy hour to lose.
if ! "$PYTHON" -c 'import kconfiglib' >/dev/null 2>&1; then
    echo "ERROR: kconfiglib is not installed for $PYTHON ($PYTHON_VER)." >&2
    echo "       build.py needs it on every run. Installing it for a different" >&2
    echo "       interpreter or user does not count." >&2
    echo "       Fix:  $PYTHON -m pip install kconfiglib" >&2
    exit 1
fi

# ----------------------------------------------------------------------------
#  kconfiglib's command line tools
#
# The library being importable is only half of it. The build also shells out to
# "genconfig" as an *executable* - base_func.py:186, "subprocess.run(['genconfig',
# '--config-out', '.config'])", found through PATH like any other command. That
# happens whenever .config is absent, which is the normal state of a fresh SDK:
# .config is a dotfile the release does not ship and the first build generates.
# (menuconfig / guiconfig are the same story, one step further out.)
#
# So "import kconfiglib" succeeding proves nothing here. The scripts are the
# part that goes missing, because where pip puts them is not where PATH looks:
# "pip install --user" uses ~/.local/bin, a venv uses its own bin/, and a
# distro package can install the modules with no PATH-visible script at all.
# ----------------------------------------------------------------------------
KCONFIG_TOOL="genconfig"
if [ "$ACTION" = "menuconfig" ]; then KCONFIG_TOOL="menuconfig"; fi
if [ "$ACTION" = "guiconfig" ]; then KCONFIG_TOOL="guiconfig"; fi

KCONFIG_SHIM_DIR=""
NINJA_SHIM_DIR=""
cleanup_shims() {
    [ -n "$KCONFIG_SHIM_DIR" ] && rm -rf "$KCONFIG_SHIM_DIR"
    [ -n "$NINJA_SHIM_DIR" ] && rm -rf "$NINJA_SHIM_DIR"
    return 0
}
trap cleanup_shims EXIT

KCONFIG_NOTE=""

if ! command -v "$KCONFIG_TOOL" >/dev/null 2>&1; then
    # Ask the chosen interpreter where its own script directories are instead of
    # trusting PATH. Several schemes, because the default one is not always the
    # directory that was written to - it resolves to nothing at all on some
    # builds. Emitted one path per line, with forward slashes: a directory with
    # a space in it then survives, and a Windows path is not mangled by the
    # shell reading "\" as an escape.
    KCONFIG_DIRS=$(
        "$PYTHON" -c '
import os, sysconfig
dirs = []
for scheme in (None, "posix_user", "nt_user", "posix_prefix"):
    try:
        p = sysconfig.get_path("scripts", scheme)
    except Exception:
        continue
    if p:
        p = p.replace(os.sep, "/")
        if p not in dirs and os.path.isdir(p):
            dirs.append(p)
print("\n".join(dirs))
' 2>/dev/null
        # Where pipx and "pip install --user" put things, whatever interpreter
        # is in use - so worth checking without asking Python at all.
        printf '%s\n' "$HOME/.local/bin" /usr/local/bin
    )
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        if [ -x "$d/$KCONFIG_TOOL" ]; then
            PATH="$d:$PATH"
            export PATH
            KCONFIG_NOTE=" Kconfig  : $KCONFIG_TOOL from $d (added to PATH)"
            break
        fi
    done <<EOF
$KCONFIG_DIRS
EOF
fi

if ! command -v "$KCONFIG_TOOL" >/dev/null 2>&1; then
    # Nothing on PATH, but if the *module* is installed we can reach the same
    # entry point the console script would have called: "python -m genconfig".
    # That covers a distro package that ships the modules only. Temporary, and
    # removed again by the trap above.
    if "$PYTHON" -c "import $KCONFIG_TOOL" >/dev/null 2>&1; then
        KCONFIG_SHIM_DIR=$(mktemp -d "${TMPDIR:-/tmp}/simcom-kconfig.XXXXXX" 2>/dev/null)
        if [ -n "$KCONFIG_SHIM_DIR" ]; then
            # Absolute interpreter path: build.py appends its own directories to
            # PATH later, and a bare name would then resolve against whatever
            # happens to be first by the time the shim runs.
            printf '#!/bin/sh\nexec "%s" -m %s "$@"\n' "$(command -v "$PYTHON")" "$KCONFIG_TOOL" \
                > "$KCONFIG_SHIM_DIR/$KCONFIG_TOOL"
            chmod +x "$KCONFIG_SHIM_DIR/$KCONFIG_TOOL"
            PATH="$KCONFIG_SHIM_DIR:$PATH"
            export PATH
            KCONFIG_NOTE=" Kconfig  : no $KCONFIG_TOOL script on PATH; using a shim that runs
            \"$(command -v "$PYTHON") -m $KCONFIG_TOOL\" (the module is installed)"
        fi
    fi
fi

if ! command -v "$KCONFIG_TOOL" >/dev/null 2>&1; then
    # How much this matters depends on which tool is wanted. genconfig is only
    # reached when the SDK has no .config yet - that file is what it generates -
    # so with one already present it is not going to be called, and a working
    # build should not be turned into a failure over it. menuconfig and
    # guiconfig are the opposite: they ARE the action, so a missing one is
    # always fatal. Either way a missing tool must be caught here, because
    # otherwise it surfaces much later as a bare FileNotFoundError out of a
    # subprocess call, with nothing to say about what is missing.
    KCONFIG_HAVE_CONFIG=""
    for f in "$SDK_DIR"/configs/*/*/.config "$SDK_DIR"/config/.config; do
        if [ -f "$f" ]; then KCONFIG_HAVE_CONFIG="$f"; break; fi
    done

    if [ "$KCONFIG_TOOL" = "genconfig" ] && [ -n "$KCONFIG_HAVE_CONFIG" ]; then
        echo " WARNING  : no \"$KCONFIG_TOOL\" on PATH."
        echo "            $KCONFIG_HAVE_CONFIG"
        echo "            already exists, so this build will not call it - but the SDK"
        echo "            looks for it by name whenever that file is missing, so the next"
        echo "            clean build will fail without it. See the prerequisites in"
        echo "            README.md: kconfiglib's script directory has to be on PATH,"
        echo "            not merely importable."
    else
        if [ "$KCONFIG_TOOL" = "genconfig" ]; then
            echo "ERROR: \"genconfig\" is not on PATH, and the SDK has no .config yet." >&2
            echo "       genconfig is what generates that file, so the build cannot get" >&2
            echo "       past that step." >&2
        else
            echo "ERROR: \"$KCONFIG_TOOL\" is not on PATH." >&2
            echo "       It is the tool this action runs, so there is nothing to fall" >&2
            echo "       back on." >&2
        fi
        echo "       It is not part of the SDK: it is one of the command line tools" >&2
        echo "       that ship with kconfiglib, and the SDK calls it by name, so a" >&2
        echo "       working \"import kconfiglib\" is not enough - the script itself" >&2
        echo "       has to be somewhere PATH looks." >&2
        echo "       A plain \"pip install --user\" puts it in ~/.local/bin, which is" >&2
        echo "       not on PATH by default; Ubuntu 24.04 and newer also refuse a" >&2
        echo "       system-wide pip install (PEP 668), so use one of:" >&2
        echo "         sudo apt install python3-kconfiglib          # distro package" >&2
        echo "         sudo apt install pipx && pipx install kconfiglib" >&2
        echo "         python3 -m venv ~/.venvs/simcom && ~/.venvs/simcom/bin/pip install kconfiglib" >&2
        echo "       Re-running this script after any of those will pick it up." >&2
        exit 1
    fi
fi

# Say which one it settled on, so a wrong pick is visible before the build
# rather than in a traceback halfway through it.
if [ -z "$KCONFIG_NOTE" ]; then
    KCONFIG_RESOLVED=$(command -v "$KCONFIG_TOOL" 2>/dev/null)
    [ -n "$KCONFIG_RESOLVED" ] && KCONFIG_NOTE=" Kconfig  : $KCONFIG_TOOL -> $KCONFIG_RESOLVED"
fi
[ -n "$KCONFIG_NOTE" ] && echo "$KCONFIG_NOTE"


# ============================================================================
#  menuconfig / guiconfig
#  These edit the SDK's own Kconfig tree, which is the one this build uses.
# ============================================================================
if [ "$ACTION" = "menuconfig" ] || [ "$ACTION" = "guiconfig" ]; then
    pushd "$SDK_DIR" >/dev/null || { echo "ERROR: cannot enter $SDK_DIR" >&2; exit 1; }
    "$PYTHON" build.py "$ACTION"
    CFG_RC=$?
    popd >/dev/null
    echo
    if [ "$CFG_RC" -eq 0 ]; then
        echo 'Configuration saved. Now run "./build.sh rebuild" for it to take effect.'
    fi
    exit "$CFG_RC"
fi


# ============================================================================
#  build
# ============================================================================
# build.py needs the tool package for this host, and on Linux it takes a bare
# "cmake" from PATH. Both failures are otherwise reported from deep inside the
# build, so check them first.
if [ "$TOOLS_PLAT" = "linux" ] && ! command -v cmake >/dev/null 2>&1; then
    echo "ERROR: cmake is not on PATH." >&2
    echo "       On Linux build.py does not bundle cmake the way the Windows" >&2
    echo "       tools package does - install it: apt install cmake" >&2
    exit 1
fi
if [ ! -d "$SDK_DIR/tools/$TOOLS_PLAT" ]; then
    echo "ERROR: no tools/$TOOLS_PLAT/ directory under SDK_DIR:" >&2
    echo "       $SDK_DIR" >&2
    echo "       The $TOOLS_PLAT tools package is a separate download - see the" >&2
    echo "       \"SDK packages\" section of README.md - and must be unpacked" >&2
    echo "       into tools/$TOOLS_PLAT/ before this host can build." >&2
    exit 1
fi

# The cross compiler lives in the tools package and build.py puts its bin/ on
# PATH itself (build.py:70,118). It unpacks cross_tool.zip when the unpacked
# directory is absent, so an unpacked bin/ is not the only acceptable state.
#
# The Linux package is the exception to that rule: it ships the toolchain as
# cross_tool.tar.bz2, and build.py only ever looks for .zip, so nothing would
# unpack it and the build would die at the first compile. Hence the extraction
# below. Leaving it packed is also the better resting state: the archive stores
# the exec bits (arm-none-eabi-gcc is rwxrwxrwx in it), which is exactly what a
# tools directory that has been copied or restored around loses - see the lzma
# note further down, where that same loss breaks the packaging step.
CROSS_TOOL_DIR="$SDK_DIR/tools/$TOOLS_PLAT/cross_tool"
CROSS_BIN="$CROSS_TOOL_DIR/gcc-arm-none-eabi/bin"
CROSS_ZIP="$SDK_DIR/tools/$TOOLS_PLAT/cross_tool.zip"
CROSS_BZ2="$SDK_DIR/tools/$TOOLS_PLAT/cross_tool.tar.bz2"
# Keyed on the bin directory rather than on cross_tool/ itself, so the ask is
# "is there a usable compiler", and a half-unpacked cross_tool/ - directory
# present, compiler not - is repaired by the extraction too.
if [ "$TOOLS_PLAT" = "linux" ] && [ ! -d "$CROSS_BIN" ] && [ -f "$CROSS_BZ2" ]; then
    echo " Cross    : unpacking cross_tool.tar.bz2 (this takes a moment)"
    if ! tar -xjf "$CROSS_BZ2" -C "$SDK_DIR/tools/$TOOLS_PLAT"; then
        echo "ERROR: could not unpack $CROSS_BZ2" >&2
        echo "       It is the only copy of the cross compiler in the Linux" >&2
        echo "       tools package, so nothing can be built without it. A" >&2
        echo "       truncated download is the usual cause - fetch the Linux" >&2
        echo "       tools package again and re-try." >&2
        exit 1
    fi
    if [ ! -d "$CROSS_BIN" ]; then
        echo "ERROR: $CROSS_BZ2 unpacked, but there is still no" >&2
        echo "       $CROSS_BIN" >&2
        echo "       The archive does not have the layout this script expects" >&2
        echo "       (cross_tool/gcc-arm-none-eabi/bin/)." >&2
        exit 1
    fi
    echo " Cross    : cross_tool/ unpacked from cross_tool.tar.bz2"
fi
if [ ! -d "$CROSS_BIN" ] && [ ! -f "$CROSS_ZIP" ]; then
    echo "ERROR: the cross toolchain is missing from the tools package:" >&2
    echo "       $CROSS_BIN" >&2
    echo "       Neither it nor cross_tool.zip (cross_tool.tar.bz2 on Linux)" >&2
    echo "       is there. build.py unpacks cross_tool.zip from" >&2
    echo "       tools/$TOOLS_PLAT/ when it has to, but it has nothing to" >&2
    echo "       unpack, so it would stop with a traceback." >&2
    echo "       Re-unpack the $TOOLS_PLAT tools package into tools/$TOOLS_PLAT/." >&2
    exit 1
fi

# Ninja. This one has no fallback: build.py hardcodes the generator
# (build.py:81-82 - it configures with "cmake -G Ninja" and then builds with
# "ninja -j <n>"), and the only ninja binary in the release is
# tools/win32/ninja.exe. On Linux cmake otherwise stops with "unable to find a
# build program corresponding to \"Ninja\"" - and build.py's own check for it
# is commented out (build.py:529), so nothing warns you first.
# Only the Linux host is resolved and checked here. On win32 the release itself
# is where ninja is supposed to come from (tools/win32/ninja.exe) and build.py
# puts that directory on PATH for the child processes, so there is nothing for
# this script to do.
NINJA_NOTE=""
if [ "$TOOLS_PLAT" = "linux" ]; then
    if ! command -v ninja >/dev/null 2>&1; then
        if [ -x "$SDK_DIR/tools/linux/ninja" ]; then
            # A Linux tools package may carry its own. build.py only appends
            # tools/<plat> to PATH (build.py:117), which is too late to matter,
            # so put it in front here.
            PATH="$SDK_DIR/tools/linux:$PATH"
            export PATH
            NINJA_NOTE=" Ninja    : $SDK_DIR/tools/linux/ninja"
        elif command -v ninja-build >/dev/null 2>&1; then
            # Debian and Ubuntu name the binary ninja-build in some releases,
            # and both cmake and build.py look for plain "ninja".
            NINJA_SHIM_DIR=$(mktemp -d "${TMPDIR:-/tmp}/simcom-ninja.XXXXXX" 2>/dev/null)
            if [ -n "$NINJA_SHIM_DIR" ]; then
                ln -s "$(command -v ninja-build)" "$NINJA_SHIM_DIR/ninja" 2>/dev/null
                PATH="$NINJA_SHIM_DIR:$PATH"
                export PATH
                NINJA_NOTE=" Ninja    : ninja -> $(command -v ninja-build) (this host calls it ninja-build)"
            fi
        fi
    fi
    if ! command -v ninja >/dev/null 2>&1; then
        echo "ERROR: \"ninja\" is not on PATH." >&2
        echo "       build.py builds with the Ninja generator - it configures with" >&2
        echo "       \"cmake -G Ninja\" and then runs \"ninja -j <n>\" - and the only" >&2
        echo "       ninja binary in the release is tools/win32/ninja.exe, so here" >&2
        echo "       cmake stops with:" >&2
        echo "         CMake was unable to find a build program corresponding to" >&2
        echo "         \"Ninja\".  CMAKE_MAKE_PROGRAM is not set." >&2
        echo "       Install it and re-run this script:" >&2
        echo "         sudo apt install ninja-build       # Debian / Ubuntu" >&2
        echo "         sudo dnf install ninja-build       # Fedora" >&2
        echo "         python3 -m pip install ninja       # no sudo; ships a binary" >&2
        echo "       (build.py:81-82 is also where to switch it to make - the comment" >&2
        echo "       there names the alternative - but the SDK is read-only here.)" >&2
        exit 1
    fi
    if [ -z "$NINJA_NOTE" ]; then
        NINJA_RESOLVED=$(command -v ninja 2>/dev/null)
        [ -n "$NINJA_RESOLVED" ] && NINJA_NOTE=" Ninja    : ninja -> $NINJA_RESOLVED"
    fi
    [ -n "$NINJA_NOTE" ] && echo "$NINJA_NOTE"

    # ---- Repair the tools package's own modes, and the lzma name. ----------
    # The loose binaries in the tools package have been seen to arrive at 0644,
    # and to lose their modes again whenever the directory is re-extracted or
    # restored from a backup - the packed forms (cross_tool/, unpacked above,
    # and the .tar.bz2s) keep theirs, which is what makes the difference easy
    # to miss. It is invisible until the tool is run, and the failure surfaces
    # far from the cause: the [ -x ] test below stops matching, so tools/linux
    # is never put ahead of PATH, the host's unrelated xz "lzma" wins, and the
    # build dies at the very last step. Repair it here, where these names are
    # resolved, instead of only describing it in a warning.
    for t in crc_set lzma_asr_lnx make_image.sh aboot/adownload aboot/arelease; do
        f="$SDK_DIR/tools/$TOOLS_PLAT/$t"
        if [ -f "$f" ] && [ ! -x "$f" ] && chmod +x "$f" 2>/dev/null; then
            echo " Repaired : chmod +x tools/$TOOLS_PLAT/$t"
        fi
    done
    # The Linux package ships the LZMA tool as lzma_asr_lnx, while toolchain.cmake
    # asks for the bare name "lzma" (configs/ASR/1903SR/toolchain.cmake:12), and
    # nothing in the SDK creates that link. Only a missing one is made - a real
    # lzma in tools/linux/ is somebody's deliberate choice and is left alone.
    if [ ! -e "$SDK_DIR/tools/$TOOLS_PLAT/lzma" ] \
       && [ -f "$SDK_DIR/tools/$TOOLS_PLAT/lzma_asr_lnx" ]; then
        if ln -sf lzma_asr_lnx "$SDK_DIR/tools/$TOOLS_PLAT/lzma"; then
            echo " Repaired : tools/$TOOLS_PLAT/lzma -> lzma_asr_lnx"
        fi
    fi

    # The last thing a build does is package, and that step shells out to two
    # more tools by bare name (CMakeLists.txt:167-169):
    #     lzma e <in> <out>      and      crc_set <in> <out>
    # Neither is a distribution tool, and the release ships win32 builds of both
    # (tools/win32/lzma.exe, tools/win32/crc_set.exe), so the Linux tools
    # package has to carry its own - and its own has to be the one that runs.
    # build.py only *appends* tools/linux to PATH (build.py:117), so a host
    # "lzma" wins, and Ubuntu's xz-utils really does install an unrelated one.
    PACK_SDK=""
    for t in crc_set lzma; do
        if [ -x "$SDK_DIR/tools/linux/$t" ]; then
            PACK_SDK="$PACK_SDK $t"
        elif ! command -v "$t" >/dev/null 2>&1; then
            echo " WARNING  : \"$t\" is neither in tools/linux/ nor on PATH."
            echo "            The packaging step calls it by name, so the build"
            echo "            will fail once it reaches the end."
        fi
    done
    if [ -n "$PACK_SDK" ]; then
        PATH="$SDK_DIR/tools/linux:$PATH"
        export PATH
        echo " Packaging:$PACK_SDK from tools/linux, ahead of PATH"
    fi
    if [ ! -x "$SDK_DIR/tools/linux/lzma" ] && command -v lzma >/dev/null 2>&1 \
       && lzma --version 2>&1 | grep -qi 'xz'; then
        echo " WARNING  : the \"lzma\" on PATH is xz-utils', but the SDK runs"
        echo "            \"lzma e <in> <out>\". xz's lzma has no \"e\" subcommand,"
        echo "            so packaging will fail with something like"
        echo "            \"e: No such file or directory\"."
    fi
fi

# ---- 1. Back up the SDK's files, once, so "restore" can undo everything. --
if [ ! -f "$SDK_APP_DIR/main.c.simcom" ]; then
    cp -f "$SDK_APP_DIR/main.c" "$SDK_APP_DIR/main.c.simcom"
    echo " [1/4] Backed up AL/APP/main.c          -> main.c.simcom"
fi
if [ ! -f "$SDK_APP_DIR/CMakeLists.txt.simcom" ]; then
    cp -f "$SDK_APP_DIR/CMakeLists.txt" "$SDK_APP_DIR/CMakeLists.txt.simcom"
    echo " [1/4] Backed up AL/APP/CMakeLists.txt  -> CMakeLists.txt.simcom"
fi
echo ' [1/4] SDK originals backed up (kept for "./build.sh restore").'

# ---- 2. Copy the customer code into the SDK. -----------------------------
# Wipe first, so files deleted here do not linger in the SDK.
rm -rf "$SDK_APP_DIR/customer_code"
mkdir -p "$SDK_APP_DIR/customer_code"
if ! cp -R "$APP_DIR/customer_code/." "$SDK_APP_DIR/customer_code/"; then
    echo "ERROR: failed to copy customer_code/ into the SDK." >&2
    exit 1
fi

cp -f "$APP_DIR/customer_code/main.c" "$SDK_APP_DIR/main.c"
echo " [2/4] Copied customer_code/ and main.c into AL/APP/."

# Register customer_code as a subdirectory of AL/APP, once.
if ! grep -qF 'add_subdirectory(customer_code)' "$SDK_APP_DIR/CMakeLists.txt"; then
    # Quoted here-doc delimiter: ${CMAKE_CURRENT_SOURCE_DIR} stays literal,
    # for CMake to expand, exactly as build.bat writes it.
    cat >> "$SDK_APP_DIR/CMakeLists.txt" <<'EOF'

# Appended by Customer_Application/build.sh
if (EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/customer_code/CMakeLists.txt")
    add_subdirectory(customer_code)
endif()
EOF
    echo " [2/4] Registered customer_code in AL/APP/CMakeLists.txt."
fi

# ---- 3. Build inside the SDK. --------------------------------------------
# NOTE: build.py always exits 0, even when ninja fails - it only prints
# ">>>>> build successed. <<<<<" or ">>>>> build fail. <<<<<". It also
# rewrites build_<module>.log from scratch on every run, so that marker in
# that file is the only reliable verdict on the build.
BUILD_ARGS=("${TARGET}_app")
if [ "$ACTION" = "rebuild" ]; then
    BUILD_ARGS+=("-c")
fi

SDK_LOG="$SDK_DIR/output/$TARGET/build_$TARGET.log"

echo " [3/4] Running: $PYTHON build.py ${BUILD_ARGS[*]}"
echo
pushd "$SDK_DIR" >/dev/null || { echo "ERROR: cannot enter $SDK_DIR" >&2; exit 1; }
"$PYTHON" build.py "${BUILD_ARGS[@]}"
popd >/dev/null
echo

BUILD_OK=""
if [ -f "$SDK_LOG" ] && grep -qF '>>>>> build successed. <<<<<' "$SDK_LOG"; then
    BUILD_OK="1"
fi

# ---- 4. Copy the results back into this folder. --------------------------
# The log is always copied. The firmware is only copied on success, so a
# failed build never leaves stale binaries looking like fresh output.
mkdir -p "$OUT_DIR"

[ -f "$SDK_LOG" ] && cp -f "$SDK_LOG" "$OUT_DIR/build_$TARGET.log"
[ -f "$SDK_DIR/output/$TARGET/simcom_build.log" ] && \
    cp -f "$SDK_DIR/output/$TARGET/simcom_build.log" "$OUT_DIR/simcom_build.log"

if [ -n "$BUILD_OK" ]; then
    # Named explicitly: a "customer_app.*" wildcard would miss the _crc / _lzma
    # variants, which use an underscore rather than a dot.
    for f in customer_app.elf \
             customer_app.elf.map \
             customer_app.elf.map.json \
             customer_app.bin \
             customer_app_crc.bin \
             customer_app_lzma.bin \
             customer_app_lzma_crc.bin; do
        [ -f "$APP_OUT/$f" ] && cp -f "$APP_OUT/$f" "$OUT_DIR/$f"
    done

    # The flash package is produced automatically by the APP build; there is no
    # separate "package" target in this SDK (build.py's _package branch is
    # commented out, and packaging is a POST_BUILD step in
    # configs/ASR/1903SR/app_extern_build_flow.cmake).
    if [ -d "$SDK_DIR/output/package/$TARGET" ]; then
        mkdir -p "$OUT_DIR/package"
        cp -R "$SDK_DIR/output/package/$TARGET" "$OUT_DIR/package/"
    fi
fi
echo " [4/4] Output folder: $OUT_DIR"


# ============================================================================
#  Result
# ============================================================================
if [ -z "$BUILD_OK" ]; then
    echo
    echo "============================================================"
    echo " BUILD FAILED  -  $TARGET"
    echo "============================================================"
    echo " Log           : $OUT_DIR/build_$TARGET.log"
    echo " The output folder still holds the previous build, if any."
    echo
    exit 1
fi

echo
echo "============================================================"
echo " BUILD SUCCEEDED  -  $TARGET"
echo "============================================================"
echo " Firmware      : $OUT_DIR/customer_app.bin"
echo " ELF with debug: $OUT_DIR/customer_app.elf"
echo " Flash package : $OUT_DIR/package/$TARGET/"
echo " Build log     : $OUT_DIR/build_$TARGET.log"
echo
exit 0
