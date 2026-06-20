#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║      🍎  mac-check  –  Pre-Purchase Inspection Script       ║
# ║                                                              ║
# ║  Checks battery, MDM/DEP enrollment, Activation Lock,       ║
# ║  security settings, storage health and more before          ║
# ║  buying a used Mac.                                          ║
# ║                                                              ║
# ║  One-liner:                                                  ║
# ║    curl -fsSL https://raw.githubusercontent.com/            ║
# ║      <YOU>/mac-check/main/mac-check.sh | bash               ║
# ╚══════════════════════════════════════════════════════════════╝

[[ "$(uname -s)" == "Darwin" ]] || { echo "Requires macOS." >&2; exit 1; }

# ── Colours (disabled when output is piped / not a TTY) ────────
if [[ -t 1 ]]; then
  R=$'\033[0;31m' Y=$'\033[0;33m' G=$'\033[0;32m'
  B=$'\033[0;34m' C=$'\033[0;36m' D=$'\033[2m'
  BOLD=$'\033[1m' NC=$'\033[0m'
else
  R='' Y='' G='' B='' C='' D='' BOLD='' NC=''
fi

ISSUES=0; WARNINGS=0

pass() { printf "  ${G}✔${NC}  %b\n"    "$1"; }
warn() { printf "  ${Y}⚠${NC}  %b\n"    "$1"; WARNINGS=$((WARNINGS+1)); }
fail() { printf "  ${R}✘${NC}  %b\n"    "$1"; ISSUES=$((ISSUES+1)); }
info() { printf "  ${B}·${NC}  %b\n"    "$1"; }
note() { printf "      ${D}↳ %s${NC}\n" "$1"; }
sep()  { printf '%56s\n' '' | tr ' ' '─'; }
section() { printf "\n${BOLD}${B}▸ %s${NC}\n" "$1"; sep; }

# ── Header ──────────────────────────────────────────────────────
printf "\n${BOLD}${B}"
printf '╔══════════════════════════════════════════════════════════╗\n'
printf '║    🍎  mac-check  –  Pre-Purchase Inspection Report      ║\n'
printf '╚══════════════════════════════════════════════════════════╝\n'
printf "${NC}  ${D}%s${NC}\n" "$(date '+%a %d %b %Y  %H:%M')"

# ════════════════════════════════════════════════════════════════
# 1 · SYSTEM OVERVIEW
# ════════════════════════════════════════════════════════════════
section "1 · System Overview"

HW=$(system_profiler SPHardwareDataType 2>/dev/null)
gHW() { printf '%s' "$HW" | awk -F':[[:space:]]+' "/$1/{print \$2;exit}"; }

MODEL=$(    gHW 'Model Name')
MODEL_ID=$( gHW 'Model Identifier')
SERIAL=$(   gHW 'Serial Number \(system\)')
CHIP=$(     gHW 'Chip')
CPU_NAME=$( gHW 'Processor Name')
RAM=$(      gHW 'Memory')
CORES=$(    gHW 'Total Number of Cores')

ARCH="${CHIP:-${CPU_NAME:-Unknown}}"
OS_VER=$(  sw_vers -productVersion 2>/dev/null || echo '?')
OS_BUILD=$(sw_vers -buildVersion   2>/dev/null || echo '')
OS_NAME=$( sw_vers -productName    2>/dev/null || echo 'macOS')

info "${BOLD}Model:${NC}   $MODEL ($MODEL_ID)"
info "${BOLD}Chip:${NC}    $ARCH${CORES:+  ·  $CORES cores}"
info "${BOLD}RAM:${NC}     $RAM"
info "${BOLD}Serial:${NC}  ${SERIAL:-(unavailable)}"
info "${BOLD}macOS:${NC}   $OS_NAME $OS_VER${OS_BUILD:+ (build $OS_BUILD)}"

# ════════════════════════════════════════════════════════════════
# 2 · BATTERY HEALTH
# ════════════════════════════════════════════════════════════════
section "2 · Battery Health"

PWR=$(system_profiler SPPowerDataType 2>/dev/null)
gPWR() { printf '%s' "$PWR" | awk -F':[[:space:]]+' "/$1/{print \$2;exit}" | tr -d '[:space:]%'; }

