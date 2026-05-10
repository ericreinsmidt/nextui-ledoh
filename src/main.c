/*
 * LED'oh! — LED color controller for NextUI
 * Apostrophe UI + PakKit. No network required.
 *
 * Graphical front/back device view with selectable LED zones.
 * RGB color picker with live sysfs preview.
 * Saves to NextUI-compatible ledsettings file.
 * Per-LED animations via frame_hex (Brick only).
 */

#define AP_IMPLEMENTATION
#include "apostrophe.h"

#define PAKKIT_UI_IMPLEMENTATION
#include "pakkit_ui.h"

#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <signal.h>
#include <dirent.h>

/* -----------------------------------------------------------------------
 * Constants
 * ----------------------------------------------------------------------- */

#define LEDOH_VERSION    "0.5.0"
#define MAX_PATH_LEN     1280
#define MAX_ZONES        4
#define MAX_LINE         512

#define DEFAULT_BG_R     30
#define DEFAULT_BG_G     30
#define DEFAULT_BG_B     35
#define DEFAULT_TEXT_R   220
#define DEFAULT_TEXT_G   220
#define DEFAULT_TEXT_B   220
#define DEFAULT_HINT_R   140
#define DEFAULT_HINT_G   140
#define DEFAULT_HINT_B   150

#define VIEW_FRONT       0
#define VIEW_BACK        1

#define SLIDER_R         0
#define SLIDER_G         1
#define SLIDER_B         2
#define SLIDER_COUNT     3

/* Brick device image dimensions (source asset) */
#define BRICK_IMG_W      349
#define BRICK_IMG_H      532

/* Smart Pro device image dimensions (source asset) */
#define SP_IMG_W         500
#define SP_IMG_H         220

/* LED overlay positions in source image coordinates — Brick */
/* Front: FN1 */
#define FN1_X            132
#define FN1_Y            302
#define FN1_W            33
#define FN1_H            13

/* Front: FN2 */
#define FN2_X            184
#define FN2_Y            302
#define FN2_W            33
#define FN2_H            13

/* Back: Top bar (m) */
#define TOPBAR_X         87
#define TOPBAR_Y         0
#define TOPBAR_W         175
#define TOPBAR_H         13

/* Back: L triggers */
#define LTRIG_X          8
#define LTRIG_Y          222
#define LTRIG_W          134
#define LTRIG_H          18

/* Back: R triggers (mirrored) */
#define RTRIG_Y          222
#define RTRIG_H          18

/* LED overlay positions in source image coordinates — Smart Pro */
/* Triangle (m / Logo): small upward-pointing triangle near bottom center */
#define SP_TRI_TIP_X     250
#define SP_TRI_TIP_Y     202
#define SP_TRI_BL_X      246
#define SP_TRI_BL_Y      210
#define SP_TRI_BR_X      254
#define SP_TRI_BR_Y      210

/* Left joystick ring (l): annulus */
#define SP_RING_L_CX     58
#define SP_RING_L_CY     142
#define SP_RING_L_IR     19    /* inner radius (x spans 39-77, so (77-39)/2 = 19) */
#define SP_RING_L_OR     25   /* outer radius (x spans 33-82, so (82-33+1)/2 ≈ 25) */

/* Right joystick ring (r): mirrored from left */
#define SP_RING_R_CX     (SP_IMG_W - SP_RING_L_CX)  /* 442 */
#define SP_RING_R_CY     SP_RING_L_CY
#define SP_RING_R_IR     SP_RING_L_IR
#define SP_RING_R_OR     SP_RING_L_OR

/* Minimum effect value — effect 0 is "Off" which disables the LED entirely.
 * Users should use brightness=0 to turn off an LED, not effect=0.
 * We clamp to 1 (Linear Rise) as the minimum selectable effect. */
#define EFFECT_MIN       1


/* Front image variants */
#define FRONT_IMG_COUNT  3

/* Animation PID file — shared with animation shell scripts */
#define ANIM_PID_FILE    "/tmp/led_anim.pid"

/* Animation config file — persists selected animation across launches */
#define ANIM_CONFIG_FILE "anim_config"

/* Backup of LED settings while animation runs (real colors, not black) */
#define SETTINGS_BACKUP_SUFFIX ".anim_backup"

/* -----------------------------------------------------------------------
 * Data structures
 * ----------------------------------------------------------------------- */

typedef struct {
    const char *name;       /* Display name: "FN1 Key" */
    const char *filename;   /* Sysfs zone name: "f1" */
    int         view;       /* VIEW_FRONT or VIEW_BACK */
    int         zone_index; /* Index within its view (for d-pad navigation) */
} zone_def_t;

typedef struct {
    uint8_t r, g, b;
    uint8_t r2, g2, b2;    /* color2 — preserved from settings file for NextUI */
    int     effect;
    int     speed;
    int     brightness;
    int     trigger;
    int     inbrightness;
} zone_state_t;

/* LED overlay rectangle in source image coordinates (Brick) */
typedef struct {
    int x, y, w, h;
    int rounded;  /* 1 = draw with rounded corners */
} led_overlay_t;

/* Animation definition */
typedef struct {
    char name[64];          /* Display name parsed from "# NAME:" header */
    char script[64];        /* Script filename: "aurora.sh" */
} anim_def_t;

/* LED operating mode */
typedef enum {
    MODE_STATIC,     /* Normal per-zone effect settings (includes "off" = brightness 0) */
    MODE_ANIMATION,  /* Script daemon running */
} led_mode_t;

/* -----------------------------------------------------------------------
 * Animation list — discovered at runtime from scripts directory
 * Each .sh file in <pak_dir>/scripts/ is an animation.
 * Display name is read from a "# NAME: ..." header line in the script.
 * Falls back to the filename (without .sh) if no NAME header is found.
 * ----------------------------------------------------------------------- */

#define MAX_ANIMATIONS  64

static anim_def_t g_animations[MAX_ANIMATIONS];
static int        g_anim_count = 0;

/* -----------------------------------------------------------------------
 * Zone definitions — Brick / Brick Hammer
 * ----------------------------------------------------------------------- */

static const zone_def_t g_brick_zones[MAX_ZONES] = {
    { "FN1 Key",      "f1", VIEW_FRONT, 0 },
    { "FN2 Key",      "f2", VIEW_FRONT, 1 },
    { "Top Bar",      "m",  VIEW_BACK,  0 },
    { "L/R Triggers", "lr", VIEW_BACK,  1 },
};

/* Overlay positions per zone (source image coords) — Brick */
static const led_overlay_t g_brick_overlays[MAX_ZONES] = {
    { FN1_X, FN1_Y, FN1_W, FN1_H, 1 },       /* f1 */
    { FN2_X, FN2_Y, FN2_W, FN2_H, 1 },       /* f2 */
    { TOPBAR_X, TOPBAR_Y, TOPBAR_W, TOPBAR_H, 0 },  /* m */
    { 0, 0, 0, 0, 0 },                         /* lr — special: two rects */
};

/* -----------------------------------------------------------------------
 * Zone definitions — Smart Pro
 * ----------------------------------------------------------------------- */

#define SP_ZONE_COUNT    3

static const zone_def_t g_smartpro_zones[SP_ZONE_COUNT] = {
    { "Joystick L", "l", VIEW_FRONT, 0 },
    { "Logo",       "m", VIEW_FRONT, 1 },
    { "Joystick R", "r", VIEW_FRONT, 2 },
};

/* -----------------------------------------------------------------------
 * Globals
 * ----------------------------------------------------------------------- */

static int           g_is_brick     = 1;
static int           g_zone_count   = MAX_ZONES;
static const zone_def_t *g_zones    = g_brick_zones;

/* Device image dimensions (set at runtime based on device) */
static int           g_dev_img_w    = BRICK_IMG_W;
static int           g_dev_img_h    = BRICK_IMG_H;

static zone_state_t  g_zone_state[MAX_ZONES];
static int           g_current_view = VIEW_FRONT;
static int           g_selected_zone = 0;        /* index into g_zones[] */

static char          g_settings_path[MAX_PATH_LEN] = {0};

/* Device images */
static SDL_Texture  *g_img_front_variants[FRONT_IMG_COUNT] = {NULL};
static int           g_img_front_valid_count = 0;  /* how many loaded successfully */
static int           g_img_front_valid[FRONT_IMG_COUNT] = {0}; /* which indices loaded */
static SDL_Texture  *g_img_front_active = NULL;    /* currently displayed front image */
static SDL_Texture  *g_img_back  = NULL;

/* Pulse animation */
static Uint32        g_pulse_start = 0;

/* LED mode tracking */
static led_mode_t    g_led_mode = MODE_STATIC;

/* -----------------------------------------------------------------------
 * String helpers
 * ----------------------------------------------------------------------- */

static void trim_inplace(char *s) {
    char *start = s;
    while (*start == ' ' || *start == '\t' || *start == '\r' || *start == '\n')
        start++;
    if (start != s)
        memmove(s, start, strlen(start) + 1);
    size_t len = strlen(s);
    while (len > 0 && (s[len - 1] == ' ' || s[len - 1] == '\t' ||
                       s[len - 1] == '\r' || s[len - 1] == '\n')) {
        s[--len] = '\0';
    }
}

/* -----------------------------------------------------------------------
 * Sysfs helpers — write LED state to hardware
 * ----------------------------------------------------------------------- */

static void sysfs_write(const char *path, const char *value) {
    ap_log("SYSFS WRITE: %s = \"%s\"", path, value);
    FILE *f = fopen(path, "w");
    if (!f) {
        ap_log("SYSFS ERROR: failed to open %s: %s", path, strerror(errno));
        return;
    }
    if (fprintf(f, "%s\n", value) < 0) {
        ap_log("SYSFS ERROR: fprintf failed for %s: %s", path, strerror(errno));
    }
    fclose(f);
}

static void sysfs_write_int(const char *path, int value) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", value);
    sysfs_write(path, buf);
}

static void led_write_color(const char *filename, uint8_t r, uint8_t g, uint8_t b) {
    char path[256];
    snprintf(path, sizeof(path), "/sys/class/led_anim/effect_rgb_hex_%s", filename);
    char hex[16];
    /* Smart Pro 'm' zone LED expects GRB byte order */
    if (!g_is_brick && strcmp(filename, "m") == 0)
        snprintf(hex, sizeof(hex), "%02X%02X%02X", g, r, b);
    else
        snprintf(hex, sizeof(hex), "%02X%02X%02X", r, g, b);
    ap_log("LED COLOR [%s]: #%s (raw:%02X%02X%02X)", filename, hex, r, g, b);
    sysfs_write(path, hex);
}

static void led_write_effect(const char *filename, int effect) {
    char path[256];
    snprintf(path, sizeof(path), "/sys/class/led_anim/effect_%s", filename);
    ap_log("LED EFFECT [%s]: %d", filename, effect);
    sysfs_write_int(path, effect);
}

static void led_write_brightness(const char *filename, int brightness) {
    char path[256];
    if (g_is_brick) {
        if (strcmp(filename, "m") == 0)
            snprintf(path, sizeof(path), "/sys/class/led_anim/max_scale");
        else if (strcmp(filename, "f1") == 0 || strcmp(filename, "f2") == 0)
            snprintf(path, sizeof(path), "/sys/class/led_anim/max_scale_f1f2");
        else if (strcmp(filename, "lr") == 0)
            snprintf(path, sizeof(path), "/sys/class/led_anim/max_scale_lr");
        else
            snprintf(path, sizeof(path), "/sys/class/led_anim/max_scale_%s", filename);
    } else {
        snprintf(path, sizeof(path), "/sys/class/led_anim/max_scale");
    }
    ap_log("LED BRIGHTNESS [%s]: %d (path: %s)", filename, brightness, path);
    sysfs_write_int(path, brightness);
}

static void led_write_speed(const char *filename, int speed) {
    char path[256];
    snprintf(path, sizeof(path), "/sys/class/led_anim/effect_duration_%s", filename);
    ap_log("LED SPEED [%s]: %d", filename, speed);
    sysfs_write_int(path, speed);
}

static void led_write_cycles(const char *filename, int cycles) {
    char path[256];
    snprintf(path, sizeof(path), "/sys/class/led_anim/effect_cycles_%s", filename);
    ap_log("LED CYCLES [%s]: %d", filename, cycles);
    sysfs_write_int(path, cycles);
}

static void led_apply_zone(int zone_idx) {
    const zone_def_t *zd = &g_zones[zone_idx];
    zone_state_t *zs = &g_zone_state[zone_idx];

    ap_log("LED APPLY ZONE [%d/%s]: r=%d g=%d b=%d effect=%d brightness=%d speed=%d",
           zone_idx, zd->filename, zs->r, zs->g, zs->b,
           zs->effect, zs->brightness, zs->speed);

    led_write_color(zd->filename, zs->r, zs->g, zs->b);
    led_write_effect(zd->filename, zs->effect);
    led_write_brightness(zd->filename, zs->brightness);
    led_write_speed(zd->filename, zs->speed);
    led_write_cycles(zd->filename, -1);
}

static void led_apply_color_only(int zone_idx) {
    const zone_def_t *zd = &g_zones[zone_idx];
    zone_state_t *zs = &g_zone_state[zone_idx];
    ap_log("LED COLOR ONLY [%d/%s]: r=%d g=%d b=%d", zone_idx, zd->filename, zs->r, zs->g, zs->b);
    led_write_color(zd->filename, zs->r, zs->g, zs->b);
    /* Hardware requires an effect write to latch the new color.
     * The color picker forces static (4) on entry, so re-writing
     * effect=4 here is safe — static has no animation to re-trigger. */
    led_write_effect(zd->filename, 4);
}

/* Forward declarations */
static void save_settings(void);
static void settings_backup(void);
static int  settings_restore_backup(void);
static void anim_stop(void);
static void anim_start(int anim_idx);
static int  anim_is_running(void);
static int  anim_get_running_index(void);
static void anim_save_config(int anim_idx);

/* Sync brightness after a single zone change (handles shared hardware paths) */
static void sync_brightness_after_change(int zone_idx) {
    if (g_is_brick) {
        const char *fn = g_zones[zone_idx].filename;
        int val = g_zone_state[zone_idx].brightness;
        if (strcmp(fn, "f1") == 0)
            g_zone_state[1].brightness = val;
        else if (strcmp(fn, "f2") == 0)
            g_zone_state[0].brightness = val;
    } else {
        /* Smart Pro: all zones share max_scale */
        int val = g_zone_state[zone_idx].brightness;
        for (int i = 0; i < g_zone_count; i++) {
            g_zone_state[i].brightness = val;
        }
    }
}

/* -----------------------------------------------------------------------
 * Animation discovery — scan scripts directory at runtime
 * ----------------------------------------------------------------------- */

/* Compare animation entries by name for qsort (case-insensitive) */
static int anim_cmp(const void *a, const void *b) {
    return strcasecmp(((const anim_def_t *)a)->name,
                      ((const anim_def_t *)b)->name);
}

/* Scan the scripts directory for .sh files and populate g_animations[].
 * Each script can declare a display name via a "# NAME: ..." line
 * in its first 5 lines.  Falls back to the filename without extension. */
static void anim_scan_scripts(void) {
    const char *pak_dir = getenv("LEDOH_PAK_DIR");
    if (!pak_dir) {
        ap_log("ANIM SCAN: LEDOH_PAK_DIR not set, no animations available");
        return;
    }

    char scripts_dir[MAX_PATH_LEN];
    snprintf(scripts_dir, sizeof(scripts_dir), "%s/scripts", pak_dir);

    DIR *dir = opendir(scripts_dir);
    if (!dir) {
        ap_log("ANIM SCAN: cannot open %s: %s", scripts_dir, strerror(errno));
        return;
    }

    g_anim_count = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL && g_anim_count < MAX_ANIMATIONS) {
        /* Copy filename into a fixed-size buffer for safe handling */
        char fname[64];
        size_t len = strlen(entry->d_name);
        if (len < 4 || len >= sizeof(fname)) continue;
        memcpy(fname, entry->d_name, len + 1);

        /* Must end in .sh and not be hidden */
        if (strcmp(fname + len - 3, ".sh") != 0) continue;
        if (fname[0] == '.') continue;

        /* Try to read "# NAME: ..." from the first 5 lines of the script */
        char script_path[MAX_PATH_LEN + 80];
        snprintf(script_path, sizeof(script_path), "%s/%s", scripts_dir, fname);

        char display_name[64] = {0};
        FILE *f = fopen(script_path, "r");
        if (f) {
            char line[256];
            for (int i = 0; i < 5 && fgets(line, sizeof(line), f); i++) {
                /* Look for "# NAME: <display name>" */
                if (strncmp(line, "# NAME:", 7) == 0) {
                    char *name_start = line + 7;
                    while (*name_start == ' ') name_start++;
                    snprintf(display_name, sizeof(display_name), "%s", name_start);
                    /* Trim trailing whitespace */
                    size_t nlen = strlen(display_name);
                    while (nlen > 0 && (display_name[nlen-1] == '\n' ||
                           display_name[nlen-1] == '\r' ||
                           display_name[nlen-1] == ' '))
                        display_name[--nlen] = '\0';
                    break;
                }
            }
            fclose(f);
        }

        /* Fall back to filename without .sh extension */
        if (display_name[0] == '\0') {
            snprintf(display_name, sizeof(display_name), "%.*s",
                     (int)(len - 3), fname);
            /* Capitalize first letter */
            if (display_name[0] >= 'a' && display_name[0] <= 'z')
                display_name[0] -= 32;
        }

        anim_def_t *anim = &g_animations[g_anim_count];
        snprintf(anim->script, sizeof(anim->script), "%s", fname);
        snprintf(anim->name, sizeof(anim->name), "%s", display_name);
        g_anim_count++;

        ap_log("ANIM SCAN: found %s → \"%s\"", fname, display_name);
    }

    closedir(dir);

    /* Sort alphabetically by display name */
    if (g_anim_count > 0)
        qsort(g_animations, g_anim_count, sizeof(anim_def_t), anim_cmp);

    ap_log("ANIM SCAN: %d animations discovered in %s", g_anim_count, scripts_dir);
}

/* -----------------------------------------------------------------------
 * Animation management (Brick only)
 * ----------------------------------------------------------------------- */

/* Read PID from the animation PID file. Returns -1 if not found or invalid. */
static pid_t anim_read_pid(void) {
    FILE *f = fopen(ANIM_PID_FILE, "r");
    if (!f) return -1;
    char buf[32] = {0};
    if (!fgets(buf, sizeof(buf), f)) {
        fclose(f);
        return -1;
    }
    fclose(f);
    trim_inplace(buf);
    if (buf[0] == '\0') return -1;
    pid_t pid = (pid_t)atoi(buf);
    return (pid > 0) ? pid : -1;
}

/* Check if an animation is currently running */
static int anim_is_running(void) {
    pid_t pid = anim_read_pid();
    if (pid <= 0) return 0;
    /* Check if process exists (signal 0 = no signal, just check) */
    return (kill(pid, 0) == 0) ? 1 : 0;
}

/* Get the index of the currently running animation, or -1 if none.
 * Reads /proc/<pid>/cmdline to match against known script names. */
static int anim_get_running_index(void) {
    if (!anim_is_running()) return -1;

    pid_t pid = anim_read_pid();
    if (pid <= 0) return -1;

    /* Read the command line of the running process */
    char proc_path[64];
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/cmdline", (int)pid);
    FILE *f = fopen(proc_path, "r");
    if (!f) return -1;

    char cmdline[MAX_PATH_LEN] = {0};
    size_t n = fread(cmdline, 1, sizeof(cmdline) - 1, f);
    fclose(f);

    if (n == 0) return -1;

    /* cmdline has NUL-separated args; replace NULs with spaces for matching */
    for (size_t i = 0; i < n; i++) {
        if (cmdline[i] == '\0') cmdline[i] = ' ';
    }

    /* Match against known script filenames */
    for (int i = 0; i < g_anim_count; i++) {
        if (strstr(cmdline, g_animations[i].script) != NULL) {
            ap_log("ANIM: running animation detected: %s (pid %d)",
                   g_animations[i].name, (int)pid);
            return i;
        }
    }

    ap_log("ANIM: PID %d is running but doesn't match any known animation", (int)pid);
    return -1;
}

/* Stop any running animation and restore saved LED state */
static void anim_stop(void) {
    pid_t pid = anim_read_pid();
    if (pid <= 0) {
        ap_log("ANIM STOP: no PID file or invalid PID");
        return;
    }

    if (kill(pid, 0) != 0) {
        ap_log("ANIM STOP: PID %d not running, cleaning up PID file", (int)pid);
        unlink(ANIM_PID_FILE);
        return;
    }

    ap_log("ANIM STOP: killing animation PID %d", (int)pid);
    kill(pid, SIGTERM);

    /* Wait briefly for the process to exit and clean up */
    for (int i = 0; i < 10; i++) {
        usleep(100000); /* 100ms */
        if (kill(pid, 0) != 0) break;
    }

    /* Force kill if still alive */
    if (kill(pid, 0) == 0) {
        ap_log("ANIM STOP: SIGTERM didn't work, sending SIGKILL");
        kill(pid, SIGKILL);
        usleep(200000);
    }

    /* Clean up PID file if the script's trap didn't */
    unlink(ANIM_PID_FILE);

    /* Re-enable effect system and restore real settings from backup */
    ap_log("ANIM STOP: re-enabling effect system");
    sysfs_write_int("/sys/class/led_anim/effect_enable", 1);
    if (!settings_restore_backup()) {
        /* No backup — fall back to current g_zone_state */
        ap_log("ANIM STOP: no backup found, using current zone state");
    }
    for (int i = 0; i < g_zone_count; i++)
        led_apply_zone(i);
    save_settings();
}

/* Start an animation by index */
static void anim_start(int anim_idx) {
    if (anim_idx < 0 || anim_idx >= g_anim_count) return;

    const char *pak_dir = getenv("LEDOH_PAK_DIR");
    if (!pak_dir) {
        ap_log("ANIM START: LEDOH_PAK_DIR not set, cannot find scripts");
        return;
    }

    /* The script's own PID management will kill any existing animation */
    char cmd[MAX_PATH_LEN];
    snprintf(cmd, sizeof(cmd), "\"%s/scripts/%s\" > /dev/null 2>&1 &",
             pak_dir, g_animations[anim_idx].script);

    /* Blank the hardware AND settings file before launching.
     * Hardware: prevents blip during handoff to script.
     * File: prevents NextUI from periodically re-applying real colors
     * while the animation runs (causes intermittent blips).
     * We zero colors and effects but keep real brightness so NextUI
     * doesn't kill the animation by zeroing max_scale. */
    for (int i = 0; i < g_zone_count; i++) {
        led_write_color(g_zones[i].filename, 0, 0, 0);
        led_write_effect(g_zones[i].filename, 0);
    }

    /* Back up real settings, then write black to the settings file */
    settings_backup();
    {
        uint8_t saved_r[MAX_ZONES], saved_g[MAX_ZONES], saved_b[MAX_ZONES];
        int saved_effect[MAX_ZONES];
        for (int i = 0; i < g_zone_count; i++) {
            saved_r[i] = g_zone_state[i].r;
            saved_g[i] = g_zone_state[i].g;
            saved_b[i] = g_zone_state[i].b;
            saved_effect[i] = g_zone_state[i].effect;
            g_zone_state[i].r = 0;
            g_zone_state[i].g = 0;
            g_zone_state[i].b = 0;
            g_zone_state[i].effect = 0;
        }
        save_settings();
        for (int i = 0; i < g_zone_count; i++) {
            g_zone_state[i].r = saved_r[i];
            g_zone_state[i].g = saved_g[i];
            g_zone_state[i].b = saved_b[i];
            g_zone_state[i].effect = saved_effect[i];
        }
    }

    ap_log("ANIM START: launching %s: %s", g_animations[anim_idx].name, cmd);
    system(cmd);

    /* Brief pause to let the script start and write its PID */
    usleep(300000);

    ap_log("ANIM START: %s launched (pid file check: %s)",
           g_animations[anim_idx].name,
           anim_is_running() ? "running" : "not detected");
}

/* Pause animation for editing — returns the animation index that was running,
 * or -1 if none was running.  Pass the return value to anim_resume_after_editing(). */
static int anim_pause_for_editing(void) {
    if (!g_is_brick) return -1;
    if (g_led_mode != MODE_ANIMATION) return -1;
    if (!anim_is_running()) return -1;

    int idx = anim_get_running_index();
    const char *name = (idx >= 0) ? g_animations[idx].name : "Animation";

    ap_log("ANIM: pausing %s for editing (will resume on exit)", name);
    anim_stop();

    char msg[256];
    snprintf(msg, sizeof(msg), "%s paused for editing", name);
    pakkit_message(msg, "OK");

    return idx;
}

