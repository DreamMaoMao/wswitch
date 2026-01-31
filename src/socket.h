/* src/socket.h - Unix Domain Socket IPC */
#ifndef SOCKET_H
#define SOCKET_H

#include <stdbool.h>

/* Socket path */
#define SOCKET_PATH "/tmp/wswitch.sock"

/* Commands */
#define CMD_NEXT "NEXT"
#define CMD_PREV "PREV"
#define CMD_SELECT "SELECT"
#define CMD_TOGGLE "TOGGLE"
#define CMD_HIDE "HIDE"
#define CMD_QUIT "QUIT"

/* Server functions (daemon) */
int init_server(void);
int accept_client(int server_fd);
char *read_command(int client_fd);
void cleanup_server(int server_fd);
int get_server_fd(void);

/* Client functions */
int send_command(const char *cmd);

/* Check if daemon is running */
bool is_daemon_running(void);

#endif /* SOCKET_H */
