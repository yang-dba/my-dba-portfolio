# 安装部署

## Mysql

### 1.单实例二进制安装

> [!important]
>
> **1.创建系统用户和组**
>
> ```bash
> # 创建系统 mysql 组和用户
> sudo groupadd mysql
> sudo useradd -r -g mysql -s /bin/false mysql
> ```
>
> **2.解压**
>
> ```bash
> # 解压到 /usr/local 目录 (x = extract（解压），f = file（指定文件）)
> sudo tar xf /tmp/mysql-8.0.36-linux-glibc2.17-x86_64.tar.xz -C /usr/local
> # 创建软链接
> sudo ln -s mysql-8.0.36-linux-glibc2.17-x86_64 mysql
> # 设置属主 和 属组（ 用操作系统的 mysql用 来管理数据库mysql ）
> sudo chown -R mysql:mysql /usr/local/mysql
> ```
>
> **3.创建数据目录**
>
> ```bash
> # 创建数据目录（建议独立磁盘分区）
> sudo mkdir -p /data/mysql/{data,logs,tmp}
> sudo chown -R mysql:mysql /data/mysql
> ```
>
> **4.配置环境变量**
>
> ```bash
> # 将 MySQL 的 bin 目录加入 PATH
> echo 'export PATH=/usr/local/mysql/bin:$PATH' | sudo tee /etc/profile.d/mysql.sh
> # 执行脚本
> source /etc/profile.d/mysql.sh
> # # 验证
> mysql --version
> ```
>
> **5.编写配置文件**
>
> ```bash
> sudo vim /etc/my.cnf
> 
> # 添加两个标签 [mysqld] [client]
> # 1.在 mysqld 标签下配置：基本路径、socket、日志、网络、字符集、InnoDB基本、安全相关
> # 2.在 client 标签下配置：socket、字符集
> ```
>
> **6.初始化数据库**
>
> ```bash
> sudo /usr/local/mysql/bin/mysqld --initialize --user=mysql
> # 查看临时密码
> grep 'temporary password' /data/mysql/logs/mysqld.log
> ```
>
> **7.注册系统服务**
>
> ```bash
> sudo tee /etc/systemd/system/mysqld.service > /dev/null << 'EOF'
> [Unit]
> Description=MySQL Server
> After=network.target
> 
> [Service]
> Type=notify
> User=mysql
> Group=mysql
> ExecStart=/usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf
> LimitNOFILE=65535
> LimitNPROC=65535
> Restart=on-failure
> RestartSec=10
> 
> [Install]
> WantedBy=multi-user.target
> EOF
> ```
>
> 重新加载 systemctl 配置
>
> ```bash
> # 重新加载 systemd 配置
> sudo systemctl daemon-reload
> 
> # 启动 MySQL
> sudo systemctl start mysqld
> sudo systemctl enable mysqld
> 
> # 查看 MySQL 服务是否已加入开机自启列表
> sudo systemctl is-enabled mysqld
> ```
>
> **8.登录修改密码**
>
> ```shell
> ALTER USER 'root'@'localhost' IDENTIFIED BY '';
> # mysql中完整的账户 = 'root'@'localhost' 也就是：用户名 + 主机名
> ```



### 2.主从复制搭建

#### 2.1 基于位点搭建

> 前置知识点
>
> - Mysql版本从库尽可能保证和主库一致，或者版本也不要高太多，至少大版本必须一致
> - ping检查主机存活，telnet 检查主库 3306 端口连通性，如果连不上检查
>   - Master 的 `bind-address` 是否绑定了 `127.0.0.1`
>   - 防火墙是否放行 3306 端口
>   - 云服务器安全组规则

**步骤1：Master 端 配置 my.cnf 文件**

