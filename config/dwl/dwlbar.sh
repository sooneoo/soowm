#!/bin/sh

while :
do
    # 1. Datum a čas: W{týden} {dd.mm.yyyy} {HH:MM:SS}
    clock="W$(date "+%V %d.%m.%Y %H:%M:%S")"

    # 2. Teplota CPU (°C) z hwmon2 (zarovnáno na 2 místa)
    if [ -f /sys/class/hwmon/hwmon2/temp1_input ]; then
        temp_val=$(($(cat /sys/class/hwmon/hwmon2/temp1_input) / 1000))
        if [ "$temp_val" -ge 80 ]; then
            temp_icon=""
        elif [ "$temp_val" -ge 50 ]; then
            temp_icon=""
        else
            temp_icon=""
        fi
        temp_formatted=$(printf "%2d" "$temp_val")
        temperature="$temp_icon ${temp_formatted}°C"
    else
        temperature=" N/A"
    fi

    # 3. Využití CPU (%) (zarovnáno na 3 místa)
    # 3. Využití CPU (%) – přesné okamžité vytížení z /proc/stat
	# 3. Využití CPU (%) – přesný výpočet rozdílu oproti předchozí sekundě
    if [ -f /tmp/.cpu_usage_prev ]; then
        read -r prev_idle prev_total < /tmp/.cpu_usage_prev
    else
        prev_idle=0
        prev_total=0
    fi

    # Načtení aktuálních hodnot CPU z /proc/stat
    cpu_line=$(grep '^cpu ' /proc/stat)
    idle=$(echo "$cpu_line" | awk '{print $5 + $6}')
    total=$(echo "$cpu_line" | awk '{print $2+$3+$4+$5+$6+$7+$8}')

    # Výpočet rozdílu oproti předchozímu měření
    diff_idle=$((idle - prev_idle))
    diff_total=$((total - prev_total))

    if [ "$diff_total" -gt 0 ]; then
        cpu_val=$(( (100 * (diff_total - diff_idle)) / diff_total ))
    else
        cpu_val=0
    fi

    # Uložení aktuálních hodnot pro příští iteraci
    echo "$idle $total" > /tmp/.cpu_usage_prev

    cpu_formatted=$(printf "%3d" "$cpu_val")
    cpu=" ${cpu_formatted}%"


    # 4. Využití paměti RAM (%) (zarovnáno na 3 místa)
    memory_usage=$(free | awk '/Mem:/ {printf("%.0f", $3/$2 * 100)}')
    memory_formatted=$(printf "%3d" "$memory_usage")
    memory=" ${memory_formatted}%"

    # 5. Síť (Wi-Fi s SSID / Ethernet pouze ikona / Nepřipojeno)
    net_dev=$(ip route | grep default | awk '{print $5}' | head -n1)

    if [ -n "$net_dev" ]; then
        case "$net_dev" in
            w*) is_wifi=1 ;;
            *)
                if [ -d "/sys/class/net/$net_dev/wireless" ] || [ -d "/sys/class/net/$net_dev/phy80211" ]; then
                    is_wifi=1
                else
                    is_wifi=0
                fi
                ;;
        esac

        if [ "$is_wifi" -eq 1 ]; then
            ssid=$(nmcli -t -f GENERAL.CONNECTION dev show "$net_dev" 2>/dev/null | cut -d: -f2)
            [ -z "$ssid" ] && ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep -E '^(yes|ano):' | cut -d: -f2)
            [ -z "$ssid" ] && ssid=$(iwctl station "$net_dev" show 2>/dev/null | awk -F'  +' '/Connected network/ {print $2}' | xargs)
            [ -z "$ssid" ] && ssid=$(wpa_cli -i "$net_dev" status 2>/dev/null | awk -F'=' '/^ssid=/ {print $2}')
            [ -z "$ssid" ] && ssid=$(iw dev "$net_dev" info 2>/dev/null | awk '/ssid/ {print $2}')
            [ -z "$ssid" ] && ssid=$(iwgetid -r 2>/dev/null)

            if [ -n "$ssid" ]; then
                network="  $ssid"
            else
                network="  Wi-Fi"
            fi
        else
            network=""
        fi
    else
        network="󰤮"
    fi

    # 6. Bluetooth
    if command -v bluetoothctl >/dev/null 2>&1; then
        if bluetoothctl show | grep -q "Powered: yes"; then
            bt_dev=$(bluetoothctl info | grep "Name:" | cut -d ' ' -f2-)
            if [ -n "$bt_dev" ]; then
                bluetooth=" $bt_dev"
            else
                bluetooth=" on"
            fi
        else
            bluetooth=" off"
        fi
    else
        bluetooth=" N/A"
    fi

    # 7. Zvuk a mikrofon (PipeWire přes wpctl) (zarovnáno na 3 místa)
    wpctl_out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    if [ -z "$wpctl_out" ]; then
        audio=" N/A"
    else
        vol_float=$(echo "$wpctl_out" | awk '{print $2}')
        audio_vol=$(awk -v v="$vol_float" 'BEGIN {printf "%.0f", v * 100}')

        if echo "$wpctl_out" | grep -q "MUTED"; then
            audio=" Mute "
        else
            if [ "$audio_vol" -ge 66 ]; then
                audio_icon=""
            elif [ "$audio_vol" -ge 33 ]; then
                audio_icon=""
            else
                audio_icon=""
            fi

            mic_out=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
            if echo "$mic_out" | grep -q "MUTED"; then
                mic_icon=""
            else
                mic_icon=""
            fi

            audio_formatted=$(printf "%3d" "$audio_vol")
            audio="$audio_icon ${audio_formatted}% $mic_icon"
        fi
    fi

    # 8. Podsvícení displeje (Backlight) (zarovnáno na 3 místa)
    if command -v brightnessctl >/dev/null 2>&1; then
        bright_val=$(brightnessctl -m 2>/dev/null | cut -d',' -f4 | tr -d '%')
        
        if [ -n "$bright_val" ]; then
            bright_formatted=$(printf "%3d" "$bright_val")
            backlight="● ${bright_formatted}%"
        else
            backlight=""
        fi
    else
        backlight=""
    fi

    # 9. Baterie (zarovnáno na 3 místa)
    if [ -d /sys/class/power_supply/BAT0 ]; then
        bat_capacity=$(cat /sys/class/power_supply/BAT0/capacity)
        bat_status=$(cat /sys/class/power_supply/BAT0/status)

        if [ "$bat_status" = "Charging" ]; then
            bat_icon=""
        elif [ "$bat_status" = "Full" ]; then
            bat_icon=""
        else
            if [ "$bat_capacity" -ge 80 ]; then bat_icon=""
            elif [ "$bat_capacity" -ge 60 ]; then bat_icon=""
            elif [ "$bat_capacity" -ge 40 ]; then bat_icon=""
            elif [ "$bat_capacity" -ge 20 ]; then bat_icon=""
            else bat_icon=""; fi
        fi
        bat_formatted=$(printf "%3d" "$bat_capacity")
        battery="$bat_icon ${bat_formatted}%"
    else
        battery=""
    fi

    # Vypisování do dwl lišty
    echo " $temperature $cpu $memory $network $bluetooth $audio $backlight $battery $clock"

    sleep 1
done
