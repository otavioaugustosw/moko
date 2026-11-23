#ifndef MOKO_CLIENT_OPTIONS_H
#define MOKO_CLIENT_OPTIONS_H

#include <mysql.h>
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Resolve authentication plugins relative to the loaded connector, including after app relocation.
// These client plugins are provided by MariaDB's bundled LGPL Connector/C.
static inline void moko_configure_client_plugins(MYSQL *client) {
    Dl_info library;
    char location[PATH_MAX], plugins[PATH_MAX];
    if (!dladdr((const void *)mysql_init, &library) || !library.dli_fname
        || !realpath(library.dli_fname, location)) return;
    char *filename = strrchr(location, '/');
    if (!filename) return;
    *filename = '\0';
    int length = snprintf(plugins, sizeof plugins, "%s/../Resources/Runtime/Connector/lib/plugin", location);
    if (length > 0 && length < sizeof plugins) mysql_options(client, MYSQL_PLUGIN_DIR, plugins);
}

#endif
