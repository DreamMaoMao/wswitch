/* src/main.c - wswitch Switcher Daemon (v1.0 Stable) */
#define _POSIX_C_SOURCE 200809L

#include "backend.h"
#include "config.h"
#include "icons.h"
#include "input.h"
#include "render.h"
#include "socket.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#define LOG(fmt, ...) fprintf(stderr, "[Daemon] " fmt "\n", ##__VA_ARGS__)

/* Retry limits for robust startup */
#define WAYLAND_RETRY_MAX 25
#define WAYLAND_RETRY_MS 200
#define PROTOCOL_RETRY_MAX 50
#define PROTOCOL_RETRY_MS 100

/* Global State */
struct wl_display *display = NULL;
struct wl_compositor *compositor = NULL;
struct wl_shm *shm = NULL;
struct zwlr_layer_shell_v1 *layer_shell = NULL;
struct wl_surface *surface = NULL;
struct zwlr_layer_surface_v1 *layer_surface = NULL;
struct wl_seat *seat = NULL;
struct wl_keyboard *keyboard = NULL;

static bool running = true;
static bool visible = false;

static AppState app_state;
static Config *config = NULL;
static int socket_fd = -1;

Backend *backend = NULL;

/* Signal Handling */
static volatile sig_atomic_t should_quit = 0;
static void signal_handler(int sig) {
  (void)sig;
  should_quit = 1;
}

/* Helper: Polite Sleep */
static void sleep_ms(int ms) {
  struct timespec ts = {.tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L};
  nanosleep(&ts, NULL);
}

/* --- Wayland Events --- */
static void layer_surface_configure(void *data,
                                    struct zwlr_layer_surface_v1 *layer_surf,
                                    uint32_t serial, uint32_t w, uint32_t h) {
  (void)data;
  if (w > 0 && h > 0) {
    app_state.width = w;
    app_state.height = h;
  }
  zwlr_layer_surface_v1_ack_configure(layer_surf, serial);

  if (visible) {
    render_ui(&app_state, app_state.width, app_state.height);
  }
}

static void layer_surface_closed(void *data,
                                 struct zwlr_layer_surface_v1 *layer_surf) {
  (void)data;
  (void)layer_surf;
  LOG("Layer surface closed by compositor");
  should_quit = 1;
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_configure,
    .closed = layer_surface_closed,
};

static void seat_capabilities(void *data, struct wl_seat *wl_seat,
                              uint32_t caps) {
  (void)wl_seat;
  AppState *state = (AppState *)data;
  if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !keyboard) {
    keyboard = wl_seat_get_keyboard(seat);
    wl_keyboard_add_listener(keyboard, get_keyboard_listener(), state);
    LOG("Keyboard listener attached");
  }
}

static void seat_name(void *data, struct wl_seat *wl_seat, const char *name) {
  (void)data;
  (void)wl_seat;
  (void)name;
}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
  (void)version;
  AppState *state = (AppState *)data;

  if (strcmp(interface, wl_compositor_interface.name) == 0)
    compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
  else if (strcmp(interface, wl_shm_interface.name) == 0)
    shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
  else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0)
    layer_shell =
        wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
  else if (strcmp(interface, wl_seat_interface.name) == 0) {
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 4);
    wl_seat_add_listener(seat, &seat_listener, state);
  }
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                   uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
  LOG("Registry global removed: %u (compositor may be exiting)", name);
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global, .global_remove = registry_global_remove};

/* --- Logic --- */

static void destroy_panel(void) {
  if (layer_surface) {
    zwlr_layer_surface_v1_destroy(layer_surface);
    layer_surface = NULL;
  }
  if (surface) {
    wl_surface_destroy(surface);
    surface = NULL;
  }
  visible = false;
  LOG("Panel destroyed");
}

static void create_panel(void) {
  if (surface) {
    LOG("Panel already exists");
    return;
  }

  surface = wl_compositor_create_surface(compositor);
  if (!surface) {
    LOG("Failed to create surface");
    return;
  }

  layer_surface = zwlr_layer_shell_v1_get_layer_surface(
      layer_shell, surface, NULL, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "wswitch");
  if (!layer_surface) {
    LOG("Failed to create layer surface");
    wl_surface_destroy(surface);
    surface = NULL;
    return;
  }

  zwlr_layer_surface_v1_set_size(layer_surface, 1, 1); // 最小初始尺寸
  zwlr_layer_surface_v1_set_anchor(layer_surface, 0);
  zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface, 0);
  zwlr_layer_surface_v1_add_listener(layer_surface, &layer_surface_listener,
                                     NULL);

  wl_surface_commit(surface);
  wl_display_roundtrip(display);

  LOG("Panel created");
}

