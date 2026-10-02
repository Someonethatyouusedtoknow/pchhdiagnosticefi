if [ -t 1 ]; then
    B=$(printf '\033[1m');  DIM=$(printf '\033[2m')
    RED=$(printf '\033[31m'); GRN=$(printf '\033[32m')
    YLW=$(printf '\033[33m'); BLU=$(printf '\033[36m')
    RST=$(printf '\033[0m')
else
    B=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; RST=""
fi

rule()    { printf '%s\n' "------------------------------------------------------------"; }

header()  {
    printf '\n%s%s== %s ==%s\n' "$B" "$BLU" "$*" "$RST"
    rule
}

section() { printf '\n%s%s%s\n' "$B" "$*" "$RST"; }

kv()      { printf '  %-22s %s\n' "$1" "$2"; }

info()    { printf '  %s\n' "$*"; }
ok()      { printf '  %s[ OK ]%s %s\n' "$GRN" "$RST" "$*"; }
warn()    { printf '  %s[WARN]%s %s\n' "$YLW" "$RST" "$*"; }
bad()     { printf '  %s[FAIL]%s %s\n' "$RED" "$RST" "$*"; }

have()    { command -v "$1" >/dev/null 2>&1; }

dmi() {
    have dmidecode || return 0
    dmidecode -s "$1" 2>/dev/null
}

pause() {
    printf '\n'
    printf '  %sPress Enter to return to the menu...%s' "$DIM" "$RST"
    read -r _
}

load_settings() {
    PCHH_CPU_SECONDS=30
    PCHH_AUTO_USB_REPORT=1
    PCHH_GPU_VISUAL=1
    PCHH_VERBOSE=0
    PCHH_RAM_MODE=live
    [ -r /run/pchh/settings.conf ] || return 0
    while IFS='=' read -r key value; do
        case "$key" in
            PCHH_CPU_SECONDS) case "$value" in ''|*[!0-9]*) ;; *) PCHH_CPU_SECONDS="$value" ;; esac ;;
            PCHH_AUTO_USB_REPORT|PCHH_GPU_VISUAL|PCHH_VERBOSE)
                case "$value" in 0|1) eval "$key=$value" ;; esac ;;
            PCHH_RAM_MODE)
                case "$value" in live|memtest) PCHH_RAM_MODE="$value" ;; esac ;;
        esac
    done < /run/pchh/settings.conf
}

sanitize_output() {
    awk 'BEGIN { backspace=sprintf("%c", 8) }
    {
        output=""
        for (i=1; i<=length($0); i++) {
            char=substr($0, i, 1)
            if (char == backspace) {
                if (length(output) > 0) output=substr(output, 1, length(output)-1)
            } else if (char != "\r") {
                output=output char
            }
        }
        print output
    }'
}

find_pchh_data_device() {
    local label device candidate
    [ -d /sys/dev/block ] || return 1
    have blkid || return 1
    device=$(blkid -t LABEL=PCHH_DATA -o device 2>/dev/null | head -n 1)
    [ -n "$device" ] && { printf '%s\n' "$device"; return 0; }
    for candidate in /dev/sd* /dev/nvme* /dev/mmcblk*; do
        [ -e "$candidate" ] || continue
        label=$(blkid "$candidate" 2>/dev/null | sed -n 's/.*LABEL="\([^"]*\)".*/\1/p')
        [ "$label" = PCHH_DATA ] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

save_result_to_usb() {
    local source="$1" device mountpoint mounted_here=0 target
    [ -s "$source" ] || { bad "No result to save"; return 1; }
    device=$(find_pchh_data_device) || { bad "PCHH_DATA not visible"; return 1; }
    mountpoint=$(findmnt -n -o TARGET "$device" 2>/dev/null || true)
    if [ -z "$mountpoint" ]; then
        mountpoint=/mnt/pchh-usb
        mkdir -p "$mountpoint"
        mount -o rw "$device" "$mountpoint" 2>/dev/null || { bad "USB mount failed"; return 1; }
        mounted_here=1
    fi
    target="$mountpoint/pchh-result-$(date +%Y%m%d-%H%M%S).txt"
    if cp "$source" "$target" && sync && [ -s "$target" ]; then
        ok "Saved to USB"
        [ "$mounted_here" -eq 1 ] && umount "$mountpoint" 2>/dev/null || true
        return 0
    fi
    [ "$mounted_here" -eq 1 ] && umount "$mountpoint" 2>/dev/null || true
    bad "USB write failed"
    return 1
}

list_dimms() {
    have dmidecode || { info "dmidecode not available"; return 0; }
    dmidecode -t memory 2>/dev/null | awk '
        function flush() {
            if (size != "" && size != "No Module Installed" && size != "Not Installed")
                printf "  %-14s %-9s %-13s %-18s %s\n", loc, size, type, man, part
        }
        /^Memory Device/ { flush(); loc=size=type=man=part=""; next }
        {
            key=$0; sub(/:.*/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", key)
            val=$0; sub(/^[^:]*:[ \t]*/, "", val)
            if      (key=="Locator")      loc=val
            else if (key=="Size")         size=val
            else if (key=="Type")         type=val
            else if (key=="Manufacturer") man=val
            else if (key=="Part Number")  part=val
        }
        END { flush() }
    '
}
