/* src/icons.c - Robust XDG Icon Theme Loader */
#define _DEFAULT_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "icons.h"
#include <ctype.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef HAVE_RSVG
#include <librsvg/rsvg.h>
#endif

#define LOG(fmt, ...) fprintf(stderr, "[Icons] " fmt "\n", ##__VA_ARGS__)
#define MAX_CACHE 64
#define MAX_PATH 512

/* Icon cache entry */
typedef struct {
  char class_name[128];
  int size;
  cairo_surface_t *surface;
} IconCacheEntry;

/* Global state */
static IconCacheEntry icon_cache[MAX_CACHE];
static int cache_count = 0;
static char current_theme[64] = "Tela-dracula";
static char fallback_theme_name[64] = "Tela-circle-dracula";

/* XDG icon search paths */
static char user_icons_path[MAX_PATH];
static char user_icons_path2[MAX_PATH];
static const char *icon_dirs[8];

/* Desktop file search paths */
static char user_desktop_path[MAX_PATH];
static const char *desktop_dirs[8];

/* Convert string to lowercase */
static void to_lowercase(char *dest, const char *src, size_t max) {
  size_t i;
  for (i = 0; i < max - 1 && src[i]; i++) {
    dest[i] = tolower((unsigned char)src[i]);
  }
  dest[i] = '\0';
}

/* Check if file exists */
static int file_exists(const char *path) {
  struct stat st;
  return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

/* Initialize paths */
static void init_paths(void) {
  const char *home = getenv("HOME");
  const char *data_home = getenv("XDG_DATA_HOME");
  int icon_idx = 0;
  int desktop_idx = 0;

  /* User icon paths */
  if (home) {
    snprintf(user_icons_path, sizeof(user_icons_path), "%s/.icons", home);
    icon_dirs[icon_idx++] = user_icons_path;
  }
  if (data_home) {
    snprintf(user_icons_path2, sizeof(user_icons_path2), "%s/icons", data_home);
  } else if (home) {
    snprintf(user_icons_path2, sizeof(user_icons_path2),
             "%s/.local/share/icons", home);
  }
  icon_dirs[icon_idx++] = user_icons_path2;
  icon_dirs[icon_idx++] = "/usr/share/icons";
  icon_dirs[icon_idx++] = "/usr/local/share/icons";
  icon_dirs[icon_idx++] = "/usr/share/pixmaps";
  icon_dirs[icon_idx] = NULL;

  /* Desktop file paths */
  if (data_home) {
    snprintf(user_desktop_path, sizeof(user_desktop_path), "%s/applications",
             data_home);
  } else if (home) {
    snprintf(user_desktop_path, sizeof(user_desktop_path),
             "%s/.local/share/applications", home);
  }
  desktop_dirs[desktop_idx++] = user_desktop_path;
  desktop_dirs[desktop_idx++] = "/usr/share/applications";
  desktop_dirs[desktop_idx++] = "/usr/local/share/applications";
  desktop_dirs[desktop_idx++] = "/var/lib/flatpak/exports/share/applications";
  desktop_dirs[desktop_idx] = NULL;
}

/* Find icon in a specific theme directory */
static char *find_icon_in_theme(const char *theme, const char *icon_name,
                                int size) {
  static char path[MAX_PATH];
  (void)size; /* Size hint not used currently */

  const char *sizes[] = {"scalable", "512x512", "256x256", "128x128", "64x64",
                         "48x48",    "32x32",   "24x24",   "22x22",   "16x16"};
  const char *categories[] = {"apps",   "applications", "mimetypes",
                              "places", "devices",      "actions",
                              "status", "categories"};
  const char *extensions[] = {".svg", ".png", ".xpm"};

  for (int d = 0; icon_dirs[d]; d++) {
    if (!icon_dirs[d][0])
      continue;

    /* Try theme/size/category/icon format */
    for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
      for (size_t c = 0; c < sizeof(categories) / sizeof(categories[0]); c++) {
        for (size_t e = 0; e < sizeof(extensions) / sizeof(extensions[0]);
             e++) {
          snprintf(path, sizeof(path), "%s/%s/%s/%s/%s%s", icon_dirs[d], theme,
                   sizes[s], categories[c], icon_name, extensions[e]);
          if (file_exists(path))
            return path;
        }
      }
    }

    /* Try theme/category/size/icon format (alternate layout) */
    for (size_t c = 0; c < sizeof(categories) / sizeof(categories[0]); c++) {
      for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
        for (size_t e = 0; e < sizeof(extensions) / sizeof(extensions[0]);
             e++) {
          snprintf(path, sizeof(path), "%s/%s/%s/%s/%s%s", icon_dirs[d], theme,
                   categories[c], sizes[s], icon_name, extensions[e]);
          if (file_exists(path))
            return path;
        }
      }
    }
  }

  /* Try pixmaps as last resort */
  for (size_t e = 0; e < sizeof(extensions) / sizeof(extensions[0]); e++) {
    snprintf(path, sizeof(path), "/usr/share/pixmaps/%s%s", icon_name,
             extensions[e]);
    if (file_exists(path))
      return path;
  }

  return NULL;
}

