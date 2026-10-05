#!/usr/bin/env bash
# Regression test: swap-flush must drain DISK swap only and never `swapoff` zram.
#
# The original flush ran `swapoff -av`, which also disabled zram — decompressing
# every zram page back into RAM even though the script's own safety math
# excludes zram. On hosts with full zram that swapoff sat in D state for 5-10+
# minutes every 30 minutes with memory PSI spiking to ~40%.
#
# Runs the real script (standalone copy AND the copy embedded in
# install-swap-flush.sh) with stub swapon/swapoff/logger/systemctl on PATH and
# thresholds forced so the flush branch executes. No real swap is touched.
#
# Usage: bash tests/test-swap-flush.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t swap-flush-test)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/swapon" <<'EOF'
#!/usr/bin/env bash
echo "swapon $*" >> "$CALLS"
case "$*" in
  *--show=NAME,USED*) printf '/dev/zram0 30000000000\n/data/swapfile 9000000000\n/dev/nvme0n1p3 5000000000\n' ;;
  *--show=NAME,PRIO*) printf '/dev/zram0  100\n/data/swapfile 10\n/dev/nvme0n1p3 -2\n' ;;
  *--show=NAME*)      printf '/dev/zram0\n/data/swapfile\n/dev/nvme0n1p3\n' ;;
esac
EOF
cat > "$WORK/bin/swapoff" <<'EOF'
#!/usr/bin/env bash
echo "swapoff $*" >> "$CALLS"
EOF
cat > "$WORK/bin/logger" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
EOF
cat > "$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$CALLS"
exit 1
EOF
chmod +x "$WORK/bin/"*

# Extract the copy the installer writes to /usr/local/bin/swap-flush.
awk '/^read -r -d .. SWAP_FLUSH_SCRIPT <<.SCRIPT_EOF./{on=1; next} /^SCRIPT_EOF$/{on=0} on' \
  "$ROOT/install-swap-flush.sh" > "$WORK/swap-flush.installer"

fail=0
check() { # name, file
  local name="$1" script="$2" calls="$WORK/calls.$1"
  : > "$calls"
  CALLS="$calls" PATH="$WORK/bin:$PATH" \
    MIN_DISK_SWAP_GB=0 MEM_SAFETY_FACTOR=0 MAX_MEM_PRESSURE=100 MAX_LOAD_RATIO=100000 \
    bash "$script" > "$WORK/out.$name" 2>&1 || { echo "FAIL[$name]: script exited nonzero"; cat "$WORK/out.$name"; fail=1; return; }
  grep -q '^flushing:' "$WORK/out.$name" || { echo "FAIL[$name]: flush branch not reached (positive control)"; cat "$WORK/out.$name"; fail=1; return; }
  local expect_present=(
    "swapoff -v /data/swapfile"
    "swapoff -v /dev/nvme0n1p3"
    "swapon -v -p 10 /data/swapfile"
    "swapon -v /dev/nvme0n1p3"
  )
  for line in "${expect_present[@]}"; do
    grep -qxF -- "$line" "$calls" || { echo "FAIL[$name]: missing call: $line"; fail=1; }
  done
  if grep -E '^swapoff .*(zram|-a)' "$calls"; then echo "FAIL[$name]: swapoff touched zram or used -a"; fail=1; fi
  if grep -E '^swapon (-a|-av)( |$)' "$calls"; then echo "FAIL[$name]: blanket swapon -a"; fail=1; fi
  if [ "$fail" = 0 ]; then echo "ok[$name]: disk swap drained per device, zram untouched, priorities restored"; fi
}

check standalone "$ROOT/swap-flush"
check installer "$WORK/swap-flush.installer"
if ! diff -q <(sed -e '$a\' "$ROOT/swap-flush") <(sed -e '$a\' "$WORK/swap-flush.installer") > /dev/null; then
  echo "FAIL: swap-flush and the copy embedded in install-swap-flush.sh differ"
  diff <(sed -e '$a\' "$ROOT/swap-flush") <(sed -e '$a\' "$WORK/swap-flush.installer") | head -20
  fail=1
fi
exit "$fail"
