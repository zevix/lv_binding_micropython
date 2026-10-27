# LVGL MicroPython demo for Android.
#
# To run your own script instead, without rebuilding the APK:
#   adb push main.py /sdcard/Android/data/org.lvgl.micropython/files/main.py
# Output (print, tracebacks) goes to logcat: adb logcat -s micropython

import os
import time
import lvgl as lv

lv.init()

# Exported by android_main.c. Scale the UI so it is readable on high DPI screens.
zoom = int(os.getenv("LV_ANDROID_ZOOM") or "1")
width = int(os.getenv("LV_ANDROID_WIDTH") or "480") // zoom
height = int(os.getenv("LV_ANDROID_HEIGHT") or "800") // zoom

disp = lv.sdl_window_create(width, height)
lv.sdl_window_set_zoom(disp, zoom)
mouse = lv.sdl_mouse_create()

scr = lv.screen_active()
scr.set_flex_flow(lv.FLEX_FLOW.COLUMN)
scr.set_flex_align(lv.FLEX_ALIGN.CENTER, lv.FLEX_ALIGN.CENTER, lv.FLEX_ALIGN.CENTER)
scr.set_style_pad_row(20, 0)

title = lv.label(scr)
title.set_text("LVGL + MicroPython")

clicks = 0
button = lv.button(scr)
button_label = lv.label(button)
button_label.set_text("Click me")


def on_click(e):
    global clicks
    clicks += 1
    button_label.set_text("Clicked %d times" % clicks)


button.add_event_cb(on_click, lv.EVENT.CLICKED, None)

slider = lv.slider(scr)
slider.set_width(lv.pct(80))
slider_label = lv.label(scr)
slider_label.set_text("0%")


def on_slider(e):
    slider_label.set_text("%d%%" % slider.get_value())


slider.add_event_cb(on_slider, lv.EVENT.VALUE_CHANGED, None)

switch = lv.switch(scr)
info = lv.label(scr)
info.set_text("%dx%d, zoom %d" % (width, height, zoom))

while True:
    time.sleep_ms(min(lv.task_handler(), 10))