static void hide_switcher(void) {
  if (!visible)
    return;

  visible = false;

  if (config && config->follow_monitor) {
    destroy_panel();
  } else {
    wl_surface_attach(surface, NULL, 0, 0);
    wl_surface_commit(surface);
    wl_display_flush(display);
    LOG("Panel hidden (not destroyed)");
  }
}

static void show_switcher(void) {
  LOG("Showing switcher...");

  if (config && config->follow_monitor && !surface) {
    create_panel();
    if (!surface) {
      LOG("Failed to create panel");
      return;
    }
  } else if (visible) {
    return;
  }

  input_reset_modifier_states();

  app_state_free(&app_state);
  app_state_init(&app_state);

  if (!backend) {
    LOG("Error: Backend not initialized");
    return;
  }

  if (backend->get_windows(&app_state, config) < 0) {
    LOG("Failed to update window list");
    return;
  }

  app_state.selected_index = (app_state.count > 1) ? 1 : 0;

  calculate_dimensions(&app_state, &app_state.width, &app_state.height);
  zwlr_layer_surface_v1_set_size(layer_surface, app_state.width,
                                 app_state.height);
  zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface, 1);

  visible = true;
  wl_surface_commit(surface);
  wl_display_flush(display);
}

static void select_and_hide(void) {
  if (visible && app_state.count > 0 && backend) {
    WindowInfo *win = &app_state.windows[app_state.selected_index];
    LOG("Switching to: %s (using %s backend)", win->title, backend->get_name());
    backend->activate_window(win->address);
  }
  hide_switcher();
}

static void handle_command(const char *cmd) {
  if (strcmp(cmd, CMD_QUIT) == 0) {
    should_quit = 1;
    return;
  }

  if (strcmp(cmd, CMD_HIDE) == 0) {
    hide_switcher();
    return;
  }

  if (strcmp(cmd, CMD_TOGGLE) == 0) {
    if (visible)
      hide_switcher();
    else
      show_switcher();
    return;
  }

  /* Navigation */
  if (!visible)
    show_switcher();
  else {
    int dir = 0;
    if (strcmp(cmd, CMD_NEXT) == 0)
      dir = 1;
    else if (strcmp(cmd, CMD_PREV) == 0)
      dir = -1;

    if (dir != 0 && app_state.count > 0) {
      app_state.selected_index =
          (app_state.selected_index + dir + app_state.count) % app_state.count;
      render_ui(&app_state, app_state.width, app_state.height);
    } else if (strcmp(cmd, CMD_SELECT) == 0) {
      select_and_hide();
    }
  }
}

/* Client Mode (CLI) */
static int run_client(const char *cmd) {
  const char *socket_cmd = NULL;
  if (strcmp(cmd, "next") == 0)
    socket_cmd = CMD_NEXT;
  else if (strcmp(cmd, "prev") == 0)
    socket_cmd = CMD_PREV;
  else if (strcmp(cmd, "select") == 0)
    socket_cmd = CMD_SELECT;
  else if (strcmp(cmd, "toggle") == 0)
    socket_cmd = CMD_TOGGLE;
  else if (strcmp(cmd, "hide") == 0)
    socket_cmd = CMD_HIDE;
  else if (strcmp(cmd, "quit") == 0)
    socket_cmd = CMD_QUIT;
  else
    return 1;

  if (!is_daemon_running()) {
    fprintf(stderr, "Daemon not running. Start with: wswitch --daemon\n");
    return 1;
  }
  return send_command(socket_cmd) == 0 ? 0 : 1;
}