/* Scan directory for desktop file matching class name */
static char *find_desktop_file_by_scan(const char *class_name) {
  static char found_path[MAX_PATH];
  char lowercase_class[128];
  to_lowercase(lowercase_class, class_name, sizeof(lowercase_class));

  for (int d = 0; desktop_dirs[d]; d++) {
    DIR *dir = opendir(desktop_dirs[d]);
    if (!dir)
      continue;

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
      if (entry->d_type != DT_REG && entry->d_type != DT_LNK)
        continue;

      const char *name = entry->d_name;
      size_t len = strlen(name);
      if (len < 9 || strcmp(name + len - 8, ".desktop") != 0)
        continue;

      /* Convert filename to lowercase for comparison */
      char lowercase_name[256];
      to_lowercase(lowercase_name, name, sizeof(lowercase_name));

      /* Check various patterns:
       * 1. classname.desktop
       * 2. org.something.classname.desktop
       * 3. com.company.classname.desktop
       */
      if (strstr(lowercase_name, lowercase_class) != NULL) {
        snprintf(found_path, sizeof(found_path), "%s/%s", desktop_dirs[d],
                 name);
        closedir(dir);
        LOG("Found desktop file: %s", found_path);
        return found_path;
      }
    }
    closedir(dir);
  }

  return NULL;
}

/* Extract Icon= from desktop file */
static char *extract_icon_from_desktop(const char *desktop_path) {
  static char icon_name[256];
  FILE *fp = fopen(desktop_path, "r");
  if (!fp)
    return NULL;

  char line[512];
  while (fgets(line, sizeof(line), fp)) {
    if (strncmp(line, "Icon=", 5) == 0) {
      char *value = line + 5;
      /* Remove newline and whitespace */
      char *end = value + strlen(value) - 1;
      while (end > value && (*end == '\n' || *end == '\r' || *end == ' ')) {
        *end-- = '\0';
      }
      strncpy(icon_name, value, sizeof(icon_name) - 1);
      icon_name[sizeof(icon_name) - 1] = '\0';
      fclose(fp);
      return icon_name;
    }
  }
  fclose(fp);
  return NULL;
}

/* Find icon name from desktop file for a class name */
static char *find_desktop_icon(const char *class_name) {
  static char icon_name[256];
  char desktop_path[MAX_PATH];
  char lowercase[128];
  to_lowercase(lowercase, class_name, sizeof(lowercase));

  /* Method 1: Try direct match lowercase.desktop */
  for (int d = 0; desktop_dirs[d]; d++) {
    snprintf(desktop_path, sizeof(desktop_path), "%s/%s.desktop",
             desktop_dirs[d], lowercase);
    if (file_exists(desktop_path)) {
      char *icon = extract_icon_from_desktop(desktop_path);
      if (icon)
        return icon;
    }
  }

  /* Method 2: Scan directories for matching desktop file */
  char *found = find_desktop_file_by_scan(class_name);
  if (found) {
    char *icon = extract_icon_from_desktop(found);
    if (icon)
      return icon;
  }

  /* Method 3: Try common flatpak patterns */
  const char *flatpak_patterns[] = {"org.gnome.%s",   "org.kde.%s",
                                    "org.mozilla.%s", "com.github.%s",
                                    "io.github.%s",   NULL};
  for (int p = 0; flatpak_patterns[p]; p++) {
    for (int d = 0; desktop_dirs[d]; d++) {
      snprintf(desktop_path, sizeof(desktop_path), flatpak_patterns[p],
               class_name);
      char full_path[768]; /* Larger to avoid truncation */
      snprintf(full_path, sizeof(full_path), "%s/%s.desktop", desktop_dirs[d],
               desktop_path);
      if (file_exists(full_path)) {
        char *icon = extract_icon_from_desktop(full_path);
        if (icon)
          return icon;
      }
    }
  }

  /* Fallback: use lowercase class name as icon name */
  strncpy(icon_name, lowercase, sizeof(icon_name) - 1);
  return icon_name;
}

/* Load PNG icon with high-quality scaling */
static cairo_surface_t *load_png_icon(const char *path, int size) {
  cairo_surface_t *surface = cairo_image_surface_create_from_png(path);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    return NULL;
  }

  int orig_w = cairo_image_surface_get_width(surface);
  int orig_h = cairo_image_surface_get_height(surface);

  if (orig_w != size || orig_h != size) {
    cairo_surface_t *scaled =
        cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
    cairo_t *cr = cairo_create(scaled);

    double scale_x = (double)size / orig_w;
    double scale_y = (double)size / orig_h;
    double scale = (scale_x < scale_y) ? scale_x : scale_y;
    double offset_x = (size - orig_w * scale) / 2.0;
    double offset_y = (size - orig_h * scale) / 2.0;

    cairo_translate(cr, offset_x, offset_y);
    cairo_scale(cr, scale, scale);

    cairo_set_source_surface(cr, surface, 0, 0);
    cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BEST);
    cairo_paint(cr);

    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    return scaled;
  }

  return surface;
}

