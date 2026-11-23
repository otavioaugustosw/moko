# Installing moko

moko requires Apple Silicon and macOS 26 or later.

1. Drag moko to Applications and open it.
2. Follow the welcome screen. Choose the included PostgreSQL or MariaDB server, an existing server, or set up later.
3. Choose whether to configure PHP now. Select a project folder on the separate PHP setup screen if you accept.

PostgreSQL, MariaDB and PHP are included and work offline. No Homebrew or administrator installer is required. Both SQL engines may run at the same time. Selecting a connection does not control another service.

Default local ports are PostgreSQL 15432, MariaDB 13306 and PHP 8080. The servers listen on loopback only. An occupied port is reported; moko does not take over an existing process. The PHP server is for local development.

Data is separate from executable components:

- PostgreSQL: ~/Library/Application Support/moko/databases/postgresql/18
- MariaDB: ~/Library/Application Support/moko/database (the existing directory is retained)

Passwords remain in macOS Keychain. Updating or removing a runtime does not erase its database files. Updates require confirmation and a stopped-server backup; major upgrades require a dedicated migration. No SQL, database or PHP project is automatically converted between engines.

An existing local Oracle MySQL installation can be started, stopped or restarted with a one-time macOS administrator authorization. Controls appear only for a loopback MySQL profile matching the recognized system service and its port. The app verifies port ownership before changing that service, installs no resident privileged helper and does not stop it when moko quits. Other external installations remain independently managed. Each action asks for the administrator password. Optionally, **authorize once** in settings → connection saves a root-owned script limited to starting, stopping and restarting that service, and a sudo rule that lets your user run it without a password; from then on any app in your account can control that service. **remove authorization** deletes both files (`/Library/PrivilegedHelperTools/com.otavioaugustosw.moko.mysql-service` and `/etc/sudoers.d/moko-mysql`).

MySQL export/import uses the native client tools already installed on the Mac, when available. These tools are not included in the moko download. MariaDB uses its own included tools. PostgreSQL uses the included tools. Select `export sql` in the database's three-dot menu.

Closing or minimizing keeps owned servers running. Use open panel in the menu bar to return. settings → application controls whether closing retains the Dock entry. Quitting stops only moko-owned processes.

Source archives and notices are available at https://github.com/otavioaugustosw/moko/releases/tag/runtime-sources-2026-10-12 . Use the attached base and MariaDB source ZIPs, not GitHub's repository archive. Notices and legal documents are also in settings → components and settings → application.

PHP includes PDO/PostgreSQL, pgsql, PDO/MySQL, mysqli and the modules recorded in the runtime build profile. Configure project/database associations in the PHP workspace; copied examples omit the password unless requested. No project file is changed automatically.

Optional support: https://buymeacoffee.com/otavioaugustosw . Contact: contato@otavioaugustosw.com.
