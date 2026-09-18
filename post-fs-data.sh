#!/system/bin/sh
# A2DP Auto SampleRate - Stage 1 (post-fs-data)
#
# 作用：让蓝牙 A2DP 输出采样率跟随音源。
#
# 原理：多数 Qualcomm BSP 把 A2DP 输出设备（bt_a2dp_out / BT A2DP Out 等）声明在
# primary/default 音频模块里，这些模块的输出固定 48000，于是任何 44.1k 音源都要先被
# 重采样到 48000；AOSP 的原意是让 A2DP 走 HAL 运行时注册的独立 bluetooth 模块
# （a2dp output = [dynamic format][dynamic channels][dynamic rates]）。
# 本模块读设备自带的配置，删掉非 bluetooth 模块里的 A2DP 输出声明（devicePort + route），
# 使 A2DP 回落到 bluetooth 模块的动态输出。
#
# 投递：优先 SUSFS open_redirect（kernel 层，无挂载行）；不支持时回退 bind mount。
#
# ---- 安全阀 ----
# A. 仅当 /vendor/etc/vintf 里声明了 AIDL 蓝牙音频模块（IModule/bluetooth 或
#    IBluetoothAudioProviderFactory）时才动手。老 HIDL / 单文件 policy 布局的设备
#    （A2DP 只在 primary 里有声明、没有独立 bluetooth 模块）直接跳过，绝不改动。
# B. 补丁产出与原文件逐字节相同则跳过（说明已是 AOSP 布局，无需处理）。
# C. 两种投递方式都失败时保持原厂状态。
#
# ---- 踩过的坑 ----
# 1) 必须连 devicePort 一起删：只删 route 会让 A2DP 失去输出（实测无声）。
# 2) 不要误删 bluetooth 模块自己的声明 —— 本模块按当前 <module name> 判断，只改
#    非 bluetooth 模块（AOSP 官方配置里 A2DP 就在 bluetooth 模块，删了反而坏）。
# 3) bind mount 必须 nsenter 到 init 的 mount namespace（pid 1），否则 audio HAL
#    在另一个 namespace 里看不到挂载。
# 4) 投递目录必须是 audioserver 自己能读的：/data/vendor/audio 是 audio:audio 0770。
# 5) SUSFS 持久化配置在 boot 极早期应用，那时 /data/vendor 还没就绪，所以这里用
#    live 注册（post-fs-data 阶段 /data 已可用，且早于 audio HAL 启动）。
# 6) 不要用 shell 身份去验证投递文件内容：shell 的 SELinux 域读不到
#    vendor_audio_data_file，会误判成失败。以 service.sh 的行为判据为准。

MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.
LOG=/data/adb/a2dp_samplerate.log
log() { echo "$(date) [post-fs-data] $*" >> "$LOG"; }

BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=$(command -v busybox)
SUSFS=/data/adb/ksu/bin/ksu_susfs

PATCHER=$MODDIR/tools/patch.awk
PUBDIR=/data/vendor/audio/a2dp-sr
PUB=$PUBDIR/audio_module_config_primary.xml
UID_SCHEME=0   # 0 = 非 app 进程（uid < 10000），覆盖 audio HAL / audioserver

log "==== post-fs-data ===="

[ -f "$PATCHER" ] || { log "SKIP: 缺少 $PATCHER"; exit 0; }

# ---- A) 设备预检 ----
if ! grep -rqE 'IModule/bluetooth|IBluetoothAudioProviderFactory' \
        /vendor/etc/vintf /odm/etc/vintf 2>/dev/null; then
  log "SKIP: 未检测到 AIDL 蓝牙音频模块（应为老 HIDL/单文件布局）。不做任何改动。"
  exit 0
fi

# ---- 定位音频策略配置 ----
TARGET=""
for p in \
  /vendor/etc/audio/audio_module_config_primary.xml \
  /odm/etc/audio/audio_module_config_primary.xml \
  /vendor/etc/audio/audio_module_config.xml \
  /odm/etc/audio/audio_module_config.xml \
  /odm/etc/audio_policy_configuration.xml \
  /vendor/etc/audio_policy_configuration.xml ; do
  [ -f "$p" ] && { TARGET=$p; break; }
done
[ -n "$TARGET" ] || { log "SKIP: 未找到音频策略配置"; exit 0; }

# ---- B) 生成补丁并比对 ----
mkdir -p "$PUBDIR" 2>>"$LOG"
TMP=$PUBDIR/.patched.$$
awk -f "$PATCHER" "$TARGET" > "$TMP" 2>>"$LOG"
if [ ! -s "$TMP" ]; then
  log "ERR: 补丁产出为空，放弃"; rm -f "$TMP"; exit 0
fi
if cmp -s "$TARGET" "$TMP"; then
  log "SKIP: $TARGET 已是 AOSP 布局（补丁无差异）"
  rm -f "$TMP"; exit 0
fi

# ---- 发布（同目录 mv，原子）----
chown audio:audio "$PUBDIR" 2>>"$LOG"
chmod 0755 "$PUBDIR"
chown audio:audio "$TMP" 2>>"$LOG"
chmod 0644 "$TMP"
mv -f "$TMP" "$PUB" || { log "ERR: 发布失败"; exit 0; }

# ---- C) 选择投递方式 ----
METHOD=""
if [ -x "$SUSFS" ] && "$SUSFS" add_open_redirect "$TARGET" "$PUB" "$UID_SCHEME" >/dev/null 2>&1; then
  chcon u:object_r:vendor_audio_data_file:s0 "$PUB" 2>>"$LOG"
  METHOD=open_redirect
else
  chcon u:object_r:vendor_configs_file:s0 "$PUB" 2>>"$LOG"
  if nsenter -t 1 -m -- /system/bin/mount -o bind "$PUB" "$TARGET" 2>>"$LOG"; then
    METHOD=bind
  fi
fi

[ -n "$METHOD" ] || { log "ERR: open_redirect 与 bind 均失败，保持原厂状态"; exit 0; }
log "OK: method=$METHOD target=$TARGET pub=$(wc -c < "$PUB") bytes"
exit 0
