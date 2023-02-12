<h1 align="center">
    <p align="center">Web3hook as a service</p>
</h1>

## Web3hook is the enterprise ready webhook service

web3hook makes it easy for developers to send webhooks. 
Developers make one API call, and web3hook takes care of deliverability, retries, security, and more. 

# Running the server

For information on how to use this server please refer to the [running the server](../README.md#running-the-server) in the main README.

# Building from source

You would need a working Rust complier in order to build web3hook server.
The easiest way is to use [rustup](https://rustup.rs/).

```
# Clone the repository
git clone https://github.com/bengbengle/web3hook
# Change to the source directory
cd web3hook/server/
# Build
cargo install --path web3hook-server
```

# Development

## Setup your environment

Make sure you have a working Rust compiled (e.g. by using [rustup](https://rustup.rs/)).

Once rustup is installed make sure to set up the `stable` toolchain by running:
```
$ rustup default stable
```

Afterwards please install the following components:
```
$ rustup component add clippy rust-src cargo rustfmt
```

Install SQLx CLI for database migrations
```
$ cargo install sqlx-cli
```

For automatic reload while developing:
```
$ cargo install cargo-watch
```

## Run the development server

To run the auto-reloading development server run:
```
# Move to the inner web3hook-server directory.
cd web3hook-server
cargo watch -x run
```

This however will fail, as you also need to point the server to the database and setup a few other configurations.

The easiest way to achieve that is to use docker-compose to setup a dockerize development environment, and the related config.

```
cp development.env .env
# Set up docker (may need sudo depending on your setup)
docker-compose up
```

Now run `cargo watch -x run` again to start the development server against your local docker environment.

Now generate an auth token, you can do it by running:
```
cargo run jwt generate
```

See [the main README](../README.md) for instructions on how to generate it in production.

### Run the SQL migrations

One last missing piece to the puzzle is running the SQL migrations.

From the same directory as the `.env` file run:
```
cargo sqlx migrate run
```

More useful commands:
```
# View the migrations and their status
cargo sqlx migrate info
# Reverting the latest migration
cargo sqlx migrate revert
```

## Creating new SQL migration

As you saw before you run/revert migrations. To generate new migrations you just run:
```
cargo sqlx migrate add -r MIGRATION_NAME
```

And fill up the created migration files.


## Linting

Please run these two commands before pushing code:

```
cargo clippy --fix
cargo fmt
```

## Testing

By default, `cargo test` will run the full test suite which assumes a running PostgreSQL and Redis database.
These databases are configured with the same environment variables as with running the actual server.

The easiest way to get these tests to pass is to:
    1. Use the `testing-docker-compose.yml` file with `docker-compose` to launch the databases on their default ports.
    2. Create a `.env` file as you would when running the server for real.
    3. Migrate the database with `cargo run -- migrate`.
    4. Run `cargo test --all-targets`

Alternatively, if you're only interested in running unit tests, you can just run `cargo test --lib`. These tests don't make any assumptions about the surrounding environment.

To run only a specific test (e.g. only the application tests), you can use the `--test` flag to `cargo test` which supports common Unix glob patterns. For example: `cargo test --test '*app*'`.
