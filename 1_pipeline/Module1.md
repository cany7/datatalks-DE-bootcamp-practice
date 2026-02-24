# Module 1 — Containerized Data Pipeline

## Project Structure

```
1_pipeline/
├── ny_taxi.ipynb        # Exploratory notebook: data inspection & iterative ingestion
├── pipeline.py          # Simple ETL exercise: write a dummy DataFrame to Parquet
├── pg_ingest_data.py    # Main script: ingest NYC Taxi CSV into PostgreSQL
├── Dockerfile           # Containerize pg_ingest_data.py using uv + python:3.12-slim
├── docker-compose.yaml  # Launch PostgreSQL + pgAdmin together with a single command
└── queries.sql          # SQL queries: joins, data quality checks, aggregations
```

---

## What Each File Does

### `ny_taxi.ipynb`
- Downloads the NYC Yellow Taxi dataset (2021-01) from the DataTalksClub GitHub releases as a `.csv.gz` file
- Explores the raw data using `df.head()`, `df.dtypes`, and `df.shape`
- Identifies columns with ambiguous/mixed types (e.g. `store_and_fwd_flag` inferred as `object`)
- Defines an explicit `dtype` mapping for all columns to avoid chunk-based type inference issues
- Uses `parse_dates` to parse `tpep_pickup_datetime` and `tpep_dropoff_datetime` as proper datetime types
- Connects to a local PostgreSQL instance via SQLAlchemy `create_engine`
- Inspects the SQL DDL schema using `pd.io.sql.get_schema()` before writing
- Creates an empty target table using `df.head(0).to_sql(..., if_exists='replace')`
- Iterates over the full dataset in chunks of 100,000 rows using `pd.read_csv(..., iterator=True, chunksize=100000)`
- Inserts each chunk with `to_sql(..., if_exists='append')` and tracks progress with `tqdm`
- This notebook is the **exploratory prototype** that `pg_ingest_data.py` was refactored from

### `pipeline.py`
- A standalone ETL exercise script to practice Docker containerization (not related to PostgreSQL)
- Reads a month argument from `sys.argv`
- Creates a small dummy DataFrame with columns `A` and `B`
- Writes the DataFrame to a Parquet file named `output_<month>.parquet`
- This script is the entry point for the **earlier Dockerfile version** (before it was updated)

### `pg_ingest_data.py`
- The production-ready refactor of `ny_taxi.ipynb`, implemented as a **CLI tool using `click`**
- Accepts the following CLI options (all with sensible defaults):
  - `--year` / `--month`: selects which monthly data file to download
  - `--pg-user`, `--pg-pass`, `--pg-host`, `--pg-port`, `--pg-db`: PostgreSQL connection parameters
  - `--target-table`: name of the destination table in the database
  - `--chunksize`: number of rows per insert batch (default: 100,000)
- Constructs the download URL dynamically from the year/month parameters
- Connects to PostgreSQL using SQLAlchemy and `psycopg2`
- Uses the same explicit `dtype` mapping and `parse_dates` as the notebook to ensure schema stability
- Creates the target table on the first chunk (`if_exists='replace'`), then appends subsequent chunks
- Displays a `tqdm` progress bar per chunk during ingestion
- Originally used `argparse`; refactored to `click` for cleaner decorator-based CLI definition (original code kept as a comment at the bottom)

### `Dockerfile`
- Multi-stage build: copies the `uv` binary from the official `ghcr.io/astral-sh/uv` image
- Base image: `python:3.12.12-slim` for a small footprint
- Sets `/app` as the working directory and adds `.venv/bin` to `PATH`
- Copies `pyproject.toml` and `uv.lock` first to maximize layer cache reuse
- Runs `uv sync --locked --no-dev` to install only production dependencies from the lock file (reproducible builds, dev tools like jupyter/pgcli excluded)
- Copies `pg_ingest_data.py` into the container
- Entry point: `python pg_ingest_data.py` — CLI args are passed at `docker run` time

### `docker-compose.yaml`
- Defines two services: `pgdatabase` (PostgreSQL 18) and `pgadmin` (pgAdmin 4 web UI)
- Uses named volumes (`ny_taxi_postgres_data`, `pgadmin_data`) to persist data across restarts
- Exposes PostgreSQL on port `5432` and pgAdmin on port `8085`
- No manual `docker network create` needed — Compose creates a shared default network automatically
- Services discover each other by service name (e.g. `pgdatabase` is the hostname for PostgreSQL)

