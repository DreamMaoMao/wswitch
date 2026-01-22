/* src/icons.h - Icon Theme Loading */
#ifndef ICONS_H
#define ICONS_H

#include <cairo/cairo.h>
#include <stdbool.h>

/* Initialize icon cache and theme lookup */
void icons_init(const char *theme_name, const char *fallback_theme);

/* Load an app icon by class name (returns NULL if not found) */
cairo_surface_t *load_app_icon(const char *class_name, int size);

/* Free all cached icons */
void icons_cleanup(void);

/* Check if icon exists for app */
bool has_app_icon(const char *class_name);

#endif /* ICONS_H */