/* Daemon Mode */
static int run_daemon(void) {
  /* Check if daemon is already running */
  if (is_daemon_running()) {
    fprintf(stderr, "Error: Daemon is already running.\n");
    return 1;
  }

  /* 1. Signals */
  struct sigaction sa;
  sa.sa_handler = signal_handler;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0;
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGTERM, &sa, NULL);

  /* Set SIGPIPE to SIG_IGN to prevent crashes on broken pipe */
  signal(SIGPIPE, SIG_IGN);

  /* 2. Config & Resources */
  config = load_config();
  if (!config)
    config = get_default_config();
  render_set_config(config);
  icons_init(config->icon_theme, config->icon_fallback);
  app_state_init(&app_state);

  /* Callbacks */
  on_modifier_release = select_and_hide;
  on_escape = hide_switcher; /* hide without switch */

  /* 3. Wayland Connection */
  for (int i = 0; i < WAYLAND_RETRY_MAX; i++) {
    display = wl_display_connect(NULL);
    if (display)
      break;
    sleep_ms(WAYLAND_RETRY_MS);
  }
  if (!display) {
    LOG("Failed to connect to Wayland");
    if (backend)
      backend_cleanup(backend);
    return 1;
  }

  backend = backend_init(display);
  if (!backend) {
    LOG("Failed to initialize backend");
    wl_display_disconnect(display);
    return 1;
  }
  LOG("Using %s backend", backend->get_name());

  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, &app_state);

  /* 4. Bind Protocols */
  for (int i = 0; i < PROTOCOL_RETRY_MAX; i++) {
    wl_display_roundtrip(display);
    if (compositor && layer_shell && shm)
      break;
    sleep_ms(PROTOCOL_RETRY_MS);
  }
  if (!compositor || !layer_shell || !shm) {
    LOG("Failed to bind Wayland protocols");
    if (backend)
      backend_cleanup(backend);
    wl_display_disconnect(display);
    return 1;
  }

  /* 5. Surface Setup */
  surface = wl_compositor_create_surface(compositor);
  layer_surface = zwlr_layer_shell_v1_get_layer_surface(
      layer_shell, surface, NULL, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "wswitch");
  zwlr_layer_surface_v1_set_size(layer_surface, 1,
                                 1); /* Minimal initial size */
  zwlr_layer_surface_v1_set_anchor(layer_surface, 0);
  zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface, 0);
  zwlr_layer_surface_v1_add_listener(layer_surface, &layer_surface_listener,
                                     NULL);
  wl_surface_commit(surface);
  wl_display_roundtrip(display);

  /* 6. Socket Server */
  socket_fd = init_server();
  if (socket_fd < 0) {
    if (backend)
      backend_cleanup(backend);
    wl_display_disconnect(display);
    return 1;
  }

  LOG("Daemon Started (PID: %d)", getpid());

  struct pollfd fds[2];
  fds[0].fd = wl_display_get_fd(display);
  fds[0].events = POLLIN | POLLERR | POLLHUP;
  fds[1].fd = socket_fd;
  fds[1].events = POLLIN;

  while (running && !should_quit) {
    /* prepare to read Wayland events */
    int ret = wl_display_prepare_read(display);
    if (ret != 0) {
      /* prepare failed, may be because the connection has been lost */
      ret = wl_display_dispatch_pending(display);
      if (ret == -1) {
        LOG("Wayland connection lost (dispatch_pending failed)");
        break;
      }
      /* continue waiting for events */
    } else {
      wl_display_flush(display);

      /* Poll for events with 100ms timeout */
      if (poll(fds, 2, 100) < 0) {
        if (errno == EINTR) {
          wl_display_cancel_read(display);
          continue;
        }
        LOG("poll error: %s", strerror(errno));
        break;
      }

      /* check if Wayland connection has been terminated */
      if (fds[0].revents & (POLLERR | POLLHUP)) {
        LOG("Wayland connection terminated (compositor exited)");
        wl_display_cancel_read(display);
        break;
      }

      if (fds[0].revents & POLLIN) {
        /* read and process Wayland events */
        if (wl_display_read_events(display) == -1) {
          LOG("Failed to read Wayland events");
          break;
        }

        ret = wl_display_dispatch_pending(display);
        if (ret == -1) {
          LOG("Wayland dispatch_pending failed");
          break;
        }
      } else {
        wl_display_cancel_read(display);
      }
    }

    /* handle socket commands */
    if (fds[1].revents & POLLIN) {
      while (1) {
        struct sockaddr_un cli_addr;
        socklen_t clilen = sizeof(cli_addr);
        int client = accept(socket_fd, (struct sockaddr *)&cli_addr, &clilen);
        if (client < 0) {
          if (errno == EAGAIN || errno == EWOULDBLOCK) {
            break;
          }
          LOG("Accept error: %s", strerror(errno));
          break;
        }

        char buffer[256];
        ssize_t n = read(client, buffer, sizeof(buffer) - 1);
        if (n > 0) {
          buffer[n] = '\0';
          if (buffer[n - 1] == '\n')
            buffer[n - 1] = '\0';
          LOG("Received command: %s", buffer);
          handle_command(buffer);
        }
        close(client);
      }
    }
  }

  /* 7. Cleanup */
  LOG("Cleaning up...");

  cleanup_server(socket_fd);
  input_cleanup();
  icons_cleanup();
  app_state_free(&app_state);
  free_config(config);

  if (backend) {
    backend_cleanup(backend);
    backend = NULL;
  }

  if (layer_surface)
    zwlr_layer_surface_v1_destroy(layer_surface);
  if (surface)
    wl_surface_destroy(surface);
  if (keyboard)
    wl_keyboard_destroy(keyboard);
  if (seat)
    wl_seat_destroy(seat);
  if (display)
    wl_display_disconnect(display);

  LOG("Daemon stopped");
  return 0;
}

int main(int argc, char **argv) {
  if (argc > 1 && strcmp(argv[1], "--daemon") == 0) {
    return run_daemon();
  } else if (argc > 1) {
    return run_client(argv[1]);
  }

  fprintf(stderr, "Usage: %s <command> | --daemon\n", argv[0]);
  return 1;
}