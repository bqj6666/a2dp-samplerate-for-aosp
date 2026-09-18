#!/bin/sh
# 构建可刷写模块 zip：sh tools/build-zip.sh [输出目录]
#
# 生成的 zip 符合 Magisk / KernelSU 模块格式：
#   META-INF/com/google/android/update-binary   （标准安装入口）
#   META-INF/com/google/android/updater-script
#   module.prop / *.sh / tools/patch.awk / tools/test-patch.sh
#
# 说明：update-binary 内联在下方。请勿随意改写 —— 该内容已在实际设备上
# 验证可被 KernelSU / Magisk 正确安装。改动后必须重新验证。

set -e
DIR=${0%/*}
[ "$DIR" = "$0" ] && DIR=.
ROOT=$(cd "$DIR/.." && pwd)
OUTDIR=${1:-$ROOT/dist}
VERSION=$(grep -m1 '^version=' "$ROOT/module.prop" | cut -d= -f2)
NAME="a2dp_samplerate-${VERSION}.zip"

mkdir -p "$OUTDIR"

python3 - "$ROOT" "$OUTDIR/$NAME" <<'PY'
import os, sys, zipfile

root, out = sys.argv[1], sys.argv[2]

INSTALLER = """#!/sbin/sh

#################
# Initialization
#################

umask 022

# echo before loading util_functions
ui_print() { echo "$1"; }

require_new_magisk() {
  ui_print "*******************************"
  ui_print " Please install Magisk v20.4+! "
  ui_print "*******************************"
  exit 1
}

#########################
# Load util_functions.sh
#########################

OUTFD=$2
ZIPFILE=$3

mount /data 2>/dev/null

[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ $MAGISK_VER_CODE -lt 20400 ] && require_new_magisk

install_module
exit 0
"""

# 模块 zip 内需要包含的文件（相对路径, 权限）
FILES = [
    ("module.prop",          0o644),
    ("post-fs-data.sh",      0o755),
    ("service.sh",           0o755),
    ("uninstall.sh",         0o755),
    ("tools/patch.awk",      0o644),
    ("tools/test-patch.sh",  0o755),
]

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name, content, mode in (
        ("META-INF/com/google/android/update-binary", INSTALLER, 0o755),
        ("META-INF/com/google/android/updater-script", "#MAGISK\n", 0o644),
    ):
        zi = zipfile.ZipInfo(name)
        zi.external_attr = mode << 16
        z.writestr(zi, content)
    for rel, mode in FILES:
        zi = zipfile.ZipInfo(rel)
        zi.external_attr = mode << 16
        z.writestr(zi, open(os.path.join(root, rel), "rb").read())

print("built:", out, os.path.getsize(out), "bytes")
PY