/* Resume animation after editing */
static void anim_resume_after_editing(int anim_idx) {
    if (!g_is_brick) return;
    if (anim_idx < 0) return;

    ap_log("ANIM: resuming %s after editing", g_animations[anim_idx].name);
    anim_start(anim_idx);
    g_led_mode = MODE_ANIMATION;
}

/* Save the currently running animation to a config file for persistence */
static void anim_save_config(int anim_idx) {
    const char *pak_dir = getenv("LEDOH_PAK_DIR");
    if (!pak_dir) return;

    char path[MAX_PATH_LEN];
    snprintf(path, sizeof(path), "%s/%s", pak_dir, ANIM_CONFIG_FILE);

    FILE *f = fopen(path, "w");
    if (!f) {
        ap_log("ANIM CONFIG: failed to save to %s: %s", path, strerror(errno));
        return;
    }

    if (anim_idx >= 0 && anim_idx < g_anim_count) {
        fprintf(f, "%s\n", g_animations[anim_idx].script);
        ap_log("ANIM CONFIG: saved %s to %s", g_animations[anim_idx].script, path);
    } else {
        fprintf(f, "off\n");
        ap_log("ANIM CONFIG: saved 'off' to %s", path);
    }

    fclose(f);
}

/* Load the saved animation config. Returns animation index, or -1 for off/none. */
static int anim_load_config(void) {
    const char *pak_dir = getenv("LEDOH_PAK_DIR");
    if (!pak_dir) return -1;

    char path[MAX_PATH_LEN];
    snprintf(path, sizeof(path), "%s/%s", pak_dir, ANIM_CONFIG_FILE);

    FILE *f = fopen(path, "r");
    if (!f) {
        ap_log("ANIM CONFIG: no config file at %s", path);
        return -1;
    }

    char line[256] = {0};
    if (!fgets(line, sizeof(line), f)) {
        fclose(f);
        return -1;
    }
    fclose(f);
    trim_inplace(line);

    if (strcmp(line, "off") == 0 || line[0] == '\0') {
        ap_log("ANIM CONFIG: loaded 'off'");
        return -1;
    }

    /* Match against known script filenames */
    for (int i = 0; i < g_anim_count; i++) {
        if (strcmp(line, g_animations[i].script) == 0) {
            ap_log("ANIM CONFIG: loaded %s (index %d)", g_animations[i].name, i);
            return i;
        }
    }

    ap_log("ANIM CONFIG: unknown script '%s'", line);
    return -1;
}

/* -----------------------------------------------------------------------
 * Settings file: load / save (NextUI-compatible INI format)
 * ----------------------------------------------------------------------- */

static void set_defaults(void) {
    ap_log("SETTINGS: setting defaults for %d zones", g_zone_count);
    for (int i = 0; i < g_zone_count; i++) {
        g_zone_state[i] = (zone_state_t){
            .r = 255, .g = 255, .b = 255,
            .r2 = 255, .g2 = 255, .b2 = 255,
            .effect = 4,
            .speed = 1000,
            .brightness = 100,
            .trigger = 1,
            .inbrightness = 100,
        };
    }
}

static int find_zone_by_section(const char *section) {
    for (int i = 0; i < g_zone_count; i++) {
        if (strcmp(g_zones[i].filename, section) == 0)
            return i;
    }
    return -1;
}

static void parse_color(const char *val, uint8_t *r, uint8_t *g, uint8_t *b) {
    unsigned int color = 0;
    if (val[0] == '0' && (val[1] == 'x' || val[1] == 'X'))
        sscanf(val + 2, "%x", &color);
    else
        sscanf(val, "%x", &color);
    *r = (color >> 16) & 0xFF;
    *g = (color >> 8) & 0xFF;
    *b = color & 0xFF;
}

static void load_settings(void) {
    set_defaults();

    if (g_settings_path[0] == '\0') return;

    FILE *f = fopen(g_settings_path, "r");
    if (!f) {
        ap_log("settings: file not found at %s, using defaults", g_settings_path);
        return;
    }

    char line[MAX_LINE];
    int current_zone = -1;

    while (fgets(line, sizeof(line), f)) {
        trim_inplace(line);
        if (line[0] == '\0' || line[0] == '#') continue;

        /* Section header */
        if (line[0] == '[') {
            char section[64] = {0};
            if (sscanf(line, "[%63[^]]]", section) == 1) {
                current_zone = find_zone_by_section(section);
                ap_log("SETTINGS: parsing section [%s] → zone_idx=%d", section, current_zone);
            }
            continue;
        }

        if (current_zone < 0) continue;

        zone_state_t *zs = &g_zone_state[current_zone];
        char key[MAX_LINE] = {0}, val[MAX_LINE] = {0};
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        snprintf(key, sizeof(key), "%s", line);
        snprintf(val, sizeof(val), "%s", eq + 1);
        trim_inplace(key);
        trim_inplace(val);

        if (strcmp(key, "color1") == 0) {
            parse_color(val, &zs->r, &zs->g, &zs->b);
        } else if (strcmp(key, "color2") == 0) {
            parse_color(val, &zs->r2, &zs->g2, &zs->b2);
        } else if (strcmp(key, "effect") == 0) {
            zs->effect = atoi(val);
            /* Clamp effect: 0 means "Off" which disables the LED.
             * If we load effect=0 from a file (e.g. written by another tool),
             * upgrade it to 4 (Static) so the LED is visible. */
            if (zs->effect < EFFECT_MIN) {
                ap_log("SETTINGS: zone %d effect=%d is below minimum, upgrading to 4 (Static)",
                       current_zone, zs->effect);
                zs->effect = 4;
            }
        } else if (strcmp(key, "speed") == 0) {
            zs->speed = atoi(val);
        } else if (strcmp(key, "brightness") == 0) {
            zs->brightness = atoi(val);
        } else if (strcmp(key, "trigger") == 0) {
            zs->trigger = atoi(val);
        } else if (strcmp(key, "inbrightness") == 0) {
            zs->inbrightness = atoi(val);
        }
    }

    fclose(f);

    /* Log loaded state */
    for (int i = 0; i < g_zone_count; i++) {
        zone_state_t *zs = &g_zone_state[i];
        ap_log("SETTINGS LOADED [%d/%s]: r=%d g=%d b=%d r2=%d g2=%d b2=%d effect=%d brightness=%d speed=%d trigger=%d inbrightness=%d",
               i, g_zones[i].filename, zs->r, zs->g, zs->b,
               zs->r2, zs->g2, zs->b2,
               zs->effect, zs->brightness, zs->speed, zs->trigger, zs->inbrightness);
    }

    ap_log("SETTINGS: loaded from %s", g_settings_path);
}

static void save_settings(void) {
    if (g_settings_path[0] == '\0') return;

    /* Ensure parent directory exists */
    char dir[MAX_PATH_LEN];
    snprintf(dir, sizeof(dir), "%s", g_settings_path);
    char *slash = strrchr(dir, '/');
    if (slash) {
        *slash = '\0';
        mkdir(dir, 0755);
    }

    FILE *f = fopen(g_settings_path, "w");
    if (!f) {
        ap_log("settings: failed to save to %s: %s", g_settings_path, strerror(errno));
        return;
    }

    for (int i = 0; i < g_zone_count; i++) {
        const zone_def_t *zd = &g_zones[i];
        zone_state_t *zs = &g_zone_state[i];
        uint32_t color1 = ((uint32_t)zs->r << 16) | ((uint32_t)zs->g << 8) | zs->b;
        /* color2 is preserved from the settings file — not overwritten with color1 */
        uint32_t color2 = ((uint32_t)zs->r2 << 16) | ((uint32_t)zs->g2 << 8) | zs->b2;

        ap_log("SETTINGS SAVED [%d/%s]: r=%d g=%d b=%d r2=%d g2=%d b2=%d effect=%d brightness=%d speed=%d",
               i, zd->filename, zs->r, zs->g, zs->b,
               zs->r2, zs->g2, zs->b2,
               zs->effect, zs->brightness, zs->speed);

        fprintf(f, "[%s]\n", zd->filename);
        fprintf(f, "effect=%d\n", zs->effect);
        fprintf(f, "color1=0x%06X\n", color1);
        fprintf(f, "color2=0x%06X\n", color2);
        fprintf(f, "speed=%d\n", zs->speed);
        fprintf(f, "brightness=%d\n", zs->brightness);
        fprintf(f, "trigger=%d\n", zs->trigger);
        fprintf(f, "filename=%s\n", zd->filename);
        fprintf(f, "inbrightness=%d\n", zs->inbrightness);
        fprintf(f, "\n");
    }

    fclose(f);
    ap_log("SETTINGS: saved to %s", g_settings_path);
}

/* Back up the settings file before animation blanks it.
 * Saves a copy with the real colors so they can be restored later. */
static void settings_backup(void) {
    if (g_settings_path[0] == '\0') return;

    char backup_path[MAX_PATH_LEN + 16];
    snprintf(backup_path, sizeof(backup_path), "%s%s", g_settings_path, SETTINGS_BACKUP_SUFFIX);

    /* Don't overwrite an existing backup — it has the real colors
     * from before any animation started.  On reboot the settings file
     * already has black, so backing it up again would lose the originals. */
    if (access(backup_path, F_OK) == 0) {
        ap_log("SETTINGS BACKUP: backup already exists, keeping it");
        return;
    }

    FILE *src = fopen(g_settings_path, "r");
    if (!src) return;
    FILE *dst = fopen(backup_path, "w");
    if (!dst) { fclose(src); return; }

    char buf[512];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), src)) > 0)
        fwrite(buf, 1, n, dst);

    fclose(src);
    fclose(dst);
    ap_log("SETTINGS BACKUP: saved to %s", backup_path);
}

/* Restore settings from backup (after animation stops or on startup recovery).
 * Copies backup over the main settings file, reloads into g_zone_state,
 * and deletes the backup. */
static int settings_restore_backup(void) {
    if (g_settings_path[0] == '\0') return 0;

    char backup_path[MAX_PATH_LEN + 16];
    snprintf(backup_path, sizeof(backup_path), "%s%s", g_settings_path, SETTINGS_BACKUP_SUFFIX);

    FILE *src = fopen(backup_path, "r");
    if (!src) return 0;  /* no backup exists */
    FILE *dst = fopen(g_settings_path, "w");
    if (!dst) { fclose(src); return 0; }

    char buf[512];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), src)) > 0)
        fwrite(buf, 1, n, dst);

    fclose(src);
    fclose(dst);
    unlink(backup_path);

    /* Reload settings into g_zone_state */
    load_settings();
    ap_log("SETTINGS BACKUP: restored from %s", backup_path);
    return 1;
}

/* -----------------------------------------------------------------------
 * Device image loading
 * ----------------------------------------------------------------------- */

/* Pick a random front image from loaded variants */
static void pick_random_front(void) {
    if (g_img_front_valid_count <= 0) {
        g_img_front_active = NULL;
        return;
    }
    if (g_img_front_valid_count == 1) {
        /* Only one loaded — always use it */
        for (int i = 0; i < FRONT_IMG_COUNT; i++) {
            if (g_img_front_valid[i]) {
                g_img_front_active = g_img_front_variants[i];
                return;
            }
        }
    }
    /* Pick randomly from valid variants */
    int pick = rand() % g_img_front_valid_count;
    int count = 0;
    for (int i = 0; i < FRONT_IMG_COUNT; i++) {
        if (g_img_front_valid[i]) {
            if (count == pick) {
                g_img_front_active = g_img_front_variants[i];
                ap_log("FRONT IMAGE: picked variant %d", i + 1);
                return;
            }
            count++;
        }
    }
}

static void load_device_images(void) {
    const char *pak_dir = getenv("LEDOH_PAK_DIR");
    char path[MAX_PATH_LEN];

    /* Determine filename prefix based on device */
    const char *front_prefix = g_is_brick ? "front" : "smart";

    /* Load front image variants (front1.png/smart1.png, front2.png/smart2.png, front3.png/smart3.png) */
    g_img_front_valid_count = 0;
    for (int i = 0; i < FRONT_IMG_COUNT; i++) {
        g_img_front_valid[i] = 0;
        if (pak_dir)
            snprintf(path, sizeof(path), "%s/res/%s%d.png", pak_dir, front_prefix, i + 1);
        else
            snprintf(path, sizeof(path), "res/%s%d.png", front_prefix, i + 1);

        g_img_front_variants[i] = ap_load_image(path);
        if (g_img_front_variants[i]) {
            g_img_front_valid[i] = 1;
            g_img_front_valid_count++;
            ap_log("loaded front variant %d: %s", i + 1, path);
        } else {
            ap_log("front variant %d not found: %s (skipping)", i + 1, path);
        }
    }

    /* Pick initial random front image */
    pick_random_front();

    /* Load back image (Brick only) */
    if (g_is_brick) {
        if (pak_dir)
            snprintf(path, sizeof(path), "%s/res/back.png", pak_dir);
        else
            snprintf(path, sizeof(path), "res/back.png");

        g_img_back = ap_load_image(path);
        if (g_img_back)
            ap_log("loaded back image: %s", path);
        else
            ap_log("WARNING: could not load back image: %s", path);
    }
}