```shell
-- 核心参数
server-id = 101       	# 复制拓扑中每个实例必须唯一
log-bin = mysql-bin 	# 开启 binlog 并设置文件名前缀
binlog_format = ROW    	# 行级复制，数据一致性最好 
sync_binlog = 1         # 防止主机宕机丢 binlog（性能换安全）
innodb_flush_log_at_trx_commit = 1        # 与 sync_binlog 双 1 配置，最高数据安全级别

-- 完成配置后启动数据库查看 Binlog 是否已开启

systemctl start mysqld		# 启动mysql
mysql -u root -p			# 登录 Master
SHOW BINARY LOG STATUS\G    # 查看 binlog 状态 MySQL 8.2+（8.0 用 SHOW MASTER STATUS\G）
# 看到 `File` 和 `Position` 就说明 binlog 已正常开启。
# 先 不要急着记录 这个位点——后面获取数据快照时会拿到准确的位点。
```

**步骤2：创建复制专用账户**

```sql
# 在 Master 上执行
CREATE USER 'repl'@'192.168.1.%' IDENTIFIED BY 'Repl_Str0ng!2024' PASSWORD EXPIRE NEVER;

# 授权，只给 slave 权限
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'192.168.1.%';
# CREATE USER 和 GRANT 语句属于隐式提交的 DDL 语句，
# MySQL 会自动刷新权限表，不需要手动执行 FLUSH PRIVILEGES。

# 验证账户
SHOW GRANTS FOR 'repl'@'192.168.1.%';
```

**步骤3：导出数据快照**

```sql
# 导出方案-1：mysqldump（推荐小数据量 < 50GB）
mysqldump -u root -p \
--all-databases \
--single-transaction \
--source-data=2 \
--routines \
--triggers \
--events \
--set-gtid-purged=OFF \
  > /tmp/master_full_dump.sql

# 导出方案-2：Xtrabackup（推荐大数据量 > 50GB）
xtrabackup --backup --user=root --password='YourPassword' --target-dir=/tmp/master_backup
xtrabackup --prepare --target-dir=/tmp/master_backup

# 将 dump 文件传输到 Slave
scp /tmp/master_full_dump.sql root@192.168.1.102:/tmp/
```

**步骤4：Slave  端 配置 my.cnf 文件**

```sql
# 必须知道的几个核心参数
server-id = 102       | 绝对不能和 Master 相同
relay-log = relay-bin | relay log 文件名前缀                    |
read_only = ON        | 防止误写 Slave                          |
super_read_only =  ON         | 更严格的只读，推荐 
log_slave_updates = ON        | Slave 的变更也写 binlog，级联复制时必需 \
```

**步骤5：导入 Master 数据快照**

```sql
# 重启 Slave 的 MySQL
sudo systemctl restart mysqld

# 如果用的是 mysqldump 拷贝的，导入用如下命令--------------------
mysql -u root -p < /tmp/master_full_dump.sql

# 如果用的 Xtrabackup-----------------------------------------
# 在 Slave 上停止 MySQL，清空数据目录，拷贝备份
sudo systemctl stop mysqld
sudo rm -rf /var/lib/mysql/*
xtrabackup --copy-back --target-dir=/tmp/master_backup
sudo chown -R mysql:mysql /var/lib/mysql
sudo systemctl start mysqld
```

**步骤6：配置 CHANGE REPLICATION SOURCE TO**

```sql
-- 在 Slave 上执行（MySQL 8.0.23+ 新语法）
CHANGE REPLICATION SOURCE TO
SOURCE_HOST = '192.168.1.101',
SOURCE_PORT = 3306,
SOURCE_USER = 'repl',
SOURCE_PASSWORD = 'Repl_Str0ng!2024',
SOURCE_LOG_FILE = 'mysql-bin.000003',
SOURCE_LOG_POS = 785,
SOURCE_CONNECT_RETRY = 10,
GET_SOURCE_PUBLIC_KEY = 1;

# 注意两个关键参数
- `SOURCE_LOG_FILE` 和 `SOURCE_LOG_POS` 的值必须和获取快照时记录的完全一致。
- 多一个字符少一个数字都不行。
- 如果搞错了，Slave 要么找不到位点报错，要么跳过了一些数据导致主从不一致（这种问题最难排查）
# 在主库上查看 MASTER_LOG_FILE 和 MASTER_LOG_POS
head -30 /tmp/master_full_dump.sql
```

