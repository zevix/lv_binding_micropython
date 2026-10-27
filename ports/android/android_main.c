/*
 * Android entry point for the MicroPython unix port with LVGL.
 *
 * SDL's Java activity (org.libsdl.app.SDLActivity) loads libmain.so and calls
 * SDL_main() on its own thread. Here we prepare a unix-like environment and
 * then call the regular unix port main() with the script to run:
 *
 *  - stdout/stderr are forwarded to logcat (tag "micropython").
 *  - If <external files dir>/main.py exists it is run, so a script can be
 *    replaced without rebuilding the APK:
 *      adb push main.py /sdcard/Android/data/<package>/files/main.py
 *  - Otherwise main.py bundled in the APK assets is extracted and run.
 *  - Display size and DPI are exported as LV_ANDROID_WIDTH, LV_ANDROID_HEIGHT,
 *    LV_ANDROID_DPI and LV_ANDROID_ZOOM environment variables.
 */

#ifdef __ANDROID__

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/stat.h>
#include <android/log.h>

#include <SDL2/SDL.h>

// SDL_main.h renames main to SDL_main, but we need the unix port's main().
#undef main
int main(int argc, char **argv);

#define LOG_TAG "micropython"
#define SCRIPT_NAME "main.py"

static int log_pipe[2];
static pthread_t log_thread;

// Keep the tail of the output, to show it if the script fails.
static char log_tail[2048];
static size_t log_tail_len;

static void log_tail_append(const char *s, size_t n) {
    if (n >= sizeof(log_tail)) {
        s += n - (sizeof(log_tail) - 1);
        n = sizeof(log_tail) - 1;
    }
    if (log_tail_len + n >= sizeof(log_tail)) {
        size_t drop = log_tail_len + n - (sizeof(log_tail) - 1);
        memmove(log_tail, log_tail + drop, log_tail_len - drop);
        log_tail_len -= drop;
    }
    memcpy(log_tail + log_tail_len, s, n);
    log_tail_len += n;
    log_tail[log_tail_len] = '\0';
}

static void *log_thread_fn(void *arg) {
    (void)arg;
    FILE *in = fdopen(log_pipe[0], "r");
    char line[1024];
    while (in && fgets(line, sizeof(line), in)) {
        log_tail_append(line, strlen(line));
        __android_log_write(ANDROID_LOG_INFO, LOG_TAG, line);
    }
    return NULL;
}

static void redirect_stdio(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    if (pipe(log_pipe) != 0) {
        return;
    }
    dup2(log_pipe[1], STDOUT_FILENO);
    dup2(log_pipe[1], STDERR_FILENO);
    close(log_pipe[1]);
    pthread_create(&log_thread, NULL, log_thread_fn, NULL);
}

static void close_stdio(void) {
    fflush(stdout);
    fflush(stderr);
    // Closing the last write end of the pipe lets the log thread see EOF.
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    pthread_join(log_thread, NULL);
}

static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int extract_asset(const char *name, const char *dest) {
    SDL_RWops *src = SDL_RWFromFile(name, "rb");
    if (!src) {
        return -1;
    }
    FILE *out = fopen(dest, "wb");
    if (!out) {
        SDL_RWclose(src);
        return -1;
    }
    char buf[4096];
    size_t n;
    while ((n = SDL_RWread(src, buf, 1, sizeof(buf))) > 0) {
        fwrite(buf, 1, n, out);
    }
    fclose(out);
    SDL_RWclose(src);
    return 0;
}

static void export_int(const char *name, int value) {
    char buf[16];
    snprintf(buf, sizeof(buf), "%d", value);
    setenv(name, buf, 1);
}

static void export_display_info(void) {
    if (SDL_InitSubSystem(SDL_INIT_VIDEO) != 0) {
        return;
    }
    SDL_DisplayMode mode;
    if (SDL_GetDesktopDisplayMode(0, &mode) == 0) {
        export_int("LV_ANDROID_WIDTH", mode.w);
        export_int("LV_ANDROID_HEIGHT", mode.h);
    }
    float dpi = 160;
    SDL_GetDisplayDPI(0, &dpi, NULL, NULL);
    int zoom = (int)(dpi / 160 + 0.5f);
    export_int("LV_ANDROID_DPI", (int)dpi);
    export_int("LV_ANDROID_ZOOM", zoom < 1 ? 1 : zoom);
}

int SDL_main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    redirect_stdio();

    const char *internal = SDL_AndroidGetInternalStoragePath();
    const char *external = SDL_AndroidGetExternalStoragePath();
    const char *home = external ? external : internal;
    char script_dir[512];
    char script[600];

    snprintf(script, sizeof(script), "%s/" SCRIPT_NAME, external ? external : "");
    if (external && file_exists(script)) {
        snprintf(script_dir, sizeof(script_dir), "%s", external);
    } else {
        // Extract into a subdirectory: SDL_RWFromFile() looks in the internal
        // storage path before the assets, so don't put the copy there.
        snprintf(script_dir, sizeof(script_dir), "%s/app", internal);
        mkdir(script_dir, 0700);
        snprintf(script, sizeof(script), "%s/" SCRIPT_NAME, script_dir);
        if (extract_asset(SCRIPT_NAME, script) != 0) {
            printf("Cannot extract " SCRIPT_NAME " from assets: %s\n", SDL_GetError());
        }
    }

    setenv("HOME", home, 1);
    setenv("MICROPYPATH", ".frozen:~/lib", 0);
    export_display_info();
    if (chdir(script_dir) != 0) {
        printf("Cannot change directory to %s\n", script_dir);
    }
    printf("Running %s\n", script);

    char *mp_argv[] = { "micropython", "-X", "heapsize=32M", script, NULL };
    int ret = main(4, mp_argv);

    close_stdio();
    if (ret != 0) {
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "MicroPython exited with an error",
            log_tail_len ? log_tail : "No output, see logcat.", NULL);
    }

    // MicroPython and LVGL keep global state, so start from a fresh process
    // next time instead of reusing this one.
    exit(ret);
}

#endif // __ANDROID__