#ifdef HAVE_RSVG
/* Load SVG icon via librsvg */
static cairo_surface_t *load_svg_icon(const char *path, int size) {
  GError *error = NULL;
  RsvgHandle *handle = rsvg_handle_new_from_file(path, &error);
  if (!handle) {
    if (error) {
      LOG("SVG load error: %s", error->message);
      g_error_free(error);
    }
    return NULL;
  }

  cairo_surface_t *surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
  cairo_t *cr = cairo_create(surface);

  RsvgRectangle viewport = {0, 0, size, size};
  if (!rsvg_handle_render_document(handle, cr, &viewport, &error)) {
    LOG("SVG render error: %s", error ? error->message : "unknown");
    if (error)
      g_error_free(error);
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    g_object_unref(handle);
    return NULL;
  }

  cairo_destroy(cr);
  g_object_unref(handle);
  return surface;
}
#endif

/* Initialize icon system */
void icons_init(const char *theme_name, const char *fallback) {
  init_paths();

  if (theme_name && theme_name[0]) {
    strncpy(current_theme, theme_name, sizeof(current_theme) - 1);
    current_theme[sizeof(current_theme) - 1] = '\0';
  }
  if (fallback && fallback[0]) {
    strncpy(fallback_theme_name, fallback, sizeof(fallback_theme_name) - 1);
    fallback_theme_name[sizeof(fallback_theme_name) - 1] = '\0';
  }

  cache_count = 0;
  LOG("Initialized: theme=%s, fallback=%s", current_theme, fallback_theme_name);
}

/* Load app icon by class name */
cairo_surface_t *load_app_icon(const char *class_name, int size) {
  if (!class_name || !class_name[0])
    return NULL;

  /* Check cache first */
  for (int i = 0; i < cache_count; i++) {
    if (strcmp(icon_cache[i].class_name, class_name) == 0 &&
        icon_cache[i].size == size) {
      if (icon_cache[i].surface) {
        cairo_surface_reference(icon_cache[i].surface);
      }
      return icon_cache[i].surface;
    }
  }

  /* Find icon name from desktop file */
  char *icon_name = find_desktop_icon(class_name);
  LOG("Class '%s' -> icon '%s'", class_name, icon_name ? icon_name : "(null)");

  if (!icon_name) {
    /* Cache NULL result */
    if (cache_count < MAX_CACHE) {
      strncpy(icon_cache[cache_count].class_name, class_name, 127);
      icon_cache[cache_count].size = size;
      icon_cache[cache_count].surface = NULL;
      cache_count++;
    }
    return NULL;
  }

  /* Find icon file in themes */
  char *icon_path = find_icon_in_theme(current_theme, icon_name, size);
  if (!icon_path) {
    icon_path = find_icon_in_theme(fallback_theme_name, icon_name, size);
  }
  if (!icon_path) {
    icon_path = find_icon_in_theme("hicolor", icon_name, size);
  }
  if (!icon_path) {
    icon_path = find_icon_in_theme("Adwaita", icon_name, size);
  }

  cairo_surface_t *surface = NULL;

  if (icon_path) {
    LOG("Loading icon: %s", icon_path);

    const char *ext = strrchr(icon_path, '.');
    if (ext) {
      if (strcasecmp(ext, ".png") == 0) {
        surface = load_png_icon(icon_path, size);
      }
#ifdef HAVE_RSVG
      else if (strcasecmp(ext, ".svg") == 0) {
        surface = load_svg_icon(icon_path, size);
      }
#endif
    }
  }

  /* Cache result */
  if (cache_count < MAX_CACHE) {
    strncpy(icon_cache[cache_count].class_name, class_name, 127);
    icon_cache[cache_count].size = size;
    icon_cache[cache_count].surface = surface;
    if (surface) {
      cairo_surface_reference(surface);
    }
    cache_count++;
  }

  return surface;
}

/* Check if icon exists for app */
bool has_app_icon(const char *class_name) {
  if (!class_name)
    return false;

  for (int i = 0; i < cache_count; i++) {
    if (strcmp(icon_cache[i].class_name, class_name) == 0) {
      return icon_cache[i].surface != NULL;
    }
  }

  cairo_surface_t *s = load_app_icon(class_name, 48);
  if (s) {
    cairo_surface_destroy(s);
    return true;
  }
  return false;
}

/* Cleanup all cached icons */
void icons_cleanup(void) {
  for (int i = 0; i < cache_count; i++) {
    if (icon_cache[i].surface) {
      cairo_surface_destroy(icon_cache[i].surface);
      icon_cache[i].surface = NULL;
    }
  }
  cache_count = 0;
  LOG("Cache cleared");
}