**步骤7：启动复制并验证**

```sql
# 在 Slave 上执行
START REPLICA;  		# 旧语法：START SLAVE;
# 查看复制状态
SHOW REPLICA STATUS\G	# 旧语法：SHOW SLAVE STATUS\G

# 重点关注 两个「必须 Yes」
- 只要 `Replica_IO_Running` 和 `Replica_SQL_Running` 都是 Yes，
- 并且 `Last_IO_Error` 和 `Last_SQL_Error` 为空，复制就是正常的。
- Seconds_Behind_Source结果为0，说明 主从延迟为 0 秒（追平了）
```





#### 2.2 基于GTID搭建



> [!note]
>
> **环境：**
>
> - source端：RockyLinux 9.7 + Mysql 8.4
> - replica端：redhat 8 + Mysql 8.4

> **GTID复制核心流程**
>
> - 主库：事务提交 → 分配GTID → 写入binlog → 发给从库
>
> - 从库：接收GTID → 检查是否已执行 → 若无则执行 → 写入自己的binlog
>
> 关键：
>
> - 从库的`Executed_Gtid_Set`记录已执行过的GTID，
> - 主从切换时直接告诉新主库这个集合即可。

**步骤1：配置 Source 端 my.cnf 文件**

```sql
-- 必须知道几个重要参数：
server_id 			# 必须不同于从库
gtid_mode = ON  	# 开启 GTID 模式，所有事物必须带有 GTID
enforce_gtid_consistency = ON 	# 强制 GTID 一致性，禁止不兼容 GTID 的 SQL 语句
log_slave_updates = ON			# 将从库回放的事物也写入 binlog ,级联复制和故障切换必须配置
binlog_format = ROW		# 行格式复制，GTID 模式下必选

## 核心理解：
`gtid_mode = ON` + `enforce_gtid_consistency = ON`：
开启GTID后，主从复制不再靠文件名+位置，而是靠全局唯一的事务ID。
从库只需要告诉主库“我执行到哪个GTID”，主库自动计算差异。
`log_slave_updates = ON`：
从库回放的事务也写入自己的binlog。这是 级联复制和主从切换 的基础，否则从库不能当别人的主库。
```

**步骤2：source  端创建专门用于复制的账户**

```sql
# 启动 mysql
sudo systemctl restart mysqld
# 注意：使用 GRANT 语句无需执行 FLUSH PRIVILEGES，MySQL 会自动刷新权限表
CREATE USER 'repl'@'192.168.1.%' IDENTIFIED BY 'Repl_P@ss2024!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'192.168.1.%';
```

**步骤3：source  端 导出全量数据快照**

```sql
mysqldump -u root -p \
  --all-databases \
  --single-transaction \
  --routines --triggers --events \
  --set-gtid-purged=ON \
  > /tmp/master_full_dump.sql


# 将 dump 文件传到 Replica 端
scp /tmp/master_full_dump.sql root@192.168.1.102:/tmp/
```

**步骤4：配置 replica 端 my.cnf 文件**

```sql
--- 必须知道几个重要参数：
server_id			# 必须不同于主库
read_only = ON		# 阻止普通用户的写操作
super_read_only = ON
relay_log = /data/mysql/relay-bin	# 存储从主库接收的 binlog
relay_log_recovery = ON				# 崩溃恢复时自动清理损坏的 relay log

-- 配置完成检查配置是否正确
sudo /usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf --validate-config
```

**步骤5：replica 端 导入主库（即 source端）的 dump.sql 文件**

```sql
# 如果从库上执行过复制，则需要执行1,2,3步，若是全新则直接导入即可
STOP SLAVE; 		# 1. 停止从库复制
RESET SLAVE ALL;	# 2. 重置从库状态（清空复制信息）
RESET MASTER;		# 3. 清空 GTID 执行记录（关键！）

# 4. 导入主库的 dump 文件
mysql -u root -p < /tmp/master_full_dump.sql	
```

