#include <mysql.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include "ClientOptions.h"

// Structured transport preserves NULL, empty strings, tabs, UTF-8 and binary bytes.
// Results are streamed and bounded; omitted rows are explicitly marked.
typedef struct { char *data; size_t size, capacity; bool failed; } Buffer;
static void put(Buffer *b, const char *s, size_t n) {
    if (b->failed) return;
    if (b->size + n > 32 * 1024 * 1024) { b->failed = true; return; }
    if (b->size + n + 1 > b->capacity) {
        size_t capacity = (b->size + n + 1) * 2;
        char *p = realloc(b->data, capacity);
        if (!p) { b->failed = true; return; }
        b->data = p; b->capacity = capacity;
    }
    memcpy(b->data + b->size, s, n); b->size += n; b->data[b->size] = 0;
}
static void str(Buffer *b, const char *s) { put(b, s, strlen(s)); }
static void number(Buffer *b, unsigned long long n) { char s[32]; snprintf(s, sizeof s, "%llu", n); str(b, s); }
static void json(Buffer *b, const char *s) {
    str(b, "\"");
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        if (*p == '"' || *p == '\\') { char v[2] = {'\\', *p}; put(b, v, 2); }
        else if (*p < 32) { char v[7]; snprintf(v, sizeof v, "\\u%04x", *p); str(b, v); }
        else put(b, (const char *)p, 1);
    }
    str(b, "\"");
}
static void hex(Buffer *b, const char *s, size_t n) {
    static const char digits[] = "0123456789abcdef";
    str(b, "\"");
    for (size_t i = 0; i < n; i++) { unsigned char c = s[i]; char v[2] = {digits[c >> 4], digits[c & 15]}; put(b, v, 2); }
    str(b, "\"");
}
static char *database_execute(const char *host, unsigned int port, const char *user, const char *password,
                            const char *database, const char *sql, bool multiple, unsigned int max_rows,
                            bool one_row, bool form_session, const char *context_sql, const char *tls_mode, const char *root_ca,
                            bool (*lifecycle)(unsigned long long, void *), void *job, int *code) {
    *code = 1;
    MYSQL *client = mysql_init(NULL);
    Buffer output = {0};
    if (!client) return strdup("{\"code\":1,\"error\":\"could not prepare the connection\",\"results\":[],\"rolledBack\":false}");
    moko_configure_client_plugins(client);
    if (root_ca && *root_ca) mysql_options(client, MYSQL_OPT_SSL_CA, root_ca);
    // Connector/C defaults can change; apply the selected profile's policy explicitly.
    my_bool enforce = tls_mode && (!strcmp(tls_mode, "require") || !strcmp(tls_mode, "verify-full"));
    my_bool verify = tls_mode && !strcmp(tls_mode, "verify-full");
    mysql_options(client, MYSQL_OPT_SSL_ENFORCE, &enforce);
    mysql_options(client, MYSQL_OPT_SSL_VERIFY_SERVER_CERT, &verify);
    unsigned int timeout = 4; unsigned int local_infile = 0;
    mysql_options(client, MYSQL_OPT_CONNECT_TIMEOUT, &timeout);
    timeout = 30; mysql_options(client, MYSQL_OPT_READ_TIMEOUT, &timeout); mysql_options(client, MYSQL_OPT_WRITE_TIMEOUT, &timeout);
    mysql_options(client, MYSQL_SET_CHARSET_NAME, "utf8mb4");
    mysql_options(client, MYSQL_OPT_LOCAL_INFILE, &local_infile);
    int error_code = 0; char *error_text = NULL; bool rolled_back = false;
    if (!mysql_real_connect(client, host, user, password, *database ? database : NULL, port, NULL,
                            (multiple ? CLIENT_MULTI_STATEMENTS : 0) | (one_row ? CLIENT_FOUND_ROWS : 0))) {
        error_code = mysql_errno(client); error_text = strdup(mysql_error(client));
    }
    if (!error_code && lifecycle && !lifecycle(mysql_thread_id(client), job)) { error_code = 1317; error_text = strdup("query cancelled"); }
    str(&output, "{\"results\":[");
    bool first = true;
    if (!error_code) {
        // Single-statement forms use predictable literal escaping and reject lossy conversion.
        // The explicit SQL console preserves the server/session mode supplied by its script.
        if ((one_row || !multiple || form_session) && mysql_query(client, "SET SESSION sql_mode=CONCAT_WS(',',NULLIF(TRIM(BOTH ',' FROM REPLACE(CONCAT(',',@@SESSION.sql_mode,','),',NO_BACKSLASH_ESCAPES,',',')),''),'STRICT_ALL_TABLES')")) { error_code = mysql_errno(client); error_text = strdup(mysql_error(client)); }
        // Context is one generated SET statement. The edited DDL remains a separate,
        // single-statement query, so pasted trailing commands cannot run after it.
        if (!error_code && context_sql && *context_sql && mysql_query(client, context_sql)) {
            error_code = mysql_errno(client); error_text = strdup(mysql_error(client));
        }
        if (!error_code && one_row && mysql_autocommit(client, 0)) { error_code = mysql_errno(client); error_text = strdup(mysql_error(client)); }
        if (!error_code && lifecycle && !lifecycle(mysql_thread_id(client), job)) { error_code = 1317; error_text = strdup("query cancelled"); }
        if (!error_code && mysql_query(client, sql)) { error_code = mysql_errno(client); error_text = strdup(mysql_error(client)); }
        int next = 0;
        while (!error_code) {
            MYSQL_RES *result = mysql_use_result(client);
            if (!first) str(&output, ","); first = false;
            str(&output, "{\"fields\":[");
            if (result) {
                unsigned int count = mysql_num_fields(result); MYSQL_FIELD *fields = mysql_fetch_fields(result);
                for (unsigned int i = 0; i < count; i++) {
                    if (i) str(&output, ","); str(&output, "{\"name\":"); json(&output, fields[i].name);
                    str(&output, ",\"type\":"); number(&output, fields[i].type);
                    str(&output, ",\"binary\":");
                    bool binary = fields[i].charsetnr == 63 && (fields[i].type == MYSQL_TYPE_BIT || fields[i].type == MYSQL_TYPE_GEOMETRY || fields[i].type == MYSQL_TYPE_VECTOR || fields[i].type >= MYSQL_TYPE_TINY_BLOB);
                    str(&output, binary ? "true}" : "false}");
                }
                str(&output, "],\"rows\":[");
                MYSQL_ROW row; unsigned int kept = 0; bool truncated = false;
                size_t budget = 0;
                while ((row = mysql_fetch_row(result))) {
                    unsigned long *lengths = mysql_fetch_lengths(result); size_t bytes = 0;
                    for (unsigned int i = 0; i < count; i++) bytes += lengths[i];
                    if (kept >= max_rows || bytes > 4 * 1024 * 1024 || budget + bytes > 8 * 1024 * 1024) { truncated = true; continue; }
                    budget += bytes;
                    if (kept++) str(&output, ","); str(&output, "[");
                    for (unsigned int i = 0; i < count; i++) { if (i) str(&output, ","); if (row[i]) hex(&output, row[i], lengths[i]); else str(&output, "null"); }
                    str(&output, "]");
                }
                if (mysql_errno(client)) { error_code = mysql_errno(client); error_text = strdup(mysql_error(client)); }
                mysql_free_result(result);
                str(&output, "],\"affected\":0,\"truncated\":"); str(&output, truncated ? "true" : "false");
            } else {
                if (mysql_field_count(client)) { error_code = mysql_errno(client); error_text = strdup(mysql_error(client)); }
                str(&output, "],\"rows\":[],\"affected\":");
                unsigned long long affected = mysql_affected_rows(client);
                number(&output, affected == (unsigned long long)-1 ? 0 : affected);
                str(&output, ",\"truncated\":false");
                if (one_row && !error_code && affected != 1) {
                    error_code = 409; error_text = strdup("another connection changed or removed this row. refresh the data before editing again");
                }
            }
            str(&output, ",\"warnings\":"); number(&output, mysql_warning_count(client)); str(&output, "}");
            if (error_code || (next = mysql_next_result(client)) == -1) break;
            if (next > 0) { error_code = mysql_errno(client); error_text = strdup(mysql_error(client)); break; }
        }
        if (one_row) {
            if (error_code) { mysql_rollback(client); rolled_back = true; }
            else if (mysql_commit(client)) { error_code = mysql_errno(client); error_text = strdup(mysql_error(client)); }
        } else if (client->server_status & SERVER_STATUS_IN_TRANS) {
            mysql_rollback(client); rolled_back = true;
        }
    }
    str(&output, "],\"code\":"); number(&output, error_code); str(&output, ",\"error\":"); json(&output, error_text ? error_text : "");
    str(&output, ",\"rolledBack\":"); str(&output, rolled_back ? "true}" : "false}");
    if (lifecycle) lifecycle(0, job);
    free(error_text); mysql_close(client); *code = error_code;
    if (output.failed) { free(output.data); *code = 1; return strdup("{\"code\":1,\"error\":\"result exceeded the memory limit; reduce the query. previous commands may have been applied\",\"results\":[],\"rolledBack\":false}"); }
    return output.data;
}

char *moko_database_execute(const char *host, unsigned int port, const char *user, const char *password,
                            const char *database, const char *sql, bool multiple, unsigned int max_rows,
                            bool one_row, bool form_session, int *code) {
    return database_execute(host, port, user, password, database, sql, multiple, max_rows, one_row, form_session, NULL, NULL, NULL, NULL, NULL, code);
}
char *moko_database_execute_with_context(const char *host, unsigned int port, const char *user, const char *password,
                            const char *database, const char *sql, bool multiple, unsigned int max_rows,
                            bool one_row, bool form_session, const char *context_sql, int *code) {
    return database_execute(host, port, user, password, database, sql, multiple, max_rows, one_row, form_session, context_sql, NULL, NULL, NULL, NULL, code);
}

char *moko_database_execute_tls(const char *host, unsigned int port, const char *user, const char *password,
                            const char *database, const char *sql, bool multiple, unsigned int max_rows,
                            bool one_row, bool form_session, const char *context_sql, const char *tls_mode, const char *root_ca,
                            bool (*lifecycle)(unsigned long long, void *), void *job, int *code) {
    return database_execute(host, port, user, password, database, sql, multiple, max_rows, one_row, form_session,
                            context_sql, tls_mode, root_ca, lifecycle, job, code);
}
