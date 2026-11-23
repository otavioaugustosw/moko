#include <mysql.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>
#include "ClientOptions.h"

static void append(char **out, size_t *size, const char *text, size_t count) {
    if (*size + count > 1024 * 1024) return;
    char *new = realloc(*out, *size + count + 1);
    if (!new) return;
    *out = new; memcpy(*out + *size, text, count); *size += count; (*out)[*size] = 0;
}
char *moko_mysql_query(const char *host, unsigned int port, const char *user, const char *password, const char *socket, const char *sql, int *code) {
    *code = 1;
    MYSQL *client = mysql_init(NULL);
    if (!client) return strdup("could not prepare the connection.");
    moko_configure_client_plugins(client);
    unsigned int timeout = 3;
    bool expired = true;
    mysql_options(client, MYSQL_OPT_CONNECT_TIMEOUT, &timeout);
    timeout = 5; mysql_options(client, MYSQL_OPT_READ_TIMEOUT, &timeout); mysql_options(client, MYSQL_OPT_WRITE_TIMEOUT, &timeout);
    mysql_options(client, MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS, &expired);
    mysql_options(client, MYSQL_SET_CHARSET_NAME, "utf8mb4");
    if (!mysql_real_connect(client, host, user, password, NULL, port, socket, CLIENT_MULTI_STATEMENTS)) {
        *code = mysql_errno(client); char *error = strdup(mysql_error(client)); mysql_close(client); return error;
    }
    if (mysql_query(client, sql)) {
        *code = mysql_errno(client); char *error = strdup(mysql_error(client)); mysql_close(client); return error;
    }
    char *output = strdup(""); size_t size = 0;
    int next = 0;
    do {
        MYSQL_RES *result = mysql_store_result(client);
        if (result) {
            unsigned int fields = mysql_num_fields(result); MYSQL_ROW row;
            while ((row = mysql_fetch_row(result))) {
                unsigned long *lengths = mysql_fetch_lengths(result);
                for (unsigned int i = 0; i < fields; i++) {
                    if (i) append(&output, &size, "\t", 1);
                    if (row[i]) append(&output, &size, row[i], lengths[i]);
                }
                append(&output, &size, "\n", 1);
            }
            mysql_free_result(result);
        } else if (mysql_field_count(client)) {
            *code = mysql_errno(client); free(output); output = strdup(mysql_error(client)); mysql_close(client); return output;
        }
        next = mysql_next_result(client);
    } while (next == 0);
    if (next > 0) { *code = mysql_errno(client); free(output); output = strdup(mysql_error(client)); }
    else *code = 0;
    mysql_close(client);
    return output;
}
void moko_mysql_free(char *output) { free(output); }

static unsigned long escape_password(MYSQL *client, char *target, const char *value, size_t length) {
    if (!(client->server_status & SERVER_STATUS_NO_BACKSLASH_ESCAPES))
        return mysql_real_escape_string(client, target, value, length);
    unsigned long written = 0;
    for (size_t i = 0; i < length; i++) {
        if (value[i] == '\'') target[written++] = '\'';
        target[written++] = value[i];
    }
    target[written] = 0;
    return written;
}

char *moko_mysql_change_password(const char *host, unsigned int port, const char *user, const char *old_password, const char *new_password, int *code) {
    *code = 1;
    MYSQL *client = mysql_init(NULL);
    if (!client) return strdup("could not prepare the connection.");
    moko_configure_client_plugins(client);
    unsigned int timeout = 3; bool expired = true;
    mysql_options(client, MYSQL_OPT_CONNECT_TIMEOUT, &timeout);
    timeout = 5; mysql_options(client, MYSQL_OPT_READ_TIMEOUT, &timeout); mysql_options(client, MYSQL_OPT_WRITE_TIMEOUT, &timeout);
    mysql_options(client, MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS, &expired);
    mysql_options(client, MYSQL_SET_CHARSET_NAME, "utf8mb4");
    if (!mysql_real_connect(client, host, user, old_password, NULL, port, NULL, 0)) {
        *code = mysql_errno(client); char *error = strdup(mysql_error(client)); mysql_close(client); return error;
    }
    size_t old_size = strlen(old_password), new_size = strlen(new_password);
    if (old_size > 1024 * 1024 || new_size > 1024 * 1024) { mysql_close(client); return strdup("password is too long."); }
    char *old_escaped = malloc(old_size * 2 + 1), *new_escaped = malloc(new_size * 2 + 1);
    if (!old_escaped || !new_escaped) { free(old_escaped); free(new_escaped); mysql_close(client); return strdup("could not prepare the connection."); }
    // Use the connection's own SQL mode. No preliminary SQL is permitted for expired passwords.
    unsigned long old_length = escape_password(client, old_escaped, old_password, old_size);
    unsigned long new_length = escape_password(client, new_escaped, new_password, new_size);
    if (old_length == (unsigned long)-1 || new_length == (unsigned long)-1) {
        *code = mysql_errno(client); free(old_escaped); free(new_escaped); mysql_close(client); return strdup("could not prepare the change.");
    }
    size_t sql_size = old_length + new_length + 100;
    char *sql = malloc(sql_size);
    if (!sql) { free(old_escaped); free(new_escaped); mysql_close(client); return strdup("could not prepare the change."); }
    if (strstr(mysql_get_server_info(client), "MariaDB"))
        snprintf(sql, sql_size, "ALTER USER CURRENT_USER() IDENTIFIED BY '%s'", new_escaped);
    else
        snprintf(sql, sql_size, "ALTER USER USER() IDENTIFIED BY '%s' REPLACE '%s'", new_escaped, old_escaped);
    int failed = mysql_query(client, sql);
    *code = failed ? mysql_errno(client) : 0;
    char *message = strdup(failed ? mysql_error(client) : "password changed.");
    memset(sql, 0, sql_size); memset(old_escaped, 0, old_size * 2 + 1); memset(new_escaped, 0, new_size * 2 + 1);
    free(sql); free(old_escaped); free(new_escaped); mysql_close(client);
    return message;
}
