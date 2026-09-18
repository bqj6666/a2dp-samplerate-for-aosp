#!/system/bin/sh
# A2DP Auto SampleRate - 卸载清理
#
# 1) 尝试移除 SUSFS 持久化配置里的对应条目（只影响 JSON；live 注册需重启才清除）
# 2) 摘掉 bind mount（若有）
# 3) 删除投递目录
#
# 注意：SUSFS 的 live open_redirect 只能靠重启彻底清除，故建议卸载后重启一次。

MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.
LOG=/data/adb/a2dp_samplerate.log
log() { echo "$(date) [uninstall] $*" >> "$LOG"; }

SUSFS=/data/adb/ksu/bin/ksu_susfs
PUBDIR=/data/vendor/audio/a2dp-sr

log "==== uninstall ===="

for T in \
  /vendor/etc/audio/audio_module_config_primary.xml \
  /odm/etc/audio/audio_module_config_primary.xml \
  /vendor/etc/audio/audio_module_config.xml \
  /odm/etc/audio/audio_module_config.xml \
  /odm/etc/audio_policy_configuration.xml \
  /vendor/etc/audio_policy_configuration.xml ; do
  [ -e "$T" ] || continue
  # 持久化配置
  [ -x "$SUSFS" ] && "$SUSFS" config open_redirect remove "$T" >>"$LOG" 2>&1
  # bind mount 残留
  i=0
  while grep -q " $T " /proc/1/mountinfo 2>/dev/null; do
    nsenter -t 1 -m -- /system/bin/umount "$T" >>"$LOG" 2>&1 || break
    i=$((i+1)); [ $i -gt 8 ] && break
  done
  [ $i -gt 0 ] && log "umounted $T x$i"
done

[ -d "$PUBDIR" ] && { rm -rf "$PUBDIR" && log "removed $PUBDIR"; }

setprop ctl.restart audioserver 2>/dev/null
log "done (建议重启设备以彻底清除 live open_redirect)"
exit 0
