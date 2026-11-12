#!/system/bin/sh
# A2DP Auto SampleRate - Stage 2 (late service)
#
# 开机后核验并幂等补强。判据（与命名风格无关）：
#   primary/default 模块里的 A2DP 输出声明数 应为 0
#   bluetooth 模块里的 A2DP 输出声明数 应 > 0
# 两者都满足 = 生效；否则视为未生效，重新投递一次并重启 audioserver。

MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.
LOG=/data/adb/a2dp_samplerate.log
log() { echo "$(date) [service] $*" >> "$LOG"; }

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
sleep 5
log "==== service ===="

# ---- offload 与 patch 必须同步（否则连接耳机时报 APM error=1，声音走扬声器）----
# post-fs-data 阶段设好了这里就是 no-op；只有 prop 没落盘（极早期 /data 未就绪）
# 才补设，并重启一次蓝牙栈让 stack 重新读 prop。
if [ "$(getprop ro.bluetooth.a2dp_offload.supported)" = "true" ] \
   && [ "$(getprop persist.bluetooth.a2dp_offload.disabled)" != "true" ]; then
  setprop persist.bluetooth.a2dp_offload.disabled true
  log "offload disabled(late) -> $(getprop persist.bluetooth.a2dp_offload.disabled)"
  cmd bluetooth_manager disable 2>/dev/null
  sleep 2
  cmd bluetooth_manager enable 2>/dev/null
  cmd bluetooth_manager wait-for-state:STATE_ON 2>/dev/null
  log "bt stack restarted to apply offload=off"
fi

A2DP_RE='"bt_a2dp_out"|"bt_a2dp_headphones"|"bt_a2dp_speaker"|"BT A2DP Out"|"BT A2DP Headphones"|"BT A2DP Speaker"'

count_in() {   # $1 = 模块名正则
  dumpsys media.audio_policy 2>/dev/null | awk -v want="$1" '
    /^  [0-9]+\. Handle: [0-9]+; "/ { inmod = ($0 ~ want) }
    inmod && /"bt_a2dp_out"|"bt_a2dp_headphones"|"bt_a2dp_speaker"|"BT A2DP Out"|"BT A2DP Headphones"|"BT A2DP Speaker"/ { n++ }
    END { print n+0 }'
}

prim=$(count_in '"(primary|default)"')
bt=$(count_in '"bluetooth"')
log "primary/default a2dp=$prim  bluetooth a2dp=$bt"

if [ "$prim" = "0" ] && [ "$bt" != "0" ]; then
  log "OK: 生效（A2DP 已由 bluetooth 模块承载）"
  exit 0
fi

# 未生效 -> 检查是否被投递过；若配置本来就无需修改则不算失败
log "MISS: 判据未通过，尝试补强"
if [ -f "$MODDIR/post-fs-data.sh" ]; then
  sh "$MODDIR/post-fs-data.sh" >>"$LOG" 2>&1
  log "已重跑 post-fs-data.sh"
fi
setprop ctl.restart audioserver 2>/dev/null
sleep 10
prim=$(count_in '"(primary|default)"')
bt=$(count_in '"bluetooth"')
log "after retry: primary/default a2dp=$prim  bluetooth a2dp=$bt"
if [ "$prim" = "0" ] && [ "$bt" != "0" ]; then
  log "OK: 补强后生效"
else
  log "WARN: 仍未通过判据。若音频异常，可创建 $MODDIR/disable 后重启以停用本模块。"
fi
exit 0