CYCLES=$( gPWR 'Cycle Count')
COND=$(   gPWR 'Condition')
MAX_CAP=$(gPWR 'Maximum Capacity')
CHARGE=$( gPWR 'State of Charge \(%\)')
AC=$(      printf '%s' "$PWR" | awk -F':[[:space:]]+' '/Connected/{print $2;exit}' | tr -d '[:space:]')

if [[ "$CYCLES" =~ ^[0-9]+$ ]]; then
  if   (( CYCLES < 200 )); then pass "Battery Cycles: ${BOLD}$CYCLES${NC}  ${G}(excellent – barely used)${NC}"
  elif (( CYCLES < 500 )); then pass "Battery Cycles: ${BOLD}$CYCLES${NC}  ${G}(good)${NC}"
  elif (( CYCLES < 800 )); then warn "Battery Cycles: ${BOLD}$CYCLES${NC}  ${Y}(moderate – visible wear)${NC}"
  else                          fail "Battery Cycles: ${BOLD}$CYCLES${NC}  ${R}(high – replacement likely needed soon)${NC}"
  fi
  note "Apple rates most MacBook batteries for 1 000 cycles before reaching ~80 % capacity"
else
  info "Battery Cycles: not available"
fi

if [[ -n "$COND" ]]; then
  [[ "$COND" == "Normal" ]] \
    && pass "Condition:      ${G}Normal${NC}" \
    || fail "Condition:      ${R}$COND${NC}  — service flagged by macOS"
fi

if [[ "$MAX_CAP" =~ ^[0-9]+$ ]]; then
  if   (( MAX_CAP >= 85 )); then pass "Max Capacity:   ${BOLD}${MAX_CAP}%${NC}  ${G}(healthy)${NC}"
  elif (( MAX_CAP >= 70 )); then warn "Max Capacity:   ${BOLD}${MAX_CAP}%${NC}  ${Y}(degraded – factor in replacement cost)${NC}"
  else                          fail "Max Capacity:   ${BOLD}${MAX_CAP}%${NC}  ${R}(poor – battery replacement needed)${NC}"
  fi
fi

[[ "$CHARGE" =~ ^[0-9]+$ ]] && info "Current Charge: ${CHARGE}%${AC:+  (power adapter: $AC)}"

# ════════════════════════════════════════════════════════════════
# 3 · MDM & ENTERPRISE ENROLLMENT   ← most critical check
# ════════════════════════════════════════════════════════════════
section "3 · MDM & Enterprise Enrollment  ${D}← most critical check${NC}"

ENROLL=$(profiles status -type enrollment 2>/dev/null || echo '__error__')

if [[ "$ENROLL" == '__error__' ]]; then
  warn "Cannot read enrollment status  ${D}(run: sudo bash mac-check.sh for full results)${NC}"
else
  # DEP / Apple Business Manager
  if printf '%s' "$ENROLL" | grep -qi 'Enrolled via DEP: Yes'; then
    fail "DEP / Apple Business Manager: ${BOLD}${R}Enrolled${NC}"
    note "Even after a full erase, this Mac will auto-re-enroll in the org's MDM"
    note "Do not buy unless the seller explicitly removes it from ABM/ASM"
  else
    pass "DEP / Apple Business Manager: Not enrolled"
  fi

  # MDM
  if printf '%s' "$ENROLL" | grep -qi 'MDM enrollment: Yes'; then
    MDM_SRV=$(printf '%s' "$ENROLL" | awk -F':[[:space:]]+' '/MDM server/{print $2;exit}')
    fail "MDM: ${BOLD}${R}Enrolled${NC}  — device is actively managed by an organisation"
    [[ -n "$MDM_SRV" ]] && note "Server: $MDM_SRV"
    note "The organisation can remotely wipe, lock, or restrict this device"
  else
    pass "MDM: Not enrolled"
  fi
fi

# Configuration profiles
PROF=$(profiles list 2>/dev/null || echo '__error__')
if [[ "$PROF" == '__error__' ]]; then
  info "Config profiles: could not read  ${D}(try: sudo bash mac-check.sh)${NC}"
elif printf '%s' "$PROF" | grep -qi 'no configuration profiles'; then
  pass "Config profiles: None installed"