/* -----------------------------------------------------------------------
 * Scaled overlay drawing helpers
 * ----------------------------------------------------------------------- */

/* Calculate device image draw rect (centered on screen, scaled to fit) */
static void calc_device_rect(int content_y, int content_h,
                              int *out_x, int *out_y, int *out_w, int *out_h,
                              float *out_scale) {
    int sw = ap_get_screen_width();
    int pad = AP_DS(5);

    /* Leave some margin */
    int max_w = sw - pad * 8;
    int max_h = content_h - pad * 4;

    float scale_w = (float)max_w / (float)g_dev_img_w;
    float scale_h = (float)max_h / (float)g_dev_img_h;
    float scale = (scale_w < scale_h) ? scale_w : scale_h;
    if (scale > 2.0f) scale = 2.0f;  /* cap scaling */

    int draw_w = (int)(g_dev_img_w * scale);
    int draw_h = (int)(g_dev_img_h * scale);
    int draw_x = (sw - draw_w) / 2;
    int draw_y = content_y + (content_h - draw_h) / 2;

    *out_x = draw_x;
    *out_y = draw_y;
    *out_w = draw_w;
    *out_h = draw_h;
    *out_scale = scale;
}

/* Get pulsing alpha for selection border (0.4 to 1.0 range) */
static uint8_t get_pulse_alpha(void) {
    Uint32 now = SDL_GetTicks();
    Uint32 elapsed = now - g_pulse_start;
    /* 1.5 second cycle */
    float t = (float)(elapsed % 1500) / 1500.0f;
    float pulse = 0.4f + 0.6f * (0.5f + 0.5f * sinf(t * 2.0f * 3.14159f));
    return (uint8_t)(pulse * 255.0f);
}

