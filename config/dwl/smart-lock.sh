#!/bin/sh

if playerctl sttus 2>/dev/null | grep -q "Playing"; then
    exit 0
fi

waylock -init-color 0x000000


