# moko user guide

moko brings together local PostgreSQL, MariaDB and PHP servers and an SQL database browser. The interface is
in English, with light, dark or system appearance. It requires macOS 26 or later on Apple Silicon.

## First launch

The welcome flow fills the window. In **set up sql**, choose the included PostgreSQL, the included MariaDB,
a server you already have (PostgreSQL, MariaDB or MySQL) or leave it for later. **set up php** asks for the
project folder and port; **later** skips it. The optional **ai agents** page turns on agent access. None of
these choices migrates or replaces existing databases.

## Screens

- **overview**: one card per server, with a traffic light, details and start, stop and restart.
- **connections**: sessions visible to the connected account.
- **databases**: open databases and tables, edit data, change structure through forms or run SQL.
- **web server**: add PHP project folders, choose a local port and an optional router script. Switching
  projects asks for confirmation and restarts a running server. Removing a project keeps its files.
  Start the database first so PHP receives its credentials as environment variables.
- **activity**: what moko did in this session.
- **settings**: connection, account, application, agents and components.
- **support**: optional donation link.

Minimizing hides the panel in the menu bar; **open panel** brings it back. Servers keep running while moko
is open. Quitting stops only the servers moko owns.

## Local servers and data

| Server | Address | Data |
| --- | --- | --- |
| PostgreSQL | `127.0.0.1:15432` | `~/Library/Application Support/moko/databases/postgresql/18` |
| MariaDB | `127.0.0.1:13306` | `~/Library/Application Support/moko/database` |
| PHP | `127.0.0.1:8080` | your project folder |

Passwords are stored in the macOS Keychain. Do not remove the data folders to update the app.

## An installed MySQL service

When the connection points to Oracle's MySQL installed on this Mac, the overview shows **start**, **stop**
and **restart**. Each action asks for the administrator password. In **settings → connection**,
**authorize once** (optional) saves a root-owned script limited to those three actions on that service and
port, and a `sudo` rule that lets your user run it without a password. From then on any program in your
account can start and stop that MySQL. **remove authorization** deletes both files.

## Tables

Data refresh can be manual or every five or ten seconds; it pauses while you edit or when the window is
hidden. The three-dot menu next to the table name offers **rename table** and **empty table**. Emptying
removes every row with TRUNCATE and always goes through the destructive review. **delete database** is
unavailable for each engine's system databases.

In the **structure** tab, **new index or constraint** opens a form for an index, primary key, unique key,
foreign key or check on PostgreSQL, MariaDB and MySQL. On MariaDB and MySQL a foreign key references tables
of the same database.

## SQL objects

With a database selected, the sidebar groups **procedures**, **functions**, **triggers**, **events** and
**views**. **new object** opens a form for the name, parameters and attributes of each kind, with an editor
for the SQL body; no DELIMITER commands are needed.

Select an object to read or copy its full definition. **edit body** keeps the name, parameters, definer and
other attributes. Replacing the body of routines, triggers and events is available on MariaDB; on external
MySQL servers use the SQL tab. Procedures and functions can be run with parameter fields, including OUT and
INOUT; confirm first, since they can change data. New events start disabled, and turning on the event
scheduler affects every database on the server.

## AI agents (MCP)

In **settings → agents**, **let ai agents use moko** lets agents such as Claude Code use moko through the
Model Context Protocol. Access is off by default.

- The agent starts moko's own executable with `--mcp` and talks over standard input and output. No network
  port is opened and the moko window does not need to be open.
- Tools: `list_connections`, `list_databases`, `list_tables`, `describe_table` and `run_sql`. They use the
  connections and passwords already saved in the Keychain; the password is never handed to the agent.
- **read only** (default) accepts a single `select`, `show`, `describe`, `explain`, `with`, `table` or
  `values` statement at a time, run inside a read-only transaction. **read and write** runs any SQL with the
  saved account of the connection. The read-only guard prevents accidents, but the real limit is the
  privilege of the database account: for sensitive data use an account that can only read.
- **add to claude code** registers the server in Claude Code. The other buttons copy the equivalent command
  and the JSON for other agents. After moving moko to another folder, run the setup again.
- Every call is recorded in `~/Library/Application Support/moko/Agent Activity.log`.
- Whatever the agent reads is then handled by that agent's own service, outside moko.

## Export and import

Select the database, open the three-dot menu and choose **export sql**. The export includes structure,
data, views, procedures, functions, triggers and events, as far as the connected account is allowed. It
runs in the background and can be cancelled; a partial file is removed. The connection password is never
placed on the command line or in the SQL file.

Each engine uses its own tool: the included `pg_dump` for PostgreSQL, the included `mariadb-dump` for
MariaDB and the locally installed `mysqldump` for an existing MySQL (moko tells you when it is missing).
