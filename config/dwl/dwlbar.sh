
#!/bin/sh

# Pomalejsi metriky se ctou na pozadi.
# Hlavni smycka nikdy neceka na Bluetooth, GPU ani D-Bus.

CACHE_DIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/dwl-status.XXXXXXXX") || exit 1

cleanup() {
    trap - EXIT HUP INT TERM
    [ -n "${worker_pid:-}" ] && kill "$worker_pid" 2>/dev/null
    rm -rf "$CACHE_DIR"
}

trap 'exit 0' HUP INT TERM
trap cleanup EXIT

# Bezpecny zapis hodnot do cache
save_cache() {
    printf '%s\n' "$2" > "$CACHE_DIR/$1.tmp"
    mv -f "$CACHE_DIR/$1.tmp" "$CACHE_DIR/$1"
}

# Cteni posledni hodnoty
read_cache() {
    if [ -r "$CACHE_DIR/$1" ]; then
        cat "$CACHE_DIR/$1"
    else
        printf '%s' "$2"
    fi
}

# Pomalé monitorovani na pozadi
monitor_slow() {
    while :; do
        # GPU NVIDIA
        if command -v nvidia-smi >/dev/null 2>&1; then
            gpu_temp=$(timeout -k 0.2s 2s \
                nvidia-smi \
                --query-gpu=temperature.gpu \
                --format=csv,noheader,nounits \
                2>/dev/null | head -n 1)

            case "$gpu_temp" in
                ''|*[!0-9]*)
                    # Neuspesne mereni:
                    # ponechame posledni znamou hodnotu
                    ;;
                *)
                    gpu="󰢮 ${gpu_temp}°C"
                    save_cache gpu "$gpu"
                    ;;
            esac
        fi

        # Bluetooth
        bt=" N/A"
        if command -v bluetoothctl >/dev/null 2>&1; then
            bt_status=$(timeout -k 0.2s 1s \
                bluetoothctl show 2>/dev/null)

            case "$bt_status" in
                *"Powered: yes"*)
                    bt=" on"

                    bt_devices=$(timeout -k 0.2s 1s \
                        bluetoothctl devices Connected 2>/dev/null)

                    bt_name=$(printf '%s\n' "$bt_devices" |
                        sed -n '1s/^Device [^ ]* //p')

                    [ -n "$bt_name" ] && bt=" $bt_name"
                    ;;
                *"Powered: no"*) bt=" off" ;;
            esac
        fi
        save_cache bluetooth "$bt"

        # Sit
        net="󰤮"
        net_dev=$(timeout -k 0.2s 1s \
            ip route show default 2>/dev/null |
            awk 'NR == 1 {print $5}')

        if [ -n "$net_dev" ]; then
            if [ -d "/sys/class/net/$net_dev/wireless" ] ||
               [ -d "/sys/class/net/$net_dev/phy80211" ]; then

                ssid=$(timeout -k 0.2s 1s \
                    nmcli -g GENERAL.CONNECTION \
                    device show "$net_dev" 2>/dev/null)

                if [ -n "$ssid" ] && [ "$ssid" != "--" ]; then
                    net="  $ssid"
                else
                    net="  Wi-Fi"
                fi
            else
                net=""
            fi
        fi
        save_cache network "$net"

        # Zvuk a mikrofon
        audio=" N/A"
        wp_out=$(timeout -k 0.2s 1s \
            wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)

        if [ -n "$wp_out" ]; then
            vol=$(printf '%s\n' "$wp_out" |
                awk '{printf "%.0f", $2 * 100}')

            case "$wp_out" in
                *MUTED*) audio=" Mute" ;;
                *)
                    if [ "$vol" -ge 66 ]; then ico=""
                    elif [ "$vol" -ge 33 ]; then ico=""
                    else ico=""
                    fi

                    mic=$(timeout -k 0.2s 1s \
                        wpctl get-volume @DEFAULT_AUDIO_SOURCE@ \
                        2>/dev/null)

                    case "$mic" in
                        *MUTED*) mic_ico="" ;;
                        *) mic_ico="" ;;
                    esac

                    audio=$(printf '%s %3d%% %s' \
                        "$ico" "$vol" "$mic_ico")
                    ;;
            esac
        fi
        save_cache audio "$audio"

        # Podsviceni
        backlight=""
        if command -v brightnessctl >/dev/null 2>&1; then
            bright=$(timeout -k 0.2s 1s \
                brightnessctl -m 2>/dev/null |
                cut -d',' -f4 | tr -d '%')

            case "$bright" in
                ''|*[!0-9]*) ;;
                *) backlight=$(printf '● %3d%%' "$bright") ;;
            esac
        fi
        save_cache backlight "$backlight"

        sleep 5
    done
}

monitor_slow &
worker_pid=$!

# Hodnoty CPU pro vypocet vytizeni
prev_idle=0
prev_total=0

# Hlavni rychla smycka
while :; do

    # CPU teplota
    temperature=" N/A"

    if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
        read -r raw_temp < /sys/class/thermal/thermal_zone0/temp
        temp=$((raw_temp / 1000))

        if [ "$temp" -ge 80 ]; then ico=""
        elif [ "$temp" -ge 50 ]; then ico=""
        else ico=""
        fi

        temperature=$(printf '%s %2d°C' "$ico" "$temp")
    fi

    # CPU vytizeni
    read -r _ user nice system idle iowait irq softirq \
        _ < /proc/stat

    idle_now=$((idle + iowait))
    total_now=$((user + nice + system + idle + iowait + irq + softirq))

    diff_idle=$((idle_now - prev_idle))
    diff_total=$((total_now - prev_total))

    cpu_val=0
    if [ "$prev_total" -gt 0 ] && [ "$diff_total" -gt 0 ]; then
        cpu_val=$((100 * (diff_total - diff_idle) / diff_total))
    fi

    prev_idle=$idle_now
    prev_total=$total_now

    cpu=$(printf ' %3d%%' "$cpu_val")

    # RAM
    memory_usage=$(free | awk '/Mem:/ {
        printf "%.0f", $3 / $2 * 100
    }')
    memory=$(printf ' %3d%%' "$memory_usage")

    # Baterie
    battery=""
    if [ -r /sys/class/power_supply/BAT0/capacity ]; then
        read -r cap < /sys/class/power_supply/BAT0/capacity
        read -r state < /sys/class/power_supply/BAT0/status

        if [ "$state" = "Charging" ]; then ico=""
        elif [ "$state" = "Full" ]; then ico=""
        elif [ "$cap" -ge 80 ]; then ico=""
        elif [ "$cap" -ge 60 ]; then ico=""
        elif [ "$cap" -ge 40 ]; then ico=""
        elif [ "$cap" -ge 20 ]; then ico=""
        else ico=""
        fi

        battery=$(printf '%s %3d%%' "$ico" "$cap")
    fi

    # Nacteni cache bez cekani na sondy
    gpu=$(read_cache gpu "")
    network=$(read_cache network "󰤮")
    bluetooth=$(read_cache bluetooth " N/A")
    audio=$(read_cache audio " N/A")
    backlight=$(read_cache backlight "")

    # Cas nacitame az bezprostredne pred vykreslenim
    clock="W$(date '+%V %d.%m.%Y %H:%M:%S')"

    printf ' %s  %s  %s  %s  %s  %s  %s  %s  %s  %s\n' \
        "$temperature" "$gpu" "$cpu" "$memory" \
        "$network" "$bluetooth" "$audio" \
        "$backlight" "$battery" "$clock"

    sleep 1
done