### `queries.sql`
- Collection of SQL queries to run against the ingested NYC Taxi data in pgAdmin or pgcli
- **Section 1 — Inner Joins:** implicit and explicit INNER JOIN between `yellow_taxi_trips` and `zones`
- **Section 2 — Data Quality Checks:** find NULL location IDs; find location IDs not present in `zones`
- **Section 3 — Outer Joins:** LEFT, RIGHT, and FULL OUTER JOIN examples (with a deleted zone to demonstrate NULLs)
- **Section 4 — GROUP BY:** count trips per calendar day
- **Section 5 — ORDER BY:** sort results by day (ASC) or trip count (DESC)
- **Section 6 — Other Aggregations:** per-day `COUNT`, `MAX(total_amount)`, `MAX(passenger_count)`
- **Section 7 — GROUP BY Multiple Fields:** group by day + dropoff location using positional column references

---

## How to Run & Test

### Prerequisites
- Docker daemon running (Docker Desktop, Colima, or OrbStack)
- `uv` installed (`brew install uv`)

### Step 1 — Start Docker daemon (if using Colima)

```bash
colima start
```

### Step 2 — Start a PostgreSQL container

```bash
docker run -d \
  --name pg-ny-taxi \
  -e POSTGRES_USER=root \
  -e POSTGRES_PASSWORD=root \
  -e POSTGRES_DB=ny_taxi \
  -p 5432:5432 \
  postgres:16
```

### Step 3 — Option A: Run locally with uv (no Docker build needed)

```bash
# From project root
uv sync
uv run python 1_pipeline/pg_ingest_data.py \
  --year 2021 --month 1 \
  --pg-user root --pg-pass root \
  --pg-host localhost --pg-port 5432 \
  --pg-db ny_taxi \
  --target-table yellow_taxi_data
```

### Step 3 — Option B: Build the Docker image and run inside a container

```bash
# Build image (run from 1_pipeline/ directory)
docker build -t ingest ./1_pipeline
```

There are two ways to connect the ingest container to PostgreSQL:

**B-1: PostgreSQL is running on your host machine (simplest)**

Use `host.docker.internal` — Docker on Mac automatically resolves this to the host's localhost:

```bash
docker run -it --rm ingest \
  --year 2021 --month 1 \
  --pg-user root --pg-pass root \
  --pg-host host.docker.internal --pg-port 5432 \
  --pg-db ny_taxi \
  --target-table yellow_taxi_data
```

**B-2: PostgreSQL is also running in a container — use a shared Docker network** ⭐

By default, Docker containers are isolated from each other and cannot resolve each other by container name. A custom Docker network enables automatic DNS resolution, so containers on the same network can reach each other using the **container name as hostname**.

```bash
# 1. Create a shared network (one-time setup)
docker network create pg-network

# 2. Start PostgreSQL container — join the network and give it a name
docker run -d \
  --name pgdatabase \
  --network pg-network \
  -e POSTGRES_USER=root \
  -e POSTGRES_PASSWORD=root \
  -e POSTGRES_DB=ny_taxi \
  -p 5432:5432 \
  postgres:16

# 3. Run ingest container on the same network — use container name as host
docker run -it --rm \
  --network pg-network \
  ingest \
  --year 2021 --month 1 \
  --pg-user root --pg-pass root \
  --pg-host pgdatabase --pg-port 5432 \
  --pg-db ny_taxi \
  --target-table yellow_taxi_data
```

> **Why `--pg-host=pgdatabase`?** Because both containers are on the same `pg-network`, Docker's built-in DNS resolves the container name `pgdatabase` directly to its internal IP. Without `--network`, this hostname would be unresolvable and the connection would fail.

### Step 4 — Verify the data (optional)

```bash
# Using pgcli (already in dev dependencies)
uv run pgcli -h localhost -p 5432 -u root -d ny_taxi

# Inside pgcli:
SELECT COUNT(*) FROM yellow_taxi_data;
SELECT * FROM yellow_taxi_data LIMIT 5;
```

### Step 5 — Run pgAdmin alongside PostgreSQL (Docker network)

pgAdmin is a web-based GUI for browsing and querying the database. Both pgAdmin and PostgreSQL must be on the same Docker network so they can discover each other by container name.