**步骤6：replica 端 配置 CHANGE REPLICATION SOURCE TO 使用 GTID**

```sql
-- MySQL 8.0.23+ 新语法
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = '192.168.1.101',
  SOURCE_USER = 'repl',
  SOURCE_PASSWORD = 'Repl_P@ss2024!',
  SOURCE_PORT = 3306,
  SOURCE_AUTO_POSITION = 1;
-- 旧语法：
CHANGE MASTER TO 
  MASTER_HOST = '...', 
  MASTER_USER = '...', 
  MASTER_PASSWORD = '...', 
  MASTER_PORT = 3306, 
  MASTER_AUTO_POSITION = 1;

-- MySQL 8.4
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = '192.168.0.181',
  SOURCE_USER = 'repl',
  SOURCE_PASSWORD = '123@qq.com',
  SOURCE_PORT = 3306,
  SOURCE_AUTO_POSITION = 1,   # 自动定位，使用 GTID 的核心参数，mysql能自动计算从哪开始复制
  GET_SOURCE_PUBLIC_KEY = 1;  # mysql8.4+解决认证问题的关键               
```

**步骤7：replica 端 启动复制并验证成功与否**

```sql
START REPLICA;		-- 旧语法：START SLAVE;
SHOW REPLICA STATUS\G

# 重点关注一下字段：
| Replica_IO_Running    | Yes               | IO 线程正常                       
| Replica_SQL_Running   | Yes               | SQL 线程正常                      
| Auto_Position         | 1                 | 确认使用 GTID 自动定位            
| Retrieved_Gtid_Set    | 与 Source 一致     | 已从主库接收到的 GTID             
| Executed_Gtid_Set     | 与 Retrieved 一致  | 已执行的 GTID（追上说明没有延迟） 
| Seconds_Behind_Source | 0                 | 主从延迟秒数     
```



常见故障:

| 现象                                        | 原因                                | 解决                                   |
| :------------------------------------------ | :---------------------------------- | :------------------------------------- |
| `Authentication requires secure connection` | `caching_sha2_password`需要安全连接 | `CHANGE ... GET_SOURCE_PUBLIC_KEY = 1` |
| `gtid_purged`设置失败                       | `gtid_executed`不为空               | `RESET MASTER`清空                     |
| `Access denied for 'repl'`                  | 复制用户密码错或权限不足            | 检查`GRANT REPLICATION SLAVE`          |



### 配置文件

#### my.cnf

##### 二进制安装mysql基本配置

```bash
[mysqld]
# 基本路径
basedir = /usr/local/mysql
datadir = /data/mysql/data
tmpdir  = /data/mysql/tmp
socket  = /data/mysql/mysql.sock
pid-file = /data/mysql/mysqld.pid

# 日志
log-error = /data/mysql/logs/mysqld.log

# 网络
port = 3306
bind-address = 0.0.0.0

# 字符集
character-set-server = utf8mb4
collation-server = utf8mb4_0900_ai_ci

# InnoDB 基础（Day 22 深入调优）
innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 1

# 安全
secure-file-priv = /data/mysql/tmp

[client]
socket = /data/mysql/mysql.sock
default-character-set = utf8mb4
```





##### 基于 位点 搭建一主一从

###### Master 端配置

```bash
[mysqld]
# ========== 复制相关 ==========
server-id = 101                        # 必须唯一，不能和 Slave 重复
log-bin = /var/lib/mysql/mysql-bin     # 开启 binlog，指定前缀
binlog_format = ROW                    # 行级复制，推荐
binlog_row_image = FULL                # 记录完整行数据

# ========== 数据安全 ==========
sync_binlog = 1                        # 每次事务提交都刷盘 binlog
innodb_flush_log_at_trx_commit = 1     # 每次事务提交都刷盘 redo log

# ========== 可选但推荐 ==========
binlog_expire_logs_seconds = 604800    # binlog 保留 7 天（8.0 推荐用这个参数）
max_binlog_size = 256M                 # 单个 binlog 文件最大 256MB
```

