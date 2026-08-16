#!/bin/sh

export MOZ_ENABLE_WAYLAND=1

# 1. Export proměnných
export XDG_CURRENT_DESKTOP=wlroots
export XDG_SESSION_TYPE=wayland


kanshi &

swayidle -w \
    timeout 300 '$HOME/.config/dwl/smart-lock.sh' \
    before-sleep '$HOME/.config/dwl/smart-lock.sh' &


# 2. Blok spuštěný na pozadí až po startu dwl
(
    # Počkejte 2 sekundy na plné načtení dwl a vytvoření WAYLAND_DISPLAY
    sleep 2

    # Vynutit ukončení případných visících portalů ze staré relace
    killall -9 xdg-desktop-portal-wlr 2>/dev/null
    killall -9 xdg-desktop-portal 2>/dev/null

    # Aktualizace D-Bus prostředí
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE

    # Přímé spuštění backendu i hlavního portalu
    if [ -f /usr/libexec/xdg-desktop-portal-wlr ]; then
        /usr/libexec/xdg-desktop-portal-wlr &
    else
        /usr/lib/xdg-desktop-portal-wlr &
    fi

    sleep 1

    if [ -f /usr/libexec/xdg-desktop-portal ]; then
        /usr/libexec/xdg-desktop-portal &
    else
        /usr/lib/xdg-desktop-portal &
    fi
) &

#mega-cmd-server >/dev/null 2>&1 &

sh $HOME/.config/dwl/dwlbar.sh | dwl


