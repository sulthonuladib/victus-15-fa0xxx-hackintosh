#!/bin/bash
# xegfx-stage4-trace.sh - run stage 4 with the NVRAM breadcrumb trace enabled.
#
#   sudo bash /Volumes/macUtility/scripts/xegfx/xegfx-stage4-trace.sh --yes
#
# It keeps the default XeGfx environment, adds xegfx.nvram_trace=1, raises the
# stage watchdog to 180 s, and starts stage 4. Stage 4 can panic; the EFI is
# unchanged and a power cycle recovers. After the next boot, read the trace:
#
#   nvram -p | grep xegfx-step
#   sudo bash /Volumes/macUtility/scripts/xegfx/xegfx-collect-panic.sh
#
# The collector includes the trace in its environment capture.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ENV_DEFAULT='compat.linuxkpi.i915_disable_display=1 compat.linuxkpi.i915_enable_guc=3 xegfx.nvram_trace=1'
ENV_VAL=${XEGFX_ENV:-$ENV_DEFAULT}
WDOG=${XEGFX_WDOG:-180}

say() { printf '%s\n' "$*"; }
die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "run this on macOS."
[ "$(id -u)" -eq 0 ] || exec sudo bash "$0" "$@"
[ "${1:-}" = "--yes" ] || die "stage 4 can panic. Re-run with --yes when you are ready."
[ -d /Library/Extensions/XeGfx.kext ] || die "XeGfx.kext is not installed; run xegfx-install.sh first."

grep -q 'org.watchthelight.XeGfx' <(kmutil showloaded 2>/dev/null) \
  || kmutil load -b org.watchthelight.XeGfx || die "could not load org.watchthelight.XeGfx"

sysctl debug.xegfx_env >/dev/null 2>&1 || die "debug.xegfx_env is not registered; is XeGfx loaded?"
sysctl debug.xegfx_wdog >/dev/null 2>&1 || die "debug.xegfx_wdog is not registered; is XeGfx loaded?"

say "env:  $ENV_VAL"
say "watchdog: ${WDOG}s"
sysctl -w "debug.xegfx_env=$ENV_VAL" || die "could not set debug.xegfx_env"
sysctl -w "debug.xegfx_wdog=$WDOG" || die "could not set debug.xegfx_wdog"

say ""
say "Starting stage 4 with the NVRAM trace. If it panics, power-cycle, boot normally,"
say "then run:"
say "  nvram -p | grep xegfx-step"
say "  sudo bash $HERE/xegfx-collect-panic.sh"
say ""
exec bash "$HERE/xegfx-probe.sh" --stage 4 --yes
