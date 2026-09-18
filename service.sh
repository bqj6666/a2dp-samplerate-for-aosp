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