###### Slave端配置

```bash
[mysqld]
# ========== 复制相关 ==========
server-id = 102                        # 必须和 Master 不同
relay-log = /var/lib/mysql/relay-bin    # relay log 前缀
relay_log_purge = ON                   # 自动清理已执行的 relay log
read_only = ON                         # Slave 设为只读（普通用户不可写）
super_read_only = ON                   # 连 SUPER 权限的用户也不能写（8.0 推荐）

# ========== 可选但推荐 ==========
log-bin = /var/lib/mysql/mysql-bin      # Slave 也开 binlog（级联复制、备份需要）
log_slave_updates = ON                 # 把从 Master 复制来的变更也写入自己的 binlog
```







##### 基于 GTID 搭建一主一从

###### source端

> mysql数据目录：`/data/mysql`
>
> 软硬件信息：2核4G-rockylinux9.7

```bash
[mysqld]
# 基本路径
basedir = /usr/local/mysql
datadir = /data/mysql/data
tmpdir  = /data/mysql/tmp
socket  = /data/mysql/mysql.sock
pid-file = /data/mysql/mysqld.pid

# 日志
log-error = /data/mysql/logs/mysqld.log

# 网络
port = 3306
bind-address = 0.0.0.0

# 字符集
character-set-server = utf8mb4
collation-server = utf8mb4_0900_ai_ci

# InnoDB
innodb_buffer_pool_size = 1G
innodb_redo_log_capacity = 536870912    # 替代 innodb_log_file_size
innodb_flush_log_at_trx_commit = 1

# 复制标识
server-id = 101

# GTID 核心
gtid_mode = ON
enforce_gtid_consistency = ON

# Binlog 配置
log-bin = /data/mysql/mysql-bin
binlog_format = ROW
binlog_row_image = FULL
sync_binlog = 1

# Binlog 保留策略
binlog_expire_logs_seconds = 604800
max_binlog_size = 256M

# 安全
secure-file-priv = /data/mysql/tmp

[client]
socket = /data/mysql/mysql.sock
default-character-set = utf8mb4
```

###### replica端

```bash
[mysqld]
# ========== 基本路径 ==========
basedir = /usr/local/mysql
datadir = /data/mysql/data
tmpdir  = /data/mysql/tmp
socket  = /data/mysql/mysql.sock
pid-file = /data/mysql/mysqld.pid

# ========== 日志 ==========
log-error = /data/mysql/logs/mysqld.log

# ========== 网络 ==========
port = 3306
bind-address = 0.0.0.0

# ========== 字符集 ==========
character-set-server = utf8mb4
collation-server = utf8mb4_0900_ai_ci

# ========== InnoDB ==========
innodb_buffer_pool_size = 1G
innodb_redo_log_capacity = 536870912
innodb_flush_log_at_trx_commit = 1

# ========== 复制标识（必须和主库不同）==========
server-id = 102

# ========== GTID 核心（和主库相同）==========
gtid_mode = ON
enforce_gtid_consistency = ON

# ========== Binlog 配置（和主库相同）==========
log-bin = /data/mysql/mysql-bin
binlog_format = ROW
binlog_row_image = FULL
sync_binlog = 1

# ========== Binlog 保留策略 ==========
binlog_expire_logs_seconds = 604800
max_binlog_size = 256M

# ========== 从库专属（与主库不同的部分）==========
read_only = ON                 # 普通用户只读
super_read_only = ON           # 超级用户也只读（8.0 推荐）
relay_log = /data/mysql/relay-bin
relay_log_recovery = ON

# ========== 安全 ==========
secure-file-priv = /data/mysql/tmp

[client]
socket = /data/mysql/mysql.sock
default-character-set = utf8mb4
```





# 脚本



## Oracle



## 达梦

