# Android

Runs MicroPython with LVGL as an Android app. The unix port (`VARIANT=lvgl`) is
cross-compiled with the Android NDK into `libmain.so` and started by SDL2's Java
activity; LVGL draws through its SDL driver, and touch input arrives as mouse
events.

## Getting the APK

The [Android APK workflow](../../.github/workflows/android_apk.yml) builds a
debug-signed `lvgl-micropython.apk` (arm64-v8a, armeabi-v7a, x86_64; Android 9+)
on every push. Download it from the workflow run's artifacts and install it:

```
adb install lvgl-micropython.apk
```

## Running your own script

The app runs [main.py](main.py) bundled in the APK, unless a `main.py` exists in
the app's external files directory:

```
adb push my_script.py /sdcard/Android/data/org.lvgl.micropython/files/main.py
```

Modules placed in `/sdcard/Android/data/org.lvgl.micropython/files/lib` can be
imported. `print()` output and tracebacks go to logcat:

```
adb logcat -s micropython
```

The screen size, DPI and a suggested zoom factor are available as the
`LV_ANDROID_WIDTH`, `LV_ANDROID_HEIGHT`, `LV_ANDROID_DPI` and `LV_ANDROID_ZOOM`
environment variables (see `main.py`). There is no `machine.Timer` on Android, so
call `lv.task_handler()` from your own loop instead of using `lv_utils.event_loop`.

## Building locally

Needs the Android SDK and NDK, JDK 17, cmake and python3. In an
[lv_micropython](https://github.com/lvgl/lv_micropython) checkout:

```
make -C ports/unix VARIANT=lvgl submodules
ANDROID_NDK_HOME=/path/to/ndk user_modules/lv_binding_micropython/ports/android/build.sh
```

See [build.sh](build.sh) for the options (`ABIS`, `ANDROID_API`, `SDL_VERSION`, ...).
