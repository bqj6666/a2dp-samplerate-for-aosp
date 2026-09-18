# a2dp-samplerate: 删除非 bluetooth 模块里的 A2DP 输出声明
# 仅当 A2DP 声明位于 primary/default 等模块时才删；bluetooth 模块保持原样
BEGIN { mod = ""; skip = 0 }
match($0, /<module name="[^"]+"/) {
  mod = substr($0, RSTART + 14, RLENGTH - 15)
}
skip { if ($0 ~ /<\/devicePort>/) skip = 0; next }
mod != "bluetooth" && /tagName="(bt_a2dp_out|bt_a2dp_headphones|bt_a2dp_speaker|BT A2DP Out|BT A2DP Headphones|BT A2DP Speaker)"/ {
  skip = 1
  if ($0 ~ /\/>[      ]*$/) skip = 0
  next
}
mod != "bluetooth" && /sink="(bt_a2dp_out|bt_a2dp_headphones|bt_a2dp_speaker|BT A2DP Out|BT A2DP Headphones|BT A2DP Speaker)"/ { next }
{ print }