/* Draw a filled rect with alpha using SDL */
static void draw_rect_alpha(int x, int y, int w, int h,
                             uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    SDL_SetRenderDrawBlendMode(ap__g.renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(ap__g.renderer, r, g, b, a);
    SDL_Rect rect = { x, y, w, h };
    SDL_RenderFillRect(ap__g.renderer, &rect);
}

/* Draw a selection border (outline) around a rect */
static void draw_selection_border(int x, int y, int w, int h,
                                   uint8_t alpha, int thickness) {
    /* Top */
    draw_rect_alpha(x - thickness, y - thickness,
                    w + thickness * 2, thickness,
                    255, 255, 255, alpha);
    /* Bottom */
    draw_rect_alpha(x - thickness, y + h,
                    w + thickness * 2, thickness,
                    255, 255, 255, alpha);
    /* Left */
    draw_rect_alpha(x - thickness, y,
                    thickness, h,
                    255, 255, 255, alpha);
    /* Right */
    draw_rect_alpha(x + w, y,
                    thickness, h,
                    255, 255, 255, alpha);
}

/* Draw a filled triangle with alpha (scanline fill) */
static void draw_filled_triangle(int x0, int y0, int x1, int y1, int x2, int y2,
                                  uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    SDL_SetRenderDrawBlendMode(ap__g.renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(ap__g.renderer, r, g, b, a);

    /* Sort vertices by y coordinate */
    int vx[3] = {x0, x1, x2};
    int vy[3] = {y0, y1, y2};
    for (int i = 0; i < 2; i++) {
        for (int j = i + 1; j < 3; j++) {
            if (vy[j] < vy[i]) {
                int tmp;
                tmp = vx[i]; vx[i] = vx[j]; vx[j] = tmp;
                tmp = vy[i]; vy[i] = vy[j]; vy[j] = tmp;
            }
        }
    }

    /* Scanline fill */
    for (int y = vy[0]; y <= vy[2]; y++) {
        int xa, xb;
        if (y < vy[1]) {
            if (vy[1] == vy[0]) continue;
            xa = vx[0] + (vx[1] - vx[0]) * (y - vy[0]) / (vy[1] - vy[0]);
            xb = vx[0] + (vx[2] - vx[0]) * (y - vy[0]) / (vy[2] - vy[0]);
        } else {
            if (vy[2] == vy[1]) {
                xa = vx[1];
                xb = vx[2];
            } else {
                xa = vx[1] + (vx[2] - vx[1]) * (y - vy[1]) / (vy[2] - vy[1]);
                xb = vx[0] + (vx[2] - vx[0]) * (y - vy[0]) / (vy[2] - vy[0]);
            }
        }
        if (xa > xb) { int tmp = xa; xa = xb; xb = tmp; }
        SDL_RenderDrawLine(ap__g.renderer, xa, y, xb, y);
    }
}

/* Draw a triangle outline (scaled from centroid) */
static void draw_triangle_outline(int x0, int y0, int x1, int y1, int x2, int y2,
                                    int thickness,
                                    uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    SDL_SetRenderDrawBlendMode(ap__g.renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(ap__g.renderer, r, g, b, a);

    /* Scale triangle outward from centroid */
    float cx = (x0 + x1 + x2) / 3.0f;
    float cy = (y0 + y1 + y2) / 3.0f;
    float expand = 1.0f + (float)thickness * 0.3f;

    int ox0 = (int)(cx + (x0 - cx) * expand);
    int oy0 = (int)(cy + (y0 - cy) * expand);
    int ox1 = (int)(cx + (x1 - cx) * expand);
    int oy1 = (int)(cy + (y1 - cy) * expand);
    int ox2 = (int)(cx + (x2 - cx) * expand);
    int oy2 = (int)(cy + (y2 - cy) * expand);

    for (int t = 0; t < thickness; t++) {
        float s = 1.0f - (float)t / (float)(thickness > 1 ? thickness : 1) * 0.15f;
        int tx0 = (int)(cx + (ox0 - cx) * s);
        int ty0 = (int)(cy + (oy0 - cy) * s);
        int tx1 = (int)(cx + (ox1 - cx) * s);
        int ty1 = (int)(cy + (oy1 - cy) * s);
        int tx2 = (int)(cx + (ox2 - cx) * s);
        int ty2 = (int)(cy + (oy2 - cy) * s);
        SDL_RenderDrawLine(ap__g.renderer, tx0, ty0, tx1, ty1);
        SDL_RenderDrawLine(ap__g.renderer, tx1, ty1, tx2, ty2);
        SDL_RenderDrawLine(ap__g.renderer, tx2, ty2, tx0, ty0);
    }
}

/* Draw a filled ring/annulus with alpha (scanline fill) */
static void draw_filled_ring(int cx, int cy, int inner_r, int outer_r,
                              uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    SDL_SetRenderDrawBlendMode(ap__g.renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(ap__g.renderer, r, g, b, a);

    for (int dy = -outer_r; dy <= outer_r; dy++) {
        /* Calculate x span for outer circle at this y */
        float ox = sqrtf((float)(outer_r * outer_r - dy * dy));
        int outer_x1 = (int)(cx - ox);
        int outer_x2 = (int)(cx + ox);

        if (abs(dy) < inner_r) {
            /* Inside inner circle — draw two segments (left and right arcs) */
            float ix = sqrtf((float)(inner_r * inner_r - dy * dy));
            int inner_x1 = (int)(cx - ix);
            int inner_x2 = (int)(cx + ix);
            /* Left arc */
            SDL_RenderDrawLine(ap__g.renderer, outer_x1, cy + dy, inner_x1, cy + dy);
            /* Right arc */
            SDL_RenderDrawLine(ap__g.renderer, inner_x2, cy + dy, outer_x2, cy + dy);
        } else {
            /* Outside inner circle — draw full horizontal span */
            SDL_RenderDrawLine(ap__g.renderer, outer_x1, cy + dy, outer_x2, cy + dy);
        }
    }
}

/* Draw a ring outline (thin circle at given radius) */
static void draw_ring_outline(int cx, int cy, int radius, int thickness,
                               uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    draw_filled_ring(cx, cy, radius, radius + thickness, r, g, b, a);
}

/* Draw LED overlay for Brick zones */
static void draw_led_overlay_brick(int zone_idx, int img_x, int img_y, float scale,
                                    int is_selected) {
    zone_state_t *zs = &g_zone_state[zone_idx];
    uint8_t led_alpha = 180;
    int border_thick = (int)(2.0f * scale);
    if (border_thick < 2) border_thick = 4;

    if (zone_idx == 3) {
        /* LR triggers — two separate rects */
        /* Left trigger */
        int lx = img_x + (int)(LTRIG_X * scale);
        int ly = img_y + (int)(LTRIG_Y * scale);
        int lw = (int)(LTRIG_W * scale);
        int lh = (int)(LTRIG_H * scale);
        draw_rect_alpha(lx, ly, lw, lh, zs->r, zs->g, zs->b, led_alpha);

        /* Right trigger (mirrored) */
        int rx = img_x + (int)((BRICK_IMG_W - LTRIG_W - 8) * scale);
        int ry = ly;
        int rw = lw;
        int rh = lh;
        draw_rect_alpha(rx, ry, rw, rh, zs->r, zs->g, zs->b, led_alpha);

        if (is_selected) {
            uint8_t pulse_a = get_pulse_alpha();
            draw_selection_border(lx, ly, lw, lh, pulse_a, border_thick);
            draw_selection_border(rx, ry, rw, rh, pulse_a, border_thick);
        }
    } else {
        const led_overlay_t *ov = &g_brick_overlays[zone_idx];
        int ox = img_x + (int)(ov->x * scale);
        int oy = img_y + (int)(ov->y * scale);
        int ow = (int)(ov->w * scale);
        int oh = (int)(ov->h * scale);

        if (ov->rounded) {
            /* Draw rounded pill for FN buttons */
            ap_color c = { zs->r, zs->g, zs->b, led_alpha };
            ap_draw_pill(ox, oy, ow, oh, c);
        } else {
            draw_rect_alpha(ox, oy, ow, oh, zs->r, zs->g, zs->b, led_alpha);
        }

        /* Draw pill border BEHIND the fill */
        if (is_selected && ov->rounded) {
            uint8_t pulse_a = get_pulse_alpha();
            int t = border_thick;
            ap_color border_c = { 255, 255, 255, pulse_a };
            ap_draw_pill(ox - t, oy - t, ow + t * 2, oh + t * 2, border_c);
        }

        /* Draw the fill */
        if (ov->rounded) {
            ap_color c = { zs->r, zs->g, zs->b, led_alpha };
            ap_draw_pill(ox, oy, ow, oh, c);
        } else {
            draw_rect_alpha(ox, oy, ow, oh, zs->r, zs->g, zs->b, led_alpha);
        }

        /* Rectangular border drawn AFTER fill (it's outside) */
        if (is_selected && !ov->rounded) {
            uint8_t pulse_a = get_pulse_alpha();
            draw_selection_border(ox, oy, ow, oh, pulse_a, border_thick);
        }
    }
}

/* Draw LED overlay for Smart Pro zones */
static void draw_led_overlay_smartpro(int zone_idx, int img_x, int img_y, float scale,
                                       int is_selected) {
    zone_state_t *zs = &g_zone_state[zone_idx];
    uint8_t led_alpha = 180;
    int border_thick = (int)(2.0f * scale);
    if (border_thick < 2) border_thick = 4;

    const char *fn = g_zones[zone_idx].filename;

    if (strcmp(fn, "l") == 0) {
        /* Left joystick ring */
        int cx = img_x + (int)(SP_RING_L_CX * scale);
        int cy = img_y + (int)(SP_RING_L_CY * scale);
        int ir = (int)(SP_RING_L_IR * scale);
        int or_ = (int)(SP_RING_L_OR * scale);
        draw_filled_ring(cx, cy, ir, or_, zs->r, zs->g, zs->b, led_alpha);
        if (is_selected) {
            uint8_t pulse_a = get_pulse_alpha();
            draw_ring_outline(cx, cy, or_, border_thick, 0, 0, 0, pulse_a);
        }
    } else if (strcmp(fn, "r") == 0) {
        /* Right joystick ring (mirrored) */
        int cx = img_x + (int)(SP_RING_R_CX * scale);
        int cy = img_y + (int)(SP_RING_R_CY * scale);
        int ir = (int)(SP_RING_R_IR * scale);
        int or_ = (int)(SP_RING_R_OR * scale);
        draw_filled_ring(cx, cy, ir, or_, zs->r, zs->g, zs->b, led_alpha);
        if (is_selected) {
            uint8_t pulse_a = get_pulse_alpha();
            draw_ring_outline(cx, cy, or_, border_thick, 0, 0, 0, pulse_a);
        }
    } else if (strcmp(fn, "m") == 0) {
        /* Logo triangle */
        int tx0 = img_x + (int)(SP_TRI_TIP_X * scale);
        int ty0 = img_y + (int)(SP_TRI_TIP_Y * scale);
        int tx1 = img_x + (int)(SP_TRI_BL_X * scale);
        int ty1 = img_y + (int)(SP_TRI_BL_Y * scale);
        int tx2 = img_x + (int)(SP_TRI_BR_X * scale);
        int ty2 = img_y + (int)(SP_TRI_BR_Y * scale);
        draw_filled_triangle(tx0, ty0, tx1, ty1, tx2, ty2,
                             zs->r, zs->g, zs->b, led_alpha);
        if (is_selected) {
            uint8_t pulse_a = get_pulse_alpha();
            draw_triangle_outline(tx0, ty0, tx1, ty1, tx2, ty2,
                                  border_thick, 0, 0, 0, pulse_a);
        }
    }
}

/* Draw LED overlay — dispatches to device-specific function */
static void draw_led_overlay(int zone_idx, int img_x, int img_y, float scale,
                              int is_selected) {
    if (g_is_brick)
        draw_led_overlay_brick(zone_idx, img_x, img_y, scale, is_selected);
    else
        draw_led_overlay_smartpro(zone_idx, img_x, img_y, scale, is_selected);
}

/* -----------------------------------------------------------------------
 * Navigation helpers
 * ----------------------------------------------------------------------- */

/* Get first zone index in the given view */
static int first_zone_in_view(int view) {
    for (int i = 0; i < g_zone_count; i++) {
        if (g_zones[i].view == view) return i;
    }
    return 0;
}

/* Check if any zones exist in the given view */
static int has_zones_in_view(int view) {
    for (int i = 0; i < g_zone_count; i++) {
        if (g_zones[i].view == view) return 1;
    }
    return 0;
}

/* -----------------------------------------------------------------------
 * Effect names
 * ----------------------------------------------------------------------- */

#define EFFECT_COUNT 8

static const char *g_effect_names[EFFECT_COUNT] = {
    "Off",
    "Linear Rise",
    "Breathe",
    "Sniff",
    "Static",
    "Blink 1",
    "Blink 2",
    "Blink 3",
};

/* -----------------------------------------------------------------------
 * Zone settings screen (brightness, effect, speed)
 * ----------------------------------------------------------------------- */

#define ZS_ROW_BRIGHTNESS  0
#define ZS_ROW_EFFECT      1
#define ZS_ROW_SPEED       2
#define ZS_ROW_COUNT       3

static void show_zone_settings(int zone_idx) {
    int paused_anim = anim_pause_for_editing();

    zone_state_t *zs = &g_zone_state[zone_idx];
    const zone_def_t *zd = &g_zones[zone_idx];

    /* Save originals in case user cancels */
    int orig_brightness = zs->brightness;
    int orig_effect = zs->effect;
    int orig_speed = zs->speed;

    ap_log("ZONE SETTINGS: entering for zone %d/%s (brightness=%d effect=%d speed=%d)",
           zone_idx, zd->filename, zs->brightness, zs->effect, zs->speed);

    int active_row = ZS_ROW_BRIGHTNESS;
    int running = 1;
    int l1_held = 0, r1_held = 0;

    /* Determine brightness sharing note */
    const char *brightness_note = NULL;
    if (g_is_brick) {
        if (strcmp(zd->filename, "f1") == 0)
            brightness_note = "Shared with FN2";
        else if (strcmp(zd->filename, "f2") == 0)
            brightness_note = "Shared with FN1";
    } else {
        /* Smart Pro: all zones share max_scale */
        brightness_note = "Shared across all zones";
    }

    while (running) {
        ap_input_event ev;
        while (ap_poll_input(&ev)) {
            if (ev.button == AP_BTN_L1) l1_held = ev.pressed;
            if (ev.button == AP_BTN_R1) r1_held = ev.pressed;

            if (ev.pressed) {
                switch (ev.button) {
                    case AP_BTN_B:
                        if (!ev.repeated) {
                            /* Cancel — restore originals */
                            ap_log("ZONE SETTINGS: cancelled, restoring originals");
                            zs->brightness = orig_brightness;
                            zs->effect = orig_effect;
                            zs->speed = orig_speed;
                            sync_brightness_after_change(zone_idx);
                            led_apply_zone(zone_idx);
                            running = 0;
                        }
                        break;
                    case AP_BTN_A:
                        if (!ev.repeated) {
                            ap_log("ZONE SETTINGS: confirmed (brightness=%d effect=%d speed=%d)",
                                   zs->brightness, zs->effect, zs->speed);
                            running = 0;
                        }
                        break;
                    case AP_BTN_UP:
                        if (!ev.repeated) {
                            active_row--;
                            if (active_row < 0) active_row = ZS_ROW_COUNT - 1;
                        }
                        break;
                    case AP_BTN_DOWN:
                        if (!ev.repeated) {
                            active_row++;
                            if (active_row >= ZS_ROW_COUNT) active_row = 0;
                        }
                        break;
                    case AP_BTN_LEFT:
                    case AP_BTN_RIGHT: {
                        int dir = (ev.button == AP_BTN_RIGHT) ? 1 : -1;
                        int step = (l1_held || r1_held) ? 10 : 1;
                        switch (active_row) {
                            case ZS_ROW_BRIGHTNESS: {
                                int v = zs->brightness + dir * step;
                                if (v < 0) v = 0;
                                if (v > 100) v = 100;
                                zs->brightness = v;
                                sync_brightness_after_change(zone_idx);
                                led_write_brightness(zd->filename, zs->brightness);
                                break;
                            }
                            case ZS_ROW_EFFECT: {
                                int v = zs->effect + dir;
                                /* Wrap within EFFECT_MIN..EFFECT_COUNT-1 range.
                                 * Effect 0 ("Off") is not selectable — use brightness=0 instead. */
                                if (v < EFFECT_MIN) v = EFFECT_COUNT - 1;
                                if (v >= EFFECT_COUNT) v = EFFECT_MIN;
                                zs->effect = v;
                                ap_log("ZONE SETTINGS: effect changed to %d (%s)",
                                       zs->effect, g_effect_names[zs->effect]);
                                led_write_effect(zd->filename, zs->effect);
                                led_write_cycles(zd->filename, -1);
                                break;
                            }
                            case ZS_ROW_SPEED: {
                                int s = (l1_held || r1_held) ? 500 : 100;
                                int v = zs->speed + dir * s;
                                if (v < 100) v = 100;
                                if (v > 10000) v = 10000;
                                zs->speed = v;
                                led_write_speed(zd->filename, zs->speed);
                                break;
                            }
                        }
                        break;
                    }
                    case AP_BTN_L1:
                    case AP_BTN_R1:
                        /* Handled via held state */
                        break;
                    default:
                        break;
                }
            }
        }

        /* Draw */
        ap_clear_screen();
        ap_draw_background();

        int sw = ap_get_screen_width();
        int pad = AP_DS(5);

        TTF_Font *font_med   = ap_get_font(AP_FONT_MEDIUM);
        TTF_Font *font_small = ap_get_font(AP_FONT_SMALL);
        TTF_Font *font_tiny  = ap_get_font(AP_FONT_TINY);

        ap_theme *theme = ap_get_theme();
        ap_color text_color = theme->text;
        ap_color hint_color = theme->hint;
        ap_color highlight  = theme->highlight;
        ap_color hl_text    = theme->highlighted_text;

        int y = pad * 3;

        /* Title */
        char title[128];
        snprintf(title, sizeof(title), "%s Settings", zd->name);
        ap_draw_text(font_med, title, pad * 3, y, text_color);
        y += TTF_FontHeight(font_med) + pad * 2;

        /* Divider */
        ap_draw_rect(pad * 3, y, sw - pad * 6, 1, hint_color);
        y += pad * 4;

        /* Color preview */
        int swatch_size = TTF_FontHeight(font_med);
        ap_color swatch_c = { zs->r, zs->g, zs->b, 255 };
        ap_draw_rect(pad * 3, y, swatch_size, swatch_size, swatch_c);
        char hex_str[16];
        snprintf(hex_str, sizeof(hex_str), "#%02X%02X%02X", zs->r, zs->g, zs->b);
        ap_draw_text(font_small, hex_str, pad * 3 + swatch_size + pad * 2,
                     y + (swatch_size - TTF_FontHeight(font_small)) / 2, hint_color);
        y += swatch_size + pad * 4;

        /* Settings rows */
        int row_h = TTF_FontHeight(font_small) + pad * 4;
        int label_x = pad * 4;
        int value_x = sw / 2;

        for (int r = 0; r < ZS_ROW_COUNT; r++) {
            int ry = y + r * (row_h + (r == 0 && brightness_note ? TTF_FontHeight(font_tiny) + pad : 0));
            /* Adjust y offset for rows after brightness if note is present */
            if (r > 0 && brightness_note)
                ry = y + r * row_h + TTF_FontHeight(font_tiny) + pad;

            int is_active = (r == active_row);
            const char *label = "";
            char value_str[64] = {0};

            switch (r) {
                case ZS_ROW_BRIGHTNESS:
                    label = "Brightness";
                    snprintf(value_str, sizeof(value_str), "%d%%", zs->brightness);
                    break;
                case ZS_ROW_EFFECT:
                    label = "Effect";
                    if (zs->effect >= 0 && zs->effect < EFFECT_COUNT)
                        snprintf(value_str, sizeof(value_str), "%s", g_effect_names[zs->effect]);
                    else
                        snprintf(value_str, sizeof(value_str), "%d", zs->effect);
                    break;
                case ZS_ROW_SPEED:
                    label = "Speed";
                    if (zs->speed >= 1000)
                        snprintf(value_str, sizeof(value_str), "%.1fs", zs->speed / 1000.0f);
                    else
                        snprintf(value_str, sizeof(value_str), "%dms", zs->speed);
                    break;
            }

            if (is_active) {
                ap_draw_pill(pad * 2, ry, sw - pad * 4, row_h, highlight);
                ap_draw_text(font_small, label, label_x, ry + (row_h - TTF_FontHeight(font_small)) / 2, hl_text);
                ap_draw_text(font_small, value_str, value_x, ry + (row_h - TTF_FontHeight(font_small)) / 2, hl_text);
            } else {
                ap_draw_text(font_small, label, label_x, ry + (row_h - TTF_FontHeight(font_small)) / 2, text_color);
                ap_draw_text(font_small, value_str, value_x, ry + (row_h - TTF_FontHeight(font_small)) / 2, hint_color);
            }

            /* Brightness bar */
            if (r == ZS_ROW_BRIGHTNESS) {
                int bar_x = value_x;
                int bar_w = sw - bar_x - pad * 4;
                int bar_h = 6;
                int bar_y_pos = ry + row_h - bar_h - pad;
                ap_color bar_bg = { 60, 60, 65, 255 };
                ap_draw_rect(bar_x, bar_y_pos, bar_w, bar_h, bar_bg);
                int fill_w = (zs->brightness * bar_w) / 100;
                ap_color bar_fill = is_active ? hl_text : text_color;
                ap_draw_rect(bar_x, bar_y_pos, fill_w, bar_h, bar_fill);

                /* Brightness sharing note */
                if (brightness_note) {
                    int note_y = ry + row_h + pad;
                    ap_draw_text(font_tiny, brightness_note, label_x + pad, note_y, hint_color);
                }
            }
        }

        /* Hints */
        pakkit_hint hints[] = {
            { .button = "B", .label = "Cancel" },
            { .button = "L/R", .label = "Adjust" },
            { .button = "L1+L/R", .label = "Fast" },
            { .button = "A", .label = "Confirm" },
        };
        pakkit_draw_hints(hints, 4);

        ap_present();
    }

    if (paused_anim >= 0)
        anim_resume_after_editing(paused_anim);
}

/* -----------------------------------------------------------------------
 * HSL to RGB conversion
 * ----------------------------------------------------------------------- */

static float hsl_hue2rgb(float p, float q, float t) {
    if (t < 0.0f) t += 1.0f;
    if (t > 1.0f) t -= 1.0f;
    if (t < 1.0f / 6.0f) return p + (q - p) * 6.0f * t;
    if (t < 1.0f / 2.0f) return q;
    if (t < 2.0f / 3.0f) return p + (q - p) * (2.0f / 3.0f - t) * 6.0f;
    return p;
}

static void hsl_to_rgb(float h, float s, float l,
                        uint8_t *r, uint8_t *g, uint8_t *b) {
    if (s <= 0.0f) {
        uint8_t v = (uint8_t)(l * 255.0f);
        *r = *g = *b = v;
        return;
    }
    float q = (l < 0.5f) ? (l * (1.0f + s)) : (l + s - l * s);
    float p = 2.0f * l - q;
    float rf = hsl_hue2rgb(p, q, h + 1.0f / 3.0f);
    float gf = hsl_hue2rgb(p, q, h);
    float bf = hsl_hue2rgb(p, q, h - 1.0f / 3.0f);
    *r = (uint8_t)(rf * 255.0f);
    *g = (uint8_t)(gf * 255.0f);
    *b = (uint8_t)(bf * 255.0f);
}

static void rgb_to_hsl(uint8_t r, uint8_t g, uint8_t b,
                        float *h, float *s, float *l) {
    float rf = r / 255.0f, gf = g / 255.0f, bf = b / 255.0f;
    float max = rf > gf ? (rf > bf ? rf : bf) : (gf > bf ? gf : bf);
    float min = rf < gf ? (rf < bf ? rf : bf) : (gf < bf ? gf : bf);
    float d = max - min;
    *l = (max + min) / 2.0f;
    if (d < 0.001f) {
        *h = 0.0f;
        *s = 0.0f;
        return;
    }
    *s = (*l > 0.5f) ? (d / (2.0f - max - min)) : (d / (max + min));
    if (max == rf) {
        *h = (gf - bf) / d + (gf < bf ? 6.0f : 0.0f);
    } else if (max == gf) {
        *h = (bf - rf) / d + 2.0f;
    } else {
        *h = (rf - gf) / d + 4.0f;
    }
    *h /= 6.0f;
}

/* -----------------------------------------------------------------------
 * Color picker screen
 * ----------------------------------------------------------------------- */

static void show_color_picker(int zone_idx) {
    int paused_anim = anim_pause_for_editing();

    zone_state_t *zs = &g_zone_state[zone_idx];
    const zone_def_t *zd = &g_zones[zone_idx];

    /* Save original color in case user cancels */
    uint8_t orig_r = zs->r, orig_g = zs->g, orig_b = zs->b;

    ap_log("COLOR PICKER: entering for zone %d/%s (r=%d g=%d b=%d, effect=%d)",
           zone_idx, zd->filename, zs->r, zs->g, zs->b, zs->effect);

    /* Force static effect during color picking so color is visible */
    ap_log("COLOR PICKER: forcing effect=4 (static) and brightness=%d for zone %s",
           zs->brightness > 0 ? zs->brightness : 100, zd->filename);
    led_write_effect(zd->filename, 4);
    led_write_brightness(zd->filename, zs->brightness > 0 ? zs->brightness : 100);

    /* Convert current color to HSL to find initial cursor position */
    float init_h, init_s, init_l;
    rgb_to_hsl(zs->r, zs->g, zs->b, &init_h, &init_s, &init_l);
    ap_log("COLOR PICKER: initial HSL: h=%.3f s=%.3f l=%.3f", init_h, init_s, init_l);

    int sw = ap_get_screen_width();
    int sh = ap_get_screen_height();
    int pad = AP_DS(5);

    TTF_Font *font_med   = ap_get_font(AP_FONT_MEDIUM);
    TTF_Font *font_tiny  = ap_get_font(AP_FONT_TINY);

    int hint_h = TTF_FontHeight(font_tiny) + pad * 2;
    int header_h = TTF_FontHeight(font_med) + pad * 2 + 1 + pad * 2;

    /* Color field dimensions */
    int field_x = pad * 2;
    int field_y = pad + header_h;
    int field_w = sw - pad * 4;
    int field_h = sh - field_y - hint_h - pad;

    /* Cursor position in field coordinates (0 to field_w-1, 0 to field_h-1) */
    /* X = hue, Y: top=white(L=1), middle=saturated(L=0.5), bottom=black(L=0) */
    int cursor_x = (int)(init_h * (field_w - 1));
    int cursor_y;
    if (init_l >= 0.5f) {
        /* Map L 1.0..0.5 to Y 0..field_h/2 */
        cursor_y = (int)((1.0f - init_l) * 2.0f * (field_h / 2));
    } else {
        /* Map L 0.5..0.0 to Y field_h/2..field_h */
        cursor_y = field_h / 2 + (int)((0.5f - init_l) * 2.0f * (field_h / 2));
    }
    if (cursor_x < 0) cursor_x = 0;
    if (cursor_x >= field_w) cursor_x = field_w - 1;
    if (cursor_y < 0) cursor_y = 0;
    if (cursor_y >= field_h) cursor_y = field_h - 1;

    /* Build the color field texture */
    SDL_Texture *field_tex = SDL_CreateTexture(ap__g.renderer,
        SDL_PIXELFORMAT_RGB24, SDL_TEXTUREACCESS_STREAMING, field_w, field_h);

    /* Open joystick once for the duration of the color picker */
    SDL_Joystick *joy = (SDL_NumJoysticks() > 0) ? SDL_JoystickOpen(0) : NULL;

    int running = 1;
    int field_dirty = 1;  /* rebuild texture on first frame */
    int cursor_speed = 2;
    int move_count = 0;

    while (running) {
        ap_input_event ev;
        while (ap_poll_input(&ev)) {
            if (ev.pressed) {
                switch (ev.button) {
                    case AP_BTN_B:
                        if (!ev.repeated) {
                            ap_log("COLOR PICKER: cancelled, restoring original color #%02X%02X%02X",
                                   orig_r, orig_g, orig_b);
                            zs->r = orig_r;
                            zs->g = orig_g;
                            zs->b = orig_b;
                            led_apply_color_only(zone_idx);
                            running = 0;
                        }
                        break;
                    case AP_BTN_A:
                        if (!ev.repeated) {
                            /* If the zone's effect was Off (0), upgrade to Static (4)
                             * so the picked color is actually visible */
                            if (zs->effect < EFFECT_MIN) {
                                ap_log("COLOR PICKER: effect was %d (Off), upgrading to 4 (Static)",
                                       zs->effect);
                                zs->effect = 4;
                            }
                            ap_log("COLOR PICKER: confirmed color #%02X%02X%02X",
                                   zs->r, zs->g, zs->b);
                            running = 0;
                        }
                        break;
                    default:
                        break;
                }
            }
        }

        /* Check d-pad held state via SDL joystick for smooth diagonal movement */
        int dx = 0, dy = 0;

        if (joy) {
            /* D-pad via hat */
            if (SDL_JoystickNumHats(joy) > 0) {
                Uint8 hat = SDL_JoystickGetHat(joy, 0);
                if (hat & SDL_HAT_LEFT)  dx -= cursor_speed;
                if (hat & SDL_HAT_RIGHT) dx += cursor_speed;
                if (hat & SDL_HAT_UP)    dy -= cursor_speed;
                if (hat & SDL_HAT_DOWN)  dy += cursor_speed;
            }
            /* Also check analog stick with deadzone */
            Sint16 ax = SDL_JoystickGetAxis(joy, 0);
            Sint16 ay = SDL_JoystickGetAxis(joy, 1);
            if (ax < -8000) dx -= cursor_speed;
            if (ax >  8000) dx += cursor_speed;
            if (ay < -8000) dy -= cursor_speed;
            if (ay >  8000) dy += cursor_speed;
        }

        /* Keyboard fallback for dev mode */
        {
            const Uint8 *keys = SDL_GetKeyboardState(NULL);
            if (keys[SDL_SCANCODE_LEFT])  dx -= cursor_speed;
            if (keys[SDL_SCANCODE_RIGHT]) dx += cursor_speed;
            if (keys[SDL_SCANCODE_UP])    dy -= cursor_speed;
            if (keys[SDL_SCANCODE_DOWN])  dy += cursor_speed;
        }

        if (dx != 0 || dy != 0) {
            cursor_x += dx;
            cursor_y += dy;
            if (cursor_x < 0) cursor_x = 0;
            if (cursor_x >= field_w) cursor_x = field_w - 1;
            if (cursor_y < 0) cursor_y = 0;
            if (cursor_y >= field_h) cursor_y = field_h - 1;

            /* Convert cursor position to color */
            float h = (float)cursor_x / (float)(field_w - 1);
            float l;
            int mid = field_h / 2;
            if (cursor_y <= mid) {
                l = 1.0f - ((float)cursor_y / (float)mid) * 0.5f;
            } else {
                l = 0.5f - ((float)(cursor_y - mid) / (float)(field_h - mid)) * 0.5f;
            }
            float s = 1.0f;
            hsl_to_rgb(h, s, l, &zs->r, &zs->g, &zs->b);

            move_count++;
            /* Log every 30th move to keep logs manageable */
            if (move_count % 30 == 1) {
                ap_log("COLOR PICKER: cursor move #%d → (%d,%d) h=%.2f l=%.2f → #%02X%02X%02X",
                       move_count, cursor_x, cursor_y, h, l, zs->r, zs->g, zs->b);
            }

            led_apply_color_only(zone_idx);
        }

        /* Build color field texture (only once, it's static) */
        if (field_dirty && field_tex) {
            void *pixels;
            int pitch;
            if (SDL_LockTexture(field_tex, NULL, &pixels, &pitch) == 0) {
                for (int fy = 0; fy < field_h; fy++) {
                    uint8_t *row = (uint8_t *)pixels + fy * pitch;
                    int mid = field_h / 2;
                    float l;
                    if (fy <= mid) {
                        l = 1.0f - ((float)fy / (float)mid) * 0.5f;
                    } else {
                        l = 0.5f - ((float)(fy - mid) / (float)(field_h - mid)) * 0.5f;
                    }
                    for (int fx = 0; fx < field_w; fx++) {
                        float h = (float)fx / (float)(field_w - 1);
                        uint8_t pr, pg, pb;
                        hsl_to_rgb(h, 1.0f, l, &pr, &pg, &pb);
                        row[fx * 3 + 0] = pr;
                        row[fx * 3 + 1] = pg;
                        row[fx * 3 + 2] = pb;
                    }
                }
                SDL_UnlockTexture(field_tex);
                field_dirty = 0;
            }
        }

        /* Draw */
        ap_clear_screen();
        ap_draw_background();

        ap_theme *theme = ap_get_theme();
        ap_color text_color = theme->text;
        ap_color hint_color = theme->hint;

        /* Header: zone name + hex color */
        int y = pad;
        ap_draw_text(font_med, zd->name, pad * 3, y, text_color);
        char hex_str[16];
        snprintf(hex_str, sizeof(hex_str), "#%02X%02X%02X", zs->r, zs->g, zs->b);
        int hex_w = ap_measure_text(font_med, hex_str);
        ap_color preview_color = { zs->r, zs->g, zs->b, 255 };
        ap_draw_text(font_med, hex_str, sw - hex_w - pad * 3, y, preview_color);
        y += TTF_FontHeight(font_med) + pad;
        ap_draw_rect(pad * 2, y, sw - pad * 4, 1, hint_color);
        y += pad;

        /* Color field */
        if (field_tex) {
            SDL_Rect dst = { field_x, field_y, field_w, field_h };
            SDL_RenderCopy(ap__g.renderer, field_tex, NULL, &dst);
        }

        /* Cursor crosshair */
        int cx = field_x + cursor_x;
        int cy = field_y + cursor_y;
        int cross_size = AP_DS(8);
        int cross_thick = 2;

        /* Black outline for visibility on any background */
        draw_rect_alpha(cx - cross_size - 1, cy - 1, cross_size * 2 + 3, cross_thick + 2,
                        0, 0, 0, 180);
        draw_rect_alpha(cx - 1, cy - cross_size - 1, cross_thick + 2, cross_size * 2 + 3,
                        0, 0, 0, 180);
        /* White cross */
        draw_rect_alpha(cx - cross_size, cy, cross_size * 2 + 1, cross_thick,
                        255, 255, 255, 255);
        draw_rect_alpha(cx, cy - cross_size, cross_thick, cross_size * 2 + 1,
                        255, 255, 255, 255);

        /* Small color preview square next to cursor */
        int prev_size = AP_DS(12);
        int prev_x = cx + cross_size + pad;
        int prev_y = cy - prev_size / 2;
        /* Keep preview on screen */
        if (prev_x + prev_size > sw - pad) prev_x = cx - cross_size - pad - prev_size;
        if (prev_y < field_y) prev_y = field_y;
        if (prev_y + prev_size > field_y + field_h) prev_y = field_y + field_h - prev_size;
        ap_draw_rect(prev_x, prev_y, prev_size, prev_size, preview_color);
        draw_rect_alpha(prev_x - 1, prev_y - 1, prev_size + 2, 1, 255, 255, 255, 180);
        draw_rect_alpha(prev_x - 1, prev_y + prev_size, prev_size + 2, 1, 255, 255, 255, 180);
        draw_rect_alpha(prev_x - 1, prev_y, 1, prev_size, 255, 255, 255, 180);
        draw_rect_alpha(prev_x + prev_size, prev_y, 1, prev_size, 255, 255, 255, 180);

        /* Hints */
        pakkit_hint hints[] = {
            { .button = "B", .label = "Cancel" },
            { .button = "D-pad", .label = "Pick" },
            { .button = "A", .label = "Confirm" },
        };
        pakkit_draw_hints(hints, 3);

        ap_present();
    }

    /* Close joystick */
    if (joy) SDL_JoystickClose(joy);

    if (field_tex) SDL_DestroyTexture(field_tex);

    /* Re-apply full zone state (restores effect, speed, etc.) */
    ap_log("COLOR PICKER: exiting, re-applying full zone state for zone %d/%s", zone_idx, zd->filename);
    ap_log("COLOR PICKER: final state: r=%d g=%d b=%d effect=%d brightness=%d speed=%d",
           zs->r, zs->g, zs->b, zs->effect, zs->brightness, zs->speed);
    led_apply_zone(zone_idx);

    if (paused_anim >= 0)
        anim_resume_after_editing(paused_anim);
}

/* -----------------------------------------------------------------------
 * Animations menu (Brick only)
 * ----------------------------------------------------------------------- */

static void show_animations_menu(void) {
    /* Build list items: "Off" + all animations */
    int item_count = g_anim_count + 1;
    pakkit_list_item items[g_anim_count + 1];
    char labels[g_anim_count + 1][128];

    int running_idx = anim_get_running_index();

    /* Determine initial cursor position */
    int initial_idx = 0;  /* default to "Off" */
    if (running_idx >= 0) {
        initial_idx = running_idx + 1;  /* +1 because "Off" is index 0 */
    }

    /* First item: Off */
    if (running_idx < 0 && !anim_is_running()) {
        snprintf(labels[0], sizeof(labels[0]), "Off  \xe2\x9c\x93");
    } else {
        snprintf(labels[0], sizeof(labels[0]), "Off");
    }
    items[0].label = labels[0];

    /* Animation items */
    for (int i = 0; i < g_anim_count; i++) {
        if (i == running_idx) {
            snprintf(labels[i + 1], sizeof(labels[i + 1]), "%s  \xe2\x9c\x93",
                     g_animations[i].name);
        } else {
            snprintf(labels[i + 1], sizeof(labels[i + 1]), "%s",
                     g_animations[i].name);
        }
        items[i + 1].label = labels[i + 1];
    }

    pakkit_hint hints[] = {
        { .button = "B", .label = "Back" },
        { .button = "A", .label = "Select" },
    };

    pakkit_list_opts opts = {
        .title = "Animations",
        .hints = hints,
        .hint_count = 2,
        .secondary_button = AP_BTN_NONE,
        .tertiary_button = AP_BTN_NONE,
        .initial_index = initial_idx,
    };

    pakkit_list_result result;
    int rc = pakkit_list(&opts, items, item_count, &result);
    if (rc != AP_OK) return;

    if (result.selected_index == 0) {
        if (anim_is_running()) {
            ap_log("ANIM MENU: user selected Off, stopping animation");
            anim_stop();
            anim_save_config(-1);
            g_led_mode = MODE_STATIC;
            for (int i = 0; i < g_zone_count; i++)
                led_apply_zone(i);
            pakkit_message("Animation stopped", "OK");
        }
    } else {
        int anim_idx = result.selected_index - 1;
        ap_log("ANIM MENU: user selected %s", g_animations[anim_idx].name);

        if (anim_idx == running_idx) {
            ap_log("ANIM MENU: %s is already running", g_animations[anim_idx].name);
            return;
        }

        anim_start(anim_idx);
        anim_save_config(anim_idx);
        g_led_mode = MODE_ANIMATION;

        char msg[128];
        snprintf(msg, sizeof(msg), "%s started!", g_animations[anim_idx].name);
        pakkit_message(msg, "OK");
    }
}

/* -----------------------------------------------------------------------
 * Menu screen (Y button)
 * ----------------------------------------------------------------------- */

static void show_menu(void) {
    char zone_settings_label[128];
    snprintf(zone_settings_label, sizeof(zone_settings_label), "%s Settings", g_zones[g_selected_zone].name);

    /* Build menu items — animations only on Brick when scripts are available.
     * When an animation is active, hide zone settings/reset (they're irrelevant). */
    if (g_is_brick && g_anim_count > 0) {
        int anim_active = (g_led_mode == MODE_ANIMATION);
        char anim_label[128];
        if (anim_active) {
            snprintf(anim_label, sizeof(anim_label), "Animations  \xe2\x9c\x93");
        } else {
            snprintf(anim_label, sizeof(anim_label), "Animations");
        }

        if (anim_active) {
            pakkit_menu_item items[] = {
                { .label = anim_label },
                { .label = "About" },
            };
            pakkit_menu_result result;
            int rc = pakkit_menu("Menu", items, 2, &result);
            if (rc != AP_OK) return;

            switch (result.selected_index) {
                case 0: show_animations_menu(); break;
                case 1: {
                    pakkit_info_pair info[] = {
                        { .key = "Version", .value = LEDOH_VERSION },
                        { .key = "Platform", .value = AP_PLATFORM_NAME },
                        { .key = "UI", .value = "PakKit" },
                        { .key = "License", .value = "MIT" },
                    };
                    const char *credits[] = {
                        "LED'oh! by Eric Reinsmidt",
                        "Built with Apostrophe",
                        "For NextUI by LoveRetro",
                    };
                    pakkit_detail_opts opts = {
                        .title = "LED'oh!",
                        .subtitle = "LED color controller for NextUI",
                        .info = info, .info_count = 4,
                        .credits = credits, .credit_count = 3,
                    };
                    pakkit_detail_screen(&opts);
                    break;
                }
            }
        } else {
            pakkit_menu_item items[] = {
                { .label = zone_settings_label },
                { .label = anim_label },
                { .label = "Reset This Zone" },
                { .label = "Reset All Zones" },
                { .label = "About" },
            };
            pakkit_menu_result result;
            int rc = pakkit_menu("Menu", items, 5, &result);
            if (rc != AP_OK) return;

            switch (result.selected_index) {
                case 0: {
                    show_zone_settings(g_selected_zone);
                    break;
                }
                case 1: {
                    show_animations_menu();
                    break;
                }
                case 2: {
                    char msg[128];
                    snprintf(msg, sizeof(msg), "Reset %s to white?", g_zones[g_selected_zone].name);
                    if (pakkit_confirm(msg, "Reset", "Cancel")) {
                        ap_log("MENU: resetting zone %d/%s to defaults (preserving color2/trigger/inbrightness)",
                               g_selected_zone, g_zones[g_selected_zone].filename);
                        zone_state_t *zs = &g_zone_state[g_selected_zone];
                        uint8_t saved_r2 = zs->r2, saved_g2 = zs->g2, saved_b2 = zs->b2;
                        int saved_trigger = zs->trigger;
                        int saved_inbrightness = zs->inbrightness;
                        *zs = (zone_state_t){
                            .r = 255, .g = 255, .b = 255,
                            .r2 = saved_r2, .g2 = saved_g2, .b2 = saved_b2,
                            .effect = 4, .speed = 1000, .brightness = 100,
                            .trigger = saved_trigger, .inbrightness = saved_inbrightness,
                        };
                        sync_brightness_after_change(g_selected_zone);
                        led_apply_zone(g_selected_zone);
                    }
                    break;
                }
                case 3: {
                    if (pakkit_confirm("Reset all zones to white?", "Reset All", "Cancel")) {
                        ap_log("MENU: resetting all zones to defaults (preserving color2/trigger/inbrightness)");
                        for (int i = 0; i < g_zone_count; i++) {
                            zone_state_t *zs = &g_zone_state[i];
                            uint8_t saved_r2 = zs->r2, saved_g2 = zs->g2, saved_b2 = zs->b2;
                            int saved_trigger = zs->trigger;
                            int saved_inbrightness = zs->inbrightness;
                            *zs = (zone_state_t){
                                .r = 255, .g = 255, .b = 255,
                                .r2 = saved_r2, .g2 = saved_g2, .b2 = saved_b2,
                                .effect = 4, .speed = 1000, .brightness = 100,
                                .trigger = saved_trigger, .inbrightness = saved_inbrightness,
                            };
                        }
                        for (int i = 0; i < g_zone_count; i++)
                            led_apply_zone(i);
                    }
                    break;
                }
                case 4: {
                    pakkit_info_pair info[] = {
                        { .key = "Version", .value = LEDOH_VERSION },
                        { .key = "Platform", .value = AP_PLATFORM_NAME },
                        { .key = "UI", .value = "PakKit" },
                        { .key = "License", .value = "MIT" },
                    };
                    const char *credits[] = {
                        "LED'oh! by Eric Reinsmidt",
                        "Built with Apostrophe",
                        "For NextUI by LoveRetro",
                    };
                    pakkit_detail_opts opts = {
                        .title = "LED'oh!",
                        .subtitle = "LED color controller for NextUI",
                        .info = info, .info_count = 4,
                        .credits = credits, .credit_count = 3,
                    };
                    pakkit_detail_screen(&opts);
                    break;
                }
            }
        }
    } else {
        /* Smart Pro — no animations menu */
        pakkit_menu_item items[] = {
            { .label = zone_settings_label },
            { .label = "Reset This Zone" },
            { .label = "Reset All Zones" },
            { .label = "About" },
        };
        pakkit_menu_result result;
        int rc = pakkit_menu("Menu", items, 4, &result);
        if (rc != AP_OK) return;

        switch (result.selected_index) {
            case 0: {
                show_zone_settings(g_selected_zone);
                break;
            }
            case 1: {
                /* Reset selected zone */
                char msg[128];
                snprintf(msg, sizeof(msg), "Reset %s to white?", g_zones[g_selected_zone].name);
                if (pakkit_confirm(msg, "Reset", "Cancel")) {
                    ap_log("MENU: resetting zone %d/%s to defaults",
                           g_selected_zone, g_zones[g_selected_zone].filename);
                    zone_state_t *zs = &g_zone_state[g_selected_zone];
                    uint8_t saved_r2 = zs->r2, saved_g2 = zs->g2, saved_b2 = zs->b2;
                    int saved_trigger = zs->trigger;
                    int saved_inbrightness = zs->inbrightness;
                    *zs = (zone_state_t){
                        .r = 255, .g = 255, .b = 255,
                        .r2 = saved_r2, .g2 = saved_g2, .b2 = saved_b2,
                        .effect = 4, .speed = 1000, .brightness = 100,
                        .trigger = saved_trigger, .inbrightness = saved_inbrightness,
                    };
                    sync_brightness_after_change(g_selected_zone);
                    led_apply_zone(g_selected_zone);
                }
                break;
            }
            case 2: {
                if (pakkit_confirm("Reset all zones to white?", "Reset All", "Cancel")) {
                    ap_log("MENU: resetting all zones to defaults");
                    for (int i = 0; i < g_zone_count; i++) {
                        zone_state_t *zs = &g_zone_state[i];
                        uint8_t saved_r2 = zs->r2, saved_g2 = zs->g2, saved_b2 = zs->b2;
                        int saved_trigger = zs->trigger;
                        int saved_inbrightness = zs->inbrightness;
                        *zs = (zone_state_t){
                            .r = 255, .g = 255, .b = 255,
                            .r2 = saved_r2, .g2 = saved_g2, .b2 = saved_b2,
                            .effect = 4, .speed = 1000, .brightness = 100,
                            .trigger = saved_trigger, .inbrightness = saved_inbrightness,
                        };
                    }
                    for (int i = 0; i < g_zone_count; i++)
                        led_apply_zone(i);
                }
                break;
            }
            case 3: {
                pakkit_info_pair info[] = {
                    { .key = "Version", .value = LEDOH_VERSION },
                    { .key = "Platform", .value = AP_PLATFORM_NAME },
                    { .key = "UI", .value = "PakKit" },
                    { .key = "License", .value = "MIT" },
                };
                const char *credits[] = {
                    "LED'oh! by Eric Reinsmidt",
                    "Built with Apostrophe",
                    "For NextUI by LoveRetro",
                };
                pakkit_detail_opts opts = {
                    .title = "LED'oh!",
                    .subtitle = "LED color controller for NextUI",
                    .info = info, .info_count = 4,
                    .credits = credits, .credit_count = 3,
                };
                pakkit_detail_screen(&opts);
                break;
            }
        }
    }
}

/* -----------------------------------------------------------------------
 * Device view screen (main screen)
 * ----------------------------------------------------------------------- */

static void show_device_view(void) {
    int running = 1;
    g_pulse_start = SDL_GetTicks();

    while (running) {
        ap_input_event ev;
        while (ap_poll_input(&ev)) {
            if (ev.pressed) {
                switch (ev.button) {
                    case AP_BTN_B:
                        if (!ev.repeated) {
                            /* In animation mode, don't save — the settings file
                             * intentionally has black colors to prevent blips.
                             * The real colors are safe in the backup file. */
                            if (g_led_mode != MODE_ANIMATION) {
                                ap_log("QUIT: saving settings");
                                save_settings();
                            }
                            running = 0;
                        }
                        break;
                    case AP_BTN_A:
                        if (!ev.repeated) {
                            show_color_picker(g_selected_zone);
                        }
                        break;
                    case AP_BTN_LEFT:
                        if (!ev.repeated) {
                            if (g_is_brick) {
                                /* Brick: L/R only on front view */
                                if (g_current_view == VIEW_FRONT) {
                                    int first = first_zone_in_view(VIEW_FRONT);
                                    if (g_selected_zone != first) {
                                        g_selected_zone = first;
                                        g_pulse_start = SDL_GetTicks();
                                    }
                                }
                            } else {
                                /* Smart Pro: cycle through all zones */
                                if (g_selected_zone > 0) {
                                    g_selected_zone--;
                                    g_pulse_start = SDL_GetTicks();
                                }
                            }
                        }
                        break;
                    case AP_BTN_RIGHT:
                        if (!ev.repeated) {
                            if (g_is_brick) {
                                if (g_current_view == VIEW_FRONT) {
                                    int last = -1;
                                    for (int i = g_zone_count - 1; i >= 0; i--) {
                                        if (g_zones[i].view == VIEW_FRONT) { last = i; break; }
                                    }
                                    if (last >= 0 && g_selected_zone != last) {
                                        g_selected_zone = last;
                                        g_pulse_start = SDL_GetTicks();
                                    }
                                }
                            } else {
                                /* Smart Pro: cycle through all zones */
                                if (g_selected_zone < g_zone_count - 1) {
                                    g_selected_zone++;
                                    g_pulse_start = SDL_GetTicks();
                                }
                            }
                        }
                        break;
                    case AP_BTN_UP:
                        if (!ev.repeated && g_is_brick && g_current_view == VIEW_BACK) {
                            int first = first_zone_in_view(VIEW_BACK);
                            if (g_selected_zone != first) {
                                g_selected_zone = first;
                                g_pulse_start = SDL_GetTicks();
                            }
                        }
                        break;
                    case AP_BTN_DOWN:
                        if (!ev.repeated && g_is_brick && g_current_view == VIEW_BACK) {
                            int last = -1;
                            for (int i = g_zone_count - 1; i >= 0; i--) {
                                if (g_zones[i].view == VIEW_BACK) { last = i; break; }
                            }
                            if (last >= 0 && g_selected_zone != last) {
                                g_selected_zone = last;
                                g_pulse_start = SDL_GetTicks();
                            }
                        }
                        break;
                    case AP_BTN_L1:
                    case AP_BTN_R1:
                        if (!ev.repeated) {
                            int target_view = (g_current_view == VIEW_FRONT) ? VIEW_BACK : VIEW_FRONT;
                            /* Only flip if the target view has zones */
                            if (has_zones_in_view(target_view)) {
                                g_current_view = target_view;
                                g_selected_zone = first_zone_in_view(g_current_view);
                                g_pulse_start = SDL_GetTicks();
                                /* Pick a new random front image when flipping to front */
                                if (g_current_view == VIEW_FRONT)
                                    pick_random_front();
                            }
                        }
                        break;
                    case AP_BTN_X:
                        /* X is unused — save happens on quit */
                        break;
                    case AP_BTN_Y:
                        if (!ev.repeated) {
                            show_menu();
                        }
                        break;
                    case AP_BTN_MENU:
                        /* Menu/Select button unused */
                        break;
                    default:
                        break;
                }
            }
        }

        /* Draw */
        ap_clear_screen();
        ap_draw_background();

        int sh = ap_get_screen_height();
        int pad = AP_DS(5);

        TTF_Font *font_tiny  = ap_get_font(AP_FONT_TINY);

        int hint_h = TTF_FontHeight(font_tiny) + pad * 2;

        /* Full screen for image: top pad to hint bar */
        int content_y = pad;
        int content_h = sh - content_y - hint_h - pad;

        SDL_Texture *img = (g_current_view == VIEW_FRONT) ? g_img_front_active : g_img_back;

        int img_x, img_y, img_w, img_h;
        float img_scale;
        calc_device_rect(content_y, content_h, &img_x, &img_y, &img_w, &img_h, &img_scale);

        if (img) {
            ap_draw_image(img, img_x, img_y, img_w, img_h);
        } else {
            /* Fallback: draw a placeholder rect */
            ap_color placeholder = { 50, 50, 55, 255 };
            ap_draw_rect(img_x, img_y, img_w, img_h, placeholder);
        }

        /* Draw LED overlays for zones in current view */
        for (int i = 0; i < g_zone_count; i++) {
            if (g_zones[i].view == g_current_view) {
                draw_led_overlay(i, img_x, img_y, img_scale,
                                 (i == g_selected_zone));
            }
        }

        /* Hints — device-specific layout */
        if (g_is_brick) {
            if (g_current_view == VIEW_FRONT) {
                pakkit_hint hints[] = {
                    { .button = "B", .label = "Quit" },
                    { .button = "L/R", .label = "Select" },
                    { .button = "L1", .label = "Flip" },
                    { .button = "Y", .label = "Menu" },
                    { .button = "A", .label = "Edit" },
                };
                pakkit_draw_hints(hints, 5);
            } else {
                pakkit_hint hints[] = {
                    { .button = "B", .label = "Quit" },
                    { .button = "U/D", .label = "Select" },
                    { .button = "L1", .label = "Flip" },
                    { .button = "Y", .label = "Menu" },
                    { .button = "A", .label = "Edit" },
                };
                pakkit_draw_hints(hints, 5);
            }
        } else {
            pakkit_hint hints[] = {
                { .button = "B", .label = "Quit" },
                { .button = "L/R", .label = "Select" },
                { .button = "Y", .label = "Menu" },
                { .button = "A", .label = "Edit" },
            };
            pakkit_draw_hints(hints, 4);
        }

        ap_present();
    }
}

/* -----------------------------------------------------------------------
 * Main
 * ----------------------------------------------------------------------- */

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    /* Seed random number generator for front image variants */
    srand((unsigned int)time(NULL));

    /* Truncate log */
    const char *log_dir = getenv("LEDOH_LOG_DIR");
    char log_path[MAX_PATH_LEN] = {0};
    if (log_dir) {
        snprintf(log_path, sizeof(log_path), "%s/ledoh.txt", log_dir);
        mkdir(log_dir, 0755);
        FILE *lf = fopen(log_path, "w");
        if (lf) fclose(lf);
    }

    ap_config cfg = {
        .window_title       = "LED'oh!",
        .log_path           = log_path[0] ? log_path : NULL,
        .is_nextui          = AP_PLATFORM_IS_DEVICE,
        .disable_background = true,
    };
    if (ap_init(&cfg) != AP_OK) {
        fprintf(stderr, "Failed to initialise Apostrophe\n");
        return 1;
    }

    ap_set_power_handler(false);

    ap_theme *theme = ap_get_theme();
    theme->background = (ap_color){ DEFAULT_BG_R, DEFAULT_BG_G, DEFAULT_BG_B, 255 };
    theme->text       = (ap_color){ DEFAULT_TEXT_R, DEFAULT_TEXT_G, DEFAULT_TEXT_B, 255 };
    theme->hint       = (ap_color){ DEFAULT_HINT_R, DEFAULT_HINT_G, DEFAULT_HINT_B, 255 };

    ap_log("=== LED'oh! v%s starting ===", LEDOH_VERSION);

    /* Detect device type — must happen before settings path and zone setup */
    char *device = getenv("DEVICE");
    ap_log("STARTUP: DEVICE env = %s", device ? device : "(null)");
    if (device && strcmp(device, "brick") == 0) {
        g_is_brick = 1;
        g_zones = g_brick_zones;
        g_zone_count = MAX_ZONES;
        g_dev_img_w = BRICK_IMG_W;
        g_dev_img_h = BRICK_IMG_H;
        snprintf(g_settings_path, sizeof(g_settings_path),
                 "/mnt/SDCARD/.userdata/shared/ledsettings_brick.txt");
    } else {
        g_is_brick = 0;
        g_zones = g_smartpro_zones;
        g_zone_count = SP_ZONE_COUNT;
        g_dev_img_w = SP_IMG_W;
        g_dev_img_h = SP_IMG_H;
        snprintf(g_settings_path, sizeof(g_settings_path),
                 "/mnt/SDCARD/.userdata/shared/ledsettings.txt");
    }
    ap_log("STARTUP: is_brick = %d, zone_count = %d", g_is_brick, g_zone_count);
    ap_log("STARTUP: settings path = %s", g_settings_path);

    /* Discover animation scripts (Brick only) */
    if (g_is_brick)
        anim_scan_scripts();

    /* Load device images */
    load_device_images();

    /* Load settings */
    load_settings();

    /* Check for persisted animation config — auto-launch if configured and not already running */
    if (g_is_brick && !anim_is_running()) {
        int saved_anim = anim_load_config();
        if (saved_anim >= 0) {
            ap_log("STARTUP: auto-launching saved animation: %s", g_animations[saved_anim].name);
            anim_start(saved_anim);
            g_led_mode = MODE_ANIMATION;
        } else {
            /* No animation to launch — if a backup exists, the previous animation
             * died while the app was closed.  Restore the real settings. */
            if (settings_restore_backup())
                ap_log("STARTUP: recovered real settings from animation backup");
        }
    } else if (g_is_brick && anim_is_running()) {
        g_led_mode = MODE_ANIMATION;
    }

    /* Apply current settings to hardware (skip if animation daemon owns the LEDs) */
    if (g_led_mode == MODE_ANIMATION) {
        ap_log("STARTUP: animation running, skipping hardware apply");
    } else {
        ap_log("STARTUP: applying loaded settings to hardware (%d zones)", g_zone_count);
        for (int i = 0; i < g_zone_count; i++)
            led_apply_zone(i);
        ap_log("STARTUP: hardware apply complete");
    }

    /* Main screen */
    show_device_view();

    /* On exit: write zone state to sysfs so NextUI picks up consistent state.
     * For animation mode: do NOT write to sysfs — the animation script owns
     * the LED hardware and our writes would interfere with its frame cycle.
     * The settings file already has black colors + real brightness, which
     * NextUI will apply from the file if needed. */
    if (g_led_mode == MODE_ANIMATION) {
        ap_log("EXIT: animation running, skipping sysfs writes to avoid interference");
    } else {
        ap_log("EXIT: applying zone state to hardware");
        for (int i = 0; i < g_zone_count; i++)
            led_apply_zone(i);
    }

    /* Cleanup */
    for (int i = 0; i < FRONT_IMG_COUNT; i++) {
        if (g_img_front_variants[i]) SDL_DestroyTexture(g_img_front_variants[i]);
    }
    if (g_img_back) SDL_DestroyTexture(g_img_back);

    ap_log("=== LED'oh! shutting down ===");
    ap_quit();
    return 0;
}
