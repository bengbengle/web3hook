<h1 align="center">
    <p align="center">Web3hook as a service</p>
</h1>

## Web3hook is the enterprise ready webhook service

Web3hook 使开发人员可以轻松发送 webhook。
开发人员进行一次 API 调用, web3hook 负责可交付性、重试、安全性等

# Building from source

您需要一个可用的 Rust 编译器来构建 web3hook 服务器。
最简单的方法是使用 [rustup](https://rustup.rs/)。

```
# 克隆存储库
git clone https://github.com/bengbengle/web3hook
# 切换到源目录
cd web3hook/server/
# Build
cargo install --path server
```

# Development

## Setup your environment

确保你有一个可用的 Rust 编译（例如通过使用 [rustup](https://rustup.rs/)）。

安装 rustup 后，确保通过运行以下命令设置 "stable" 工具链：
```
$ rustup default stable
```

之后请安装以下组件:
```
$ rustup component add clippy rust-src cargo rustfmt
```

Install SQLx CLI for database migrations
```
$ cargo install sqlx-cli
```

开发时自动重新加载：
```
$ cargo install cargo-watch
```

## Run the development server

要运行自动重新加载开发服务器运行：
```
# 移动到内部 server 目录
cd server
cargo watch -x run
```

然而, 这会失败, 因为您还需要将服务器指向数据库并设置一些其他配置。

实现这一目标的最简单方法是使用 docker-compose 设置 dockerize 开发环境和相关配置。

```
cp development.env .env
# 设置 docker（根据您的设置可能需要 sudo）
docker-compose up
```

再次运行 `cargo watch -x run` 针对您的本地 docker 环境启动开发服务器

现在生成一个授权令牌，你可以通过运行来完成：
```
cargo run jwt generate
```

### Run the SQL migrations

最后一个缺失的部分是运行 SQL 迁移。

从与 .env 文件相同的目录运行:
```
cargo sqlx migrate run
```

More useful commands:
```
# 查看迁移及其状态
cargo sqlx migrate info
# 恢复最新的迁移
cargo sqlx migrate revert
```

## Creating new SQL migration

正如您在运行/还原迁移之前看到的那样。要生成新的迁移，您只需运行：
```
cargo sqlx migrate add -r MIGRATION_NAME
```

并填写创建的迁移文件。


## Linting

请在推送代码之前运行这两个命令：

```
cargo clippy --fix
cargo fmt
```

## Testing

默认情况下，`cargo test` 将运行完整的测试套件，假设正在运行的 PostgreSQL 和 Redis 数据库。
这些数据库配置了与运行实际服务器相同的环境变量。

让这些测试通过的最简单方法是:
    1. Use the `testing-docker-compose.yml` file with `docker-compose` to launch the databases on their default ports.
    2. Create a `.env` file as you would when running the server for real.
    3. Migrate the database with `cargo run -- migrate`.
    4. Run `cargo test --all-targets`

或者，如果您只对运行单元测试感兴趣，则可以只运行 `cargo test --lib`。
这些测试不对周围环境做出任何假设。

要仅运行特定测试（例如，仅应用程序测试）, 您可以使用支持常见 Unix glob 模式的 `cargo test` 的 `--test` 标志。
例如：`cargo test --test '*app*'`。