else
  PC=$(printf '%s' "$PROF" | grep -c 'profileIdentifier' 2>/dev/null || echo '?')
  warn "Config profiles: ${BOLD}$PC${NC} installed  — review what they restrict"
fi

# ════════════════════════════════════════════════════════════════
# 4 · ACTIVATION LOCK & iCLOUD
# ════════════════════════════════════════════════════════════════
section "4 · Activation Lock & iCloud"

# Find My token in NVRAM (most reliable CLI indicator)
FMM=$(nvram -p 2>/dev/null | grep -c 'fmm-mobileme-token' 2>/dev/null)
if [[ "$FMM" -gt 0 ]]; then
  fail "Find My Mac NVRAM token detected  — Activation Lock is active"
  note "Ask seller: Settings → [their name] → Find My → Find My Mac → turn off"
  note "Then: System Settings → General → Transfer or Reset Mac → Erase All Content"
else
  pass "No Find My Mac token in NVRAM"
fi

# Signed-in Apple ID
APPLE_ID=$(defaults read /Library/Preferences/com.apple.MobileMeAccounts \
           2>/dev/null | awk -F'"' '/AccountID/{print $4;exit}' || true)
if [[ -n "$APPLE_ID" ]]; then
  warn "Apple ID signed in: ${BOLD}$APPLE_ID${NC}"
  note "Seller must sign out before transfer — Activation Lock remains until they do"
else
  pass "No Apple ID signed in on this device"
fi

printf "\n  ${Y}▸${NC} ${BOLD}Always verify manually at:${NC}\n"
printf "    ${C}https://checkcoverage.apple.com/${NC}"
[[ -n "$SERIAL" ]] && printf "  ${D}(serial: $SERIAL)${NC}"
printf "\n"

# ════════════════════════════════════════════════════════════════
# 5 · SECURITY SETTINGS
# ════════════════════════════════════════════════════════════════
section "5 · Security Settings"

# SIP
SIP=$(csrutil status 2>/dev/null || echo 'unknown')
if   printf '%s' "$SIP" | grep -qi 'enabled';  then
  pass "System Integrity Protection (SIP): Enabled"
elif printf '%s' "$SIP" | grep -qi 'disabled'; then
  warn "SIP: ${Y}Disabled${NC}  — requires Recovery Mode to change; may indicate tampering"
  note "Re-enable after purchase: Recovery Mode → Terminal → csrutil enable"
fi

# FileVault
FV=$(fdesetup status 2>/dev/null | head -1 || echo '')
if   printf '%s' "$FV" | grep -qiE 'is on|: on';  then pass "FileVault (disk encryption): Enabled"
elif printf '%s' "$FV" | grep -qiE 'is off|: off'; then info "FileVault: Disabled  ${D}(expected on a device being sold)${NC}"
fi

# Gatekeeper
GK=$(spctl --status 2>/dev/null || echo '')
if   printf '%s' "$GK" | grep -qi 'enabled';  then pass "Gatekeeper: Enabled"
elif printf '%s' "$GK" | grep -qi 'disabled'; then warn "Gatekeeper: Disabled  — allows apps from anywhere (was manually changed)"
fi

# T2 chip (Intel) or Apple Silicon
if [[ -z "$CHIP" ]] || printf '%s' "$CHIP" | grep -qi 'Intel\|Core'; then
  T2=$(system_profiler SPiBridgeDataType 2>/dev/null || true)
  if printf '%s' "$T2" | grep -qi 'T2'; then
    info "T2 Security Chip: present"
    BOOT_LVL=$(printf '%s' "$T2" | awk -F':[[:space:]]+' '/Boot Security Level/{print $2;exit}')
    EXT_BOOT=$( printf '%s' "$T2" | awk -F':[[:space:]]+' '/Allow External Boot/{print $2;exit}')
    if [[ -n "$BOOT_LVL" ]]; then
      [[ "$BOOT_LVL" == "Full Security" ]] \
        && pass "Secure Boot: $BOOT_LVL" \
        || warn "Secure Boot: ${Y}$BOOT_LVL${NC}  — default is 'Full Security'"
    fi
    [[ -n "$EXT_BOOT" ]] && info "External Boot: $EXT_BOOT"
  fi
else
  info "Secure Boot: Apple Silicon — hardware-enforced, always active"
fi

