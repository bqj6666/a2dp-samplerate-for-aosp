#!/system/bin/sh
# patch.awk 自测：全部使用合成 XML，不含任何厂商文件。
# 用法：sh tools/test-patch.sh
DIR=${0%/*}
[ "$DIR" = "$0" ] && DIR=.
AWK=$DIR/patch.awk
TMP=$(mktemp -d 2>/dev/null || echo /tmp/a2dptest)
mkdir -p "$TMP"
fail=0
ck() { if [ "$2" = "$3" ]; then echo "  ok   $1 ($2)"; else echo "  FAIL $1: 实际=$2 期望=$3"; fail=1; fi; }

# ---- 用例 1：BSP 风格 —— A2DP 在 default 模块，应被删除 ----
cat > "$TMP/bsp.xml" <<'XML'
<modules>
<module name="default">
    <devicePort tagName="speaker" deviceType="OUT_DEVICE">
        <profile samplingRates="48000" />
    </devicePort>
    <devicePort tagName="bt_a2dp_out" deviceType="OUT_DEVICE" role="sink">
        <profile samplingRates="48000" />
    </devicePort>
    <devicePort tagName="bt_a2dp_headphones" deviceType="OUT_HEADPHONE" role="sink">
        <profile samplingRates="48000" />
    </devicePort>
    <devicePort tagName="bt_a2dp_speaker" deviceType="OUT_SPEAKER" role="sink">
        <profile samplingRates="48000" />
    </devicePort>
    <devicePort tagName="bt_a2dp_mic" deviceType="IN_DEVICE" role="source">
        <profile samplingRates="48000" />
    </devicePort>
    <routes>
        <route type="mix" sink="speaker" sources="low_latency_out" />
        <route type="mix" sink="bt_a2dp_out" sources="low_latency_out,deep_buffer_out" />
        <route type="mix" sink="bt_a2dp_headphones" sources="low_latency_out" />
        <route type="mix" sink="bt_a2dp_speaker" sources="low_latency_out" />
        <route type="mix" sink="primary_in" sources="bt_a2dp_mic" />
    </routes>
</module>
</modules>
XML
awk -f "$AWK" "$TMP/bsp.xml" > "$TMP/bsp.out"
ck "BSP: A2DP 输出声明已删" "$(grep -c 'bt_a2dp_out\|bt_a2dp_headphones\|bt_a2dp_speaker' "$TMP/bsp.out")" "0"
ck "BSP: bt_a2dp_mic 保留" "$(grep -c 'bt_a2dp_mic' "$TMP/bsp.out")" "2"
ck "BSP: speaker 保留" "$(grep -c 'tagName="speaker"' "$TMP/bsp.out")" "1"

# ---- 用例 2：AOSP 风格 —— A2DP 在 bluetooth 模块，应零改动 ----
cat > "$TMP/aosp.xml" <<'XML'
<modules>
<module name="bluetooth">
    <devicePort tagName="BT A2DP Out" type="AUDIO_DEVICE_OUT_BLUETOOTH_A2DP" role="sink">
        <profile samplingRates="44100,48000,88200,96000" />
    </devicePort>
    <devicePort tagName="BT A2DP Headphones" type="AUDIO_DEVICE_OUT_BLUETOOTH_A2DP_HEADPHONES" role="sink">
        <profile samplingRates="44100,48000,88200,96000" />
    </devicePort>
    <routes>
        <route type="mix" sink="BT A2DP Out" sources="a2dp output" />
        <route type="mix" sink="BT A2DP Headphones" sources="a2dp output" />
    </routes>
</module>
</modules>
XML
awk -f "$AWK" "$TMP/aosp.xml" > "$TMP/aosp.out"
if cmp -s "$TMP/aosp.xml" "$TMP/aosp.out"; then echo "  ok   AOSP: bluetooth 模块零改动"; else echo "  FAIL AOSP: 被改动了"; fail=1; fi

# ---- 用例 3：幂等性（对已打过补丁的文件再打一次，结果不变）----
awk -f "$AWK" "$TMP/bsp.out" > "$TMP/bsp.out2"
if cmp -s "$TMP/bsp.out" "$TMP/bsp.out2"; then echo "  ok   幂等性"; else echo "  FAIL 幂等性"; fail=1; fi

rm -rf "$TMP"
[ $fail = 0 ] && echo "全部通过" || echo "有失败项"
exit $fail