```bash
# Create a shared virtual network (one-time setup)
docker network create pg-network

# Start PostgreSQL on that network
docker run -it \
  -e POSTGRES_USER="root" \
  -e POSTGRES_PASSWORD="root" \
  -e POSTGRES_DB="ny_taxi" \
  -v ny_taxi_postgres_data:/var/lib/postgresql \
  -p 5432:5432 \
  --network=pg-network \
  --name pgdatabase \
  postgres:18

# In another terminal, start pgAdmin on the same network
docker run -it \
  -e PGADMIN_DEFAULT_EMAIL="admin@admin.com" \
  -e PGADMIN_DEFAULT_PASSWORD="root" \
  -v pgadmin_data:/var/lib/pgadmin \
  -p 8085:80 \
  --network=pg-network \
  --name pgadmin \
  dpage/pgadmin4
```

> The `-v pgadmin_data:/var/lib/pgadmin` volume saves pgAdmin settings (saved connections, preferences) so you don't have to reconfigure them after every restart.

**Connect pgAdmin to PostgreSQL:**

1. Open [http://localhost:8085](http://localhost:8085) in your browser
2. Log in — Email: `admin@admin.com`, Password: `root`
3. Right-click **Servers** → **Register** → **Server**
4. **General** tab → Name: `Local Docker`
5. **Connection** tab:
   - Host: `pgdatabase` (the container name — resolved via Docker DNS)
   - Port: `5432`
   - Username: `root`  /  Password: `root`
6. Click **Save**

> **Tip:** If using Docker Compose (Step 7), skip this manual network setup — Compose creates the network automatically and pgAdmin can connect using the same `pgdatabase` hostname.

### Step 6 — Run SQL queries in pgAdmin

Once connected, open the **Query Tool** (right-click on the `ny_taxi` database → Query Tool) and run queries from `queries.sql`.

**Prerequisite:** the `zones` lookup table must be loaded. You can ingest it the same way as the taxi trips data, or import the CSV directly via pgAdmin.

Key queries covered in `queries.sql`:

```sql
-- INNER JOIN: taxi trips with pickup/dropoff zone names
SELECT
    tpep_pickup_datetime, tpep_dropoff_datetime, total_amount,
    CONCAT(zpu."Borough", ' | ', zpu."Zone") AS "pickup_loc",
    CONCAT(zdo."Borough", ' | ', zdo."Zone") AS "dropoff_loc"
FROM yellow_taxi_trips t
JOIN zones zpu ON t."PULocationID" = zpu."LocationID"
JOIN zones zdo ON t."DOLocationID" = zdo."LocationID"
LIMIT 100;

-- Count trips per day, ordered by busiest day
SELECT
    CAST(tpep_dropoff_datetime AS DATE) AS "day",
    COUNT(1) AS "count"
FROM yellow_taxi_trips
GROUP BY 1
ORDER BY "count" DESC
LIMIT 100;
```

See `queries.sql` for the full set of queries (data quality checks, outer joins, multi-field aggregations).

---

## Docker Compose — Start PostgreSQL + pgAdmin with One Command

Instead of running separate `docker run` commands for PostgreSQL and pgAdmin, `docker-compose.yaml` lets you start (and stop) both services together.

Docker Compose automatically creates a shared network for all services in the file — no manual `docker network create` is needed. Each service is reachable by its **service name** as the hostname (e.g. `pgdatabase`).

### Start all services (foreground)

```bash
# From the 1_pipeline/ directory
docker-compose up
```

Press `Ctrl+C` to stop.

### Start in detached mode (background)

```bash
docker-compose up -d
```

### Stop and remove containers

```bash
docker-compose down
```

### Stop, remove containers AND volumes

```bash
# ⚠️ This deletes all persisted data in the named volumes
docker-compose down -v
```

### Other useful commands

```bash
# View service logs
docker-compose logs

# View logs for a specific service
docker-compose logs pgdatabase
```

### Access pgAdmin

Open [http://localhost:8085](http://localhost:8085) in your browser and log in with:
- **Email:** `admin@admin.com`
- **Password:** `root`

Then register a new server with:
- **Host:** `pgdatabase`  (the Compose service name — DNS resolved automatically)
- **Port:** `5432`
- **Username / Password:** `root` / `root`

### Run the ingest container against the Compose network

When PostgreSQL is started via `docker-compose`, the ingest container must join the same auto-created network (named `<folder>_default`, e.g. `1_pipeline_default`):

```bash
# Find the Compose network name
docker network ls

# Run ingest against the Compose network (replace network name if different)
docker run -it --rm \
  --network=1_pipeline_default \
  ingest \
  --year 2021 --month 1 \
  --pg-user root --pg-pass root \
  --pg-host pgdatabase --pg-port 5432 \
  --pg-db ny_taxi \
  --target-table yellow_taxi_data
```

---

## Cleanup — Free Up Docker Resources

### Stop running services

```bash
docker-compose down
```

### Remove specific containers

```bash
# List all containers (including stopped ones)
docker ps -a

# Remove a specific container
docker rm <container_id>

# Remove all stopped containers
docker container prune
```

### Remove Docker images

```bash
# List all images
docker images

# Remove specific images
docker rmi ingest
docker rmi test:pandas

# Remove all unused images
docker image prune -a
```

### Remove Docker volumes

```bash
# List volumes
docker volume ls

# Remove specific volumes
docker volume rm 1_pipeline_ny_taxi_postgres_data
docker volume rm 1_pipeline_pgadmin_data

# Remove all unused volumes
docker volume prune
```

### Remove Docker networks

```bash
# List networks
docker network ls

# Remove a specific network
docker network rm pg-network

# Remove all unused networks
docker network prune
```

### Complete cleanup (⚠️ removes everything)

```bash
# Removes ALL Docker resources including images, containers, volumes and networks
docker system prune -a --volumes
```

### Clean up local files

```bash
# Remove generated Parquet files
rm *.parquet

# Remove Python cache directories
rm -rf __pycache__ .pytest_cache

# Remove virtual environment (if using plain venv instead of uv)
rm -rf .venv
```

---

# 模块 1 — 容器化数据管道

## 项目结构

```
1_pipeline/
├── ny_taxi.ipynb        # 探索性 Notebook：数据检查与分块写入
├── pipeline.py          # 简单 ETL 练习：将 dummy DataFrame 写入 Parquet
├── pg_ingest_data.py    # 主脚本：将 NYC Taxi CSV 数据写入 PostgreSQL
├── Dockerfile           # 将 pg_ingest_data.py 容器化（uv + python:3.12-slim）
├── docker-compose.yaml  # 一条命令同时启动 PostgreSQL 和 pgAdmin
└── queries.sql          # SQL 查询：连接、数据质量检查、聚合统计
```

---

## 每个文件的作用

### `ny_taxi.ipynb`
- 从 DataTalksClub 的 GitHub Releases 下载 NYC 黄出租车数据集（2021-01），格式为 `.csv.gz`
- 用 `df.head()`、`df.dtypes`、`df.shape` 探索原始数据
- 发现部分列（如 `store_and_fwd_flag`）因类型推断不稳定，被推断为 `object`
- 手动定义 `dtype` 字典，对所有列显式指定类型，避免分块读取时的类型不一致问题
- 用 `parse_dates` 将 `tpep_pickup_datetime` 和 `tpep_dropoff_datetime` 解析为 datetime 类型
- 通过 SQLAlchemy `create_engine` 连接本地 PostgreSQL
- 使用 `pd.io.sql.get_schema()` 在写入前预览 SQL DDL 建表语句
- 用 `df.head(0).to_sql(..., if_exists='replace')` 先建空表
- 用 `pd.read_csv(..., iterator=True, chunksize=100000)` 分块读取完整数据集
- 每块用 `to_sql(..., if_exists='append')` 写入，并用 `tqdm` 显示进度条
- 这个 Notebook 是 `pg_ingest_data.py` 的**原型探索版本**

### `pipeline.py`
- 独立的 ETL 练习脚本，用于练习 Docker 容器化（与 PostgreSQL 无关）
- 从 `sys.argv` 读取 month 参数
- 创建一个简单的 dummy DataFrame（列 A 和 B）
- 将 DataFrame 写入名为 `output_<month>.parquet` 的 Parquet 文件
- 这是**早期 Dockerfile 版本**对应的入口脚本

### `pg_ingest_data.py`
- `ny_taxi.ipynb` 的生产级重构版本，使用 **`click` 实现 CLI 工具**
- 支持以下 CLI 参数（均有合理默认值）：
  - `--year` / `--month`：选择要下载的月份数据
  - `--pg-user`、`--pg-pass`、`--pg-host`、`--pg-port`、`--pg-db`：PostgreSQL 连接参数
  - `--target-table`：目标表名
  - `--chunksize`：每批写入的行数（默认 100,000）
- 根据年份和月份动态拼接下载 URL
- 使用 SQLAlchemy + `psycopg2` 连接 PostgreSQL
- 沿用 Notebook 中相同的 `dtype` 映射和 `parse_dates`，确保 schema 稳定
- 第一个 chunk 建表（`if_exists='replace'`），后续 chunk 追加（`if_exists='append'`）
- 每个 chunk 用 `tqdm` 显示进度条
- 原版用 `argparse` 编写，后重构为 `click` 的装饰器风格（原始代码保留在文件末尾注释中）

### `Dockerfile`
- 多阶段构建：从官方 `ghcr.io/astral-sh/uv` 镜像复制 `uv` 二进制文件
- 基础镜像：`python:3.12.12-slim`，体积小
- 工作目录设为 `/app`，并将 `.venv/bin` 加入 `PATH`
- 先复制 `pyproject.toml` 和 `uv.lock`，充分利用 Docker 层缓存
- 运行 `uv sync --locked --no-dev` 从锁定文件安装所有**生产**依赖（可复现构建，不包含 jupyter/pgcli 等开发工具）
- 将 `pg_ingest_data.py` 复制进容器
- 入口点为 `python pg_ingest_data.py`，CLI 参数在 `docker run` 时传入

### `docker-compose.yaml`
- 定义两个服务：`pgdatabase`（PostgreSQL 18）和 `pgadmin`（pgAdmin 4 Web UI）
- 使用具名卷（`ny_taxi_postgres_data`、`pgadmin_data`）在容器重启后保留数据
- PostgreSQL 暴露在宿主机端口 `5432`，pgAdmin 暴露在端口 `8085`
- 无需手动 `docker network create`——Compose 会自动创建共享网络
- 各服务通过服务名互相发现（例如 PostgreSQL 的 hostname 即为 `pgdatabase`）

### `queries.sql`
- 针对已导入的 NYC Taxi 数据，在 pgAdmin 或 pgcli 中执行的 SQL 查询集合
- **第 1 节 — 内连接：** 对 `yellow_taxi_trips` 和 `zones` 的隐式与显式 INNER JOIN
- **第 2 节 — 数据质量检查：** 查找 NULL 的 LocationID；查找 zones 表中不存在的 LocationID
- **第 3 节 — 外连接：** LEFT / RIGHT / FULL OUTER JOIN 示例（通过删除一条 zone 演示 NULL）
- **第 4 节 — GROUP BY：** 按日期统计每天的行程数
- **第 5 节 — ORDER BY：** 按日期升序或按行程数降序排列
- **第 6 节 — 其他聚合：** 每天的行程数、最高金额、最大乘客数
- **第 7 节 — 多字段 GROUP BY：** 按日期和下车地点分组，使用位置化列引用

---

## 如何运行和测试

### 前置条件
- Docker daemon 已启动（Docker Desktop、Colima 或 OrbStack 任选其一）
- 已安装 `uv`（`brew install uv`）

### 第一步 — 启动 Docker daemon（以 Colima 为例）

```bash
colima start
```

### 第二步 — 启动 PostgreSQL 容器

```bash
docker run -d \
  --name pg-ny-taxi \
  -e POSTGRES_USER=root \
  -e POSTGRES_PASSWORD=root \
  -e POSTGRES_DB=ny_taxi \
  -p 5432:5432 \
  postgres:16
```

### 第三步 — 方式 A：本地用 uv 直接运行（无需 build 镜像）

```bash
# 从项目根目录执行
uv sync
uv run python 1_pipeline/pg_ingest_data.py \
  --year 2021 --month 1 \
  --pg-user root --pg-pass root \
  --pg-host localhost --pg-port 5432 \
  --pg-db ny_taxi \
  --target-table yellow_taxi_data
```

### 第三步 — 方式 B：Build Docker 镜像后在容器内运行

```bash
# 在项目根目录 build 镜像
docker build -t ingest ./1_pipeline
```

连接 PostgreSQL 有两种方式：

**B-1：PostgreSQL 跑在宿主机本地（最简单）**

用 `host.docker.internal`，Docker on Mac 会自动将其解析为宿主机的 localhost：

```bash
docker run -it --rm ingest \
  --year 2021 --month 1 \
  --pg-user root --pg-pass root \
  --pg-host host.docker.internal --pg-port 5432 \
  --pg-db ny_taxi \
  --target-table yellow_taxi_data
```

**B-2：PostgreSQL 也跑在容器里——用 Docker 自定义网络** ⭐

Docker 容器默认互相隔离，无法通过容器名互相访问。创建一个自定义网络后，同一网络内的容器可以直接用**容器名作为 hostname** 互相访问（Docker 内置 DNS 自动解析）。

```bash
# 1. 创建共享网络（只需执行一次）
docker network create pg-network

# 2. 启动 PostgreSQL 容器，加入该网络并指定容器名
docker run -d \
  --name pgdatabase \
  --network pg-network \
  -e POSTGRES_USER=root \
  -e POSTGRES_PASSWORD=root \
  -e POSTGRES_DB=ny_taxi \
  -p 5432:5432 \
  postgres:16

# 3. 运行 ingest 容器，加入同一网络，用容器名作为 host
docker run -it --rm \
  --network pg-network \
  ingest \
  --year 2021 --month 1 \
  --pg-user root --pg-pass root \
  --pg-host pgdatabase --pg-port 5432 \
  --pg-db ny_taxi \
  --target-table yellow_taxi_data
```

> **为什么 `--pg-host=pgdatabase`？** 因为两个容器都在 `pg-network` 里，Docker 内置的 DNS 会把容器名 `pgdatabase` 自动解析成它的内网 IP。如果不加 `--network`，这个 hostname 根本无法解析，连接会直接报错。

### 第四步 — 验证数据（可选）

```bash
# 使用 pgcli（已在 dev 依赖中）
uv run pgcli -h localhost -p 5432 -u root -d ny_taxi

# 在 pgcli 内执行：
SELECT COUNT(*) FROM yellow_taxi_data;
SELECT * FROM yellow_taxi_data LIMIT 5;
```

### 第五步 — 在 Docker 网络中同时运行 pgAdmin 和 PostgreSQL

pgAdmin 是一个基于 Web 的数据库管理工具，比 pgcli 更适合处理复杂查询。pgAdmin 和 PostgreSQL 必须在同一个 Docker 网络中，才能通过容器名互相发现。

```bash
# 创建共享虚拟网络（只需执行一次）
docker network create pg-network

# 在该网络中启动 PostgreSQL
docker run -it \
  -e POSTGRES_USER="root" \
  -e POSTGRES_PASSWORD="root" \
  -e POSTGRES_DB="ny_taxi" \
  -v ny_taxi_postgres_data:/var/lib/postgresql \
  -p 5432:5432 \
  --network=pg-network \
  --name pgdatabase \
  postgres:18

# 在另一个终端中，在同一网络启动 pgAdmin
docker run -it \
  -e PGADMIN_DEFAULT_EMAIL="admin@admin.com" \
  -e PGADMIN_DEFAULT_PASSWORD="root" \
  -v pgadmin_data:/var/lib/pgadmin \
  -p 8085:80 \
  --network=pg-network \
  --name pgadmin \
  dpage/pgadmin4
```

> `-v pgadmin_data:/var/lib/pgadmin` 卷映射会保存 pgAdmin 的配置（已保存的连接、偏好设置），避免每次重启都需要重新配置。

**将 pgAdmin 连接到 PostgreSQL：**

1. 在浏览器打开 [http://localhost:8085](http://localhost:8085)
2. 登录：Email `admin@admin.com`，密码 `root`
3. 右键点击 **Servers** → **Register** → **Server**
4. **General** 标签页 → Name: `Local Docker`
5. **Connection** 标签页：
   - Host: `pgdatabase`（容器名，由 Docker DNS 自动解析）
   - Port: `5432`
   - Username: `root` / Password: `root`
6. 点击 **Save**

> **提示：** 如果使用 Docker Compose（第七步），可跳过上述手动网络配置——Compose 自动创建网络，pgAdmin 同样可以用 `pgdatabase` 作为 hostname 连接。

### 第六步 — 在 pgAdmin 中执行 SQL 查询

连接成功后，右键点击 `ny_taxi` 数据库 → **Query Tool**，将 `queries.sql` 中的查询粘贴进去执行。

**前置条件：** 需要先加载 `zones` 区域对照表。可以用与导入出租车数据相同的方式导入，或直接通过 pgAdmin 导入 CSV。

`queries.sql` 中的核心查询示例：

```sql
-- 内连接：出租车行程与上车/下车区域名称
SELECT
    tpep_pickup_datetime, tpep_dropoff_datetime, total_amount,
    CONCAT(zpu."Borough", ' | ', zpu."Zone") AS "pickup_loc",
    CONCAT(zdo."Borough", ' | ', zdo."Zone") AS "dropoff_loc"
FROM yellow_taxi_trips t
JOIN zones zpu ON t."PULocationID" = zpu."LocationID"
JOIN zones zdo ON t."DOLocationID" = zdo."LocationID"
LIMIT 100;

-- 按天统计行程数，按最繁忙的日期排序
SELECT
    CAST(tpep_dropoff_datetime AS DATE) AS "day",
    COUNT(1) AS "count"
FROM yellow_taxi_trips
GROUP BY 1
ORDER BY "count" DESC
LIMIT 100;
```

完整查询（数据质量检查、外连接、多字段聚合）见 `queries.sql`。

---

## Docker Compose — 一条命令启动 PostgreSQL + pgAdmin

相比分别执行多条 `docker run` 命令，`docker-compose.yaml` 让你一条命令同时启动（或停止）所有服务。

Docker Compose 会自动为文件中所有服务创建一个共享网络，无需手动 `docker network create`。每个服务可以直接用**服务名**作为 hostname 互相访问（例如 `pgdatabase`）。

### 前台启动所有服务

```bash
# 在 1_pipeline/ 目录下执行
docker-compose up
```

按 `Ctrl+C` 停止。

### 后台（detached）模式启动

```bash
docker-compose up -d
```

### 停止并移除容器

```bash
docker-compose down
```

### 停止并同时删除容器和数据卷

```bash
# ⚠️ 此操作会删除具名卷中的所有持久化数据
docker-compose down -v
```

### 其他常用命令

```bash
# 查看所有服务的日志
docker-compose logs

# 查看特定服务的日志
docker-compose logs pgdatabase
```

### 访问 pgAdmin

在浏览器中打开 [http://localhost:8085](http://localhost:8085)，使用以下凭据登录：
- **Email：** `admin@admin.com`
- **Password：** `root`

然后注册一个新服务器：
- **Host：** `pgdatabase`（Compose 服务名，DNS 自动解析）
- **Port：** `5432`
- **Username / Password：** `root` / `root`

### 在 Compose 网络中运行 ingest 容器

通过 `docker-compose` 启动 PostgreSQL 后，ingest 容器必须加入 Compose 自动创建的网络（名称格式为 `<目录名>_default`，例如 `1_pipeline_default`）：

```bash
# 查看 Compose 创建的网络名称
docker network ls

# 加入该网络运行 ingest 容器（若网络名不同请替换）
docker run -it --rm \
  --network=1_pipeline_default \
  ingest \
  --year 2021 --month 1 \
  --pg-user root --pg-pass root \
  --pg-host pgdatabase --pg-port 5432 \
  --pg-db ny_taxi \
  --target-table yellow_taxi_data
```

---

## 清理 — 释放 Docker 资源

### 停止运行中的服务

```bash
docker-compose down
```

### 删除特定容器

```bash
# 列出所有容器（包括已停止的）
docker ps -a

# 删除特定容器
docker rm <container_id>

# 删除所有已停止的容器
docker container prune
```

### 删除 Docker 镜像

```bash
# 列出所有镜像
docker images

# 删除特定镜像
docker rmi ingest
docker rmi test:pandas

# 删除所有未使用的镜像
docker image prune -a
```

### 删除 Docker 数据卷

```bash
# 列出所有卷
docker volume ls

# 删除特定卷
docker volume rm 1_pipeline_ny_taxi_postgres_data
docker volume rm 1_pipeline_pgadmin_data

# 删除所有未使用的卷
docker volume prune
```

### 删除 Docker 网络

```bash
# 列出所有网络
docker network ls

# 删除特定网络
docker network rm pg-network

# 删除所有未使用的网络
docker network prune
```

### 完整清理（⚠️ 删除所有资源）

```bash
# 删除所有 Docker 资源，包括镜像、容器、卷和网络
docker system prune -a --volumes
```

### 清理本地文件

```bash
# 删除生成的 Parquet 文件
rm *.parquet

# 删除 Python 缓存目录
rm -rf __pycache__ .pytest_cache

# 删除虚拟环境（如果使用的是 venv 而非 uv）
rm -rf .venv
```