# ════════════════════════════════════════════════════════════════
# 6 · STORAGE
# ════════════════════════════════════════════════════════════════
section "6 · Storage"

DI=$(diskutil info disk0 2>/dev/null)
SMART=$( printf '%s' "$DI" | awk -F':[[:space:]]+' '/SMART Status/{print $2;exit}')
DSIZ=$(  printf '%s' "$DI" | awk -F':[[:space:]]+' '/Disk Size/{print $2;exit}')
MEDIA=$( printf '%s' "$DI" | awk -F':[[:space:]]+' '/Media Type/{print $2;exit}')
REMOTE=$(printf '%s' "$DI" | awk -F':[[:space:]]+' '/Protocol/{print $2;exit}')

[[ -n "$DSIZ"   ]] && info "${BOLD}Disk Size:${NC}   $DSIZ"
[[ -n "$MEDIA"  ]] && info "${BOLD}Media Type:${NC}  $MEDIA"
[[ -n "$REMOTE" ]] && info "${BOLD}Protocol:${NC}    $REMOTE"

case "$SMART" in
  Verified)        pass "SMART Status: Verified  ${G}(disk is healthy)${NC}" ;;
  'Not Supported') info "SMART Status: Not Supported  ${D}(normal for Apple Silicon internal NVMe)${NC}" ;;
  '')              info "SMART Status: could not read" ;;
  *)               fail "SMART Status: ${R}$SMART${NC}  — potential drive failure" ;;
esac

D_TOT=$( df -H / | tail -1 | awk '{print $2}')
D_USED=$(df -H / | tail -1 | awk '{print $3}')
D_FREE=$(df -H / | tail -1 | awk '{print $4}')
D_PCT=$( df -H / | tail -1 | awk '{print $5}' | tr -d '%')
info "${BOLD}Usage:${NC}       $D_USED of $D_TOT  ($D_FREE free)"
[[ "$D_PCT" =~ ^[0-9]+$ ]] && (( D_PCT >= 90 )) && warn "Disk is ${D_PCT}% full  — very little space remaining"

# ════════════════════════════════════════════════════════════════
# 7 · DISPLAY & GPU
# ════════════════════════════════════════════════════════════════
section "7 · Display & GPU"

DISP=$(system_profiler SPDisplaysDataType 2>/dev/null)
GPU=$(  printf '%s' "$DISP" | awk -F':[[:space:]]+' '/Chipset Model/{print $2;exit}')
VRAM=$( printf '%s' "$DISP" | awk -F':[[:space:]]+' '/VRAM \(Total\)/{print $2;exit}')
RES=$(  printf '%s' "$DISP" | awk -F':[[:space:]]+' '/Resolution/{print $2;exit}')
DNAME=$(printf '%s' "$DISP" | awk -F':[[:space:]]+' '/Display Type/{print $2;exit}')

[[ -n "$GPU"   ]] && info "${BOLD}GPU:${NC}         $GPU${VRAM:+  ($VRAM VRAM)}"
[[ -n "$RES"   ]] && info "${BOLD}Resolution:${NC}  $RES"
[[ -n "$DNAME" ]] && info "${BOLD}Panel Type:${NC}  $DNAME"
printf '%s' "$DISP" | grep -qi 'Retina' && info "${BOLD}Display:${NC}     Retina"

# ════════════════════════════════════════════════════════════════
# 8 · USER ACCOUNTS
# ════════════════════════════════════════════════════════════════
section "8 · User Accounts"

USERS=$(dscl . list /Users 2>/dev/null \
  | grep -vE '^_|^daemon$|^nobody$|^root$|^Guest$|^com\.' || true)
UC=$(printf '%s\n' "$USERS" | grep -c '[[:alnum:]]' 2>/dev/null || echo 0)

if   (( UC == 0 )); then pass "No leftover user accounts"
elif (( UC == 1 )); then info "User accounts: 1  ($USERS)"
else
  warn "$UC user accounts still present:"
  printf '%s\n' "$USERS" | while IFS= read -r u; do [[ -n "$u" ]] && note "$u"; done
fi
info "Running as: ${BOLD}$(whoami)${NC}"

# ════════════════════════════════════════════════════════════════
# 9 · SYSTEM STABILITY  (kernel panics / crashes)
# ════════════════════════════════════════════════════════════════
section "9 · System Stability"

