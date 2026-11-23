#include <stdbool.h>
#include <stdint.h>

// Exact C ABI exported by DatabaseBridge.c. Imported by Swift via the module map.
char * _Nullable moko_database_execute(
    const char * _Nonnull host, unsigned int port,
    const char * _Nonnull user, const char * _Nonnull password,
    const char * _Nonnull database, const char * _Nonnull sql,
    bool multiple, unsigned int max_rows, bool one_row, bool form_session,
    int32_t * _Nonnull code
);
char * _Nullable moko_database_execute_with_context(
    const char * _Nonnull host, unsigned int port,
    const char * _Nonnull user, const char * _Nonnull password,
    const char * _Nonnull database, const char * _Nonnull sql,
    bool multiple, unsigned int max_rows, bool one_row, bool form_session,
    const char * _Nonnull context_sql, int32_t * _Nonnull code
);

char * _Nullable moko_database_execute_tls(
    const char * _Nonnull host, uint32_t port, const char * _Nonnull user, const char * _Nonnull password,
    const char * _Nonnull database, const char * _Nonnull sql,
    bool multiple, uint32_t max_rows, bool one_row, bool form_session, const char * _Nonnull context_sql,
    const char * _Nonnull tls_mode, const char * _Nonnull root_ca,
    bool (* _Nullable lifecycle)(unsigned long long, void * _Nullable),
    void * _Nullable job, int32_t * _Nonnull code);