PANIC_DIR="/Library/Logs/DiagnosticReports"
PANICS=$(find "$PANIC_DIR" -maxdepth 1 -name '*.panic' 2>/dev/null | wc -l | tr -d ' ')
CRASHES=$(find "$PANIC_DIR" -maxdepth 1 -name '*.crash' 2>/dev/null | wc -l | tr -d ' ')
SPINS=$( find "$PANIC_DIR" -maxdepth 1 -name '*.spin'  2>/dev/null | wc -l | tr -d ' ')

if [[ "$PANICS" -eq 0 ]]; then
  pass "Kernel panics: 0  ${G}(no recorded system crashes)${NC}"
else
  fail "Kernel panics: ${BOLD}$PANICS${NC} found  — indicates hardware or driver instability"
  note "Inspect with: ls /Library/Logs/DiagnosticReports/*.panic"
fi

if [[ "$CRASHES" -gt 5 ]]; then
  warn "App crash reports: $CRASHES  — higher than typical"
else
  info "App crash reports: $CRASHES"
fi

[[ "$SPINS" -gt 0 ]] && info "Hang/spin reports: $SPINS"

UPTIME_STR=$(uptime 2>/dev/null | sed 's/^.*up //' | sed 's/,  [0-9]* user.*//')
info "Current uptime:  $UPTIME_STR"

# ════════════════════════════════════════════════════════════════
# 10 · NETWORK HARDWARE
# ════════════════════════════════════════════════════════════════
section "10 · Network Hardware"

WIFI=$(system_profiler SPAirPortDataType 2>/dev/null | awk -F':[[:space:]]+' '/Supported PHY Modes/{print $2;exit}')
BT=$(  system_profiler SPBluetoothDataType 2>/dev/null | awk -F':[[:space:]]+' '/Apple Bluetooth Software/{print $2;exit}')

[[ -n "$WIFI" ]] && info "Wi-Fi:      802.11 $WIFI" || info "Wi-Fi:      not detected"
[[ -n "$BT"   ]] && info "Bluetooth:  present (stack v$BT)" || info "Bluetooth:  not detected"

TB_DEVS=$(system_profiler SPThunderboltDataType 2>/dev/null | grep -c 'Vendor ID' || echo 0)
[[ "$TB_DEVS" -gt 0 ]] && info "Thunderbolt bus endpoints detected: $TB_DEVS"

# ════════════════════════════════════════════════════════════════
# 11 · WARRANTY & LINKS
# ════════════════════════════════════════════════════════════════
section "11 · Warranty & Useful Links"

info "Serial:      ${BOLD}${SERIAL:-(unavailable)}${NC}"
printf "  ${B}·${NC}  Coverage & repair status:\n"
printf "      ${C}https://checkcoverage.apple.com/${NC}\n"
printf "  ${B}·${NC}  AppleCare+ lookup:\n"
printf "      ${C}https://selfsolve.apple.com/agreementWarrantyDynamic.do${NC}\n"
printf "  ${B}·${NC}  Activation Lock check:\n"
printf "      ${C}https://www.icloud.com/activationlock/${NC}\n"

# ════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════
printf "\n${BOLD}${B}"
printf '╔══════════════════════════════════════════════════════════╗\n'
printf '║                         Summary                          ║\n'
printf '╚══════════════════════════════════════════════════════════╝\n'
printf "${NC}\n"
printf "  Issues:   ${R}${BOLD}%d${NC}\n" "$ISSUES"
printf "  Warnings: ${Y}${BOLD}%d${NC}\n\n" "$WARNINGS"

if   (( ISSUES == 0 && WARNINGS == 0 )); then
  printf "  ${G}${BOLD}✔  All checks passed — this Mac looks good to buy!${NC}\n"
elif (( ISSUES == 0 )); then
  printf "  ${Y}${BOLD}⚠  No blockers, but review the warnings above before committing.${NC}\n"
else
  printf "  ${R}${BOLD}✘  %d critical issue(s) found — investigate carefully before buying.${NC}\n" "$ISSUES"
fi

printf "\n  ${D}Serial: %s${NC}\n" "${SERIAL:-(unavailable)}"
printf "  ${D}Coverage: https://checkcoverage.apple.com/${NC}\n\n"
