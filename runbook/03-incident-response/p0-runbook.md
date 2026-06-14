# P0 故障应急手册

## Mysql 应急手册

### 1.主从复制故障排查与修复

#### 1.1 IO 线程故障排查

第一步：检查 网络连通性

第二步：用复制账户验证

第三步：检查 binlog 是否被清理

第四步：检查 SSL/TLS 配置是否匹配

> [!important]
>
> **第一步：检查 网络连通性**
>
> ```shell
> ping 192.168.1.100			# 在从库上测试能否连通主库
> telnet 192.168.1.100 3306	# 测试 3306 端口是否可达
> nc -zv 192.168.1.100 3306	# 或者用 nc
> ```
>
> > 如果 ping 不通或端口不通，先查防火墙和安全组
> >
> > （`iptables -L -n | grep 3306`、`firewall-cmd --list-ports`，云服务器查控制台安全组规则）
>
> **第二步：用复制账户验证**
>
> ```shell
> # 在从库上用复制账户直接连主库试试
> mysql -h 192.168.1.100 -u repl -p'Repl_P@ss123' -e "SELECT 1"
> # ERROR 1045 对应的是密码错误
> # Host 'xxx is not allowed` 则是 host 不对
> ```
>
> **第三步：检查 binlog 是否被清理**
>
> ```shell
> # 错误编码
> error 1236 
> 
> # 排查
> SHOW BINARY LOGS;	# -- 在主库上查看当前可用的 binlog
> SHOW REPLICA STATUS\G	# 在从库上查看它需要的位点（ 看 Source_Log_File 和 Read_Source_Log_Pos ）
> 
> # 如果从库需要的 binlog 确实没了，没法跳过，只能重建从库
> # 后续，设置合理的 binlog 过期时间预防这个问题
> -- MySQL 8.0+
> SET GLOBAL binlog_expire_logs_seconds = 604800;  -- 7 天
> -- MySQL 5.7
> SET GLOBAL expire_logs_days = 7;
> ```
>
> **第四步：检查 SSL/TLS 配置是否匹配**
>
> ```shell
> 如果主库开启了 `require_secure_transport = ON`，但从库连接时没配 SSL，也会被拒绝：
> -- 从库配置 SSL 连接
> STOP REPLICA;
> CHANGE REPLICATION SOURCE TO
>   SOURCE_SSL = 1,
>   SOURCE_SSL_CA = '/etc/mysql/ssl/ca.pem',
>   SOURCE_SSL_CERT = '/etc/mysql/ssl/client-cert.pem',
>   SOURCE_SSL_KEY = '/etc/mysql/ssl/client-key.pem';
> START REPLICA;
> ```



#### 1.2 SQL 线程故障排查

1. Error 1062：主键冲突
2. Error 1032：记录不存在
3. DDL 冲突

> [!important]
>
> 1. **Error 1062：主键冲突**
>
>    > [!tip]
>    >
>    > **原因**：从库上已经存在这条记录了。最常见的原因是有人在从库上做了写操作
>    >
>    > **排查：**-- 查看冲突的记录 （ 在主库执行同样的查询 ）
>    >
>    > - `SELECT * FROM db_name.table_name WHERE id = 12345;`
>    >
>    > **处理：**删除从库上冲突的记录，让复制重新回放
>    >
>    > - `DELETE FROM db_name.table_name WHERE id = 12345;`
>    > - `START REPLICA;`
>
> 2. **Error 1032：记录不存在**
>
>    > [!tip]
>    >
>    > **原因**：主库上执行了 UPDATE 或 DELETE，但从库上这条记录不存在。说明之前某个时刻从库丢了数据。
>    >
>    > **处理方案**：
>    >
>    > - -- 查看主库上这条记录的完整数据
>    >   `SELECT * FROM db_name.table_name WHERE id = 12345;`
>    > - -- 在从库上手动补回来
>    >   `INSERT INTO db_name.table_name VALUES (...);`
>    >   `START REPLICA;`
>
> 3. **DDL 冲突**
>
>    > [!tip]
>    >
>    > **原因**：主库执行了`CREATE TABLE`但从库上表已存在（或反过来，主库 `DROP TABLE` 但从库上表不存在）。
>    >
>    > **处理方案**：根据实际情况调整从库的表结构，使其与主库一致后重新启动复制。



#### 1.3 主从数据一致性校验工具

pt-table-checksum 工具

Percona Toolkit 提供的 `pt-table-checksum` 是业界标准的一致性校验工具。

```shell
# ===============================================
# 安装
# ===============================================
yum install -y percona-toolkit    # CentOS/RHEL
apt-get install -y percona-toolkit # Ubuntu/Debian
pt-table-checksum --version        # 验证

# ===============================================
# 使用
# ===============================================
# 1. 先创建校验账户
CREATE USER 'checksum_user'@'%' IDENTIFIED BY 'Check_P@ss123';
GRANT SELECT, PROCESS, SUPER, REPLICATION SLAVE ON *.* TO 'checksum_user'@'%';
GRANT ALL PRIVILEGES ON percona.* TO 'checksum_user'@'%';

# 2. 在主库上执行校验
pt-table-checksum \
  --host=127.0.0.1 --port=3306 \
  --user=checksum_user --password='Check_P@ss123' \
  --databases=mydb \
  --replicate=percona.checksums \
  --no-check-binlog-format \
  --recursion-method=processlist
# 常用参数：--tables（指定表）、--chunk-size（chunk 行数，默认 1000）

# 3. 结果分析
            TS ERRORS  DIFFS     ROWS  DIFF_ROWS  CHUNKS SKIPPED    TIME TABLE
03-15T10:05:00      0      0    10000          0       10       0   0.512 mydb.users
03-15T10:05:01      0      2     5000        156        5       0   0.308 mydb.orders
03-15T10:05:01      0      0      200          0        1       0   0.105 mydb.config

| 列        | 含义                                   
| ERRORS    | 执行错误数                             
| DIFFS     | 有差异的 chunk 数。**非 0 就是有问题
| ROWS      | 表的总行数                             
| DIFF_ROWS | 预估不一致的行数                      
| CHUNKS    | 分成了多少个 chunk                     
| SKIPPED   | 跳过的 chunk 数      
```

> [!warning]
>
> - `pt-table-checksum` 在主库上执行时会短暂加锁，对线上业务有一定影响。
> - 建议在业务低峰期执行，或使用 `--chunk-time=0.5` 控制每个 chunk 的执行时间。

#### 1.4 数据不一致修复

1 小范围修复：pt-table-sync

2 小范围修复：手动补数据

3 大范围不一致：重建从库

> [!important]
>
> ```shell
> pt-table-sync  可以修复 pt-table-checksum 发现的不一致数据。
> ```
>
> 1. **小范围修复：pt-table-sync、手动补数据**
>
>    pt-table-sync 可以修复 pt-table-checksum  发现的不一致数据。
>
>    ```shell
>    # 先预览要修复的内容（--print 只打印不执行）
>    pt-table-sync \
>      --replicate=percona.checksums \
>      --sync-to-master \
>      h=192.168.1.101,u=checksum_user,p='Check_P@ss123' \
>      --databases=mydb \
>      --tables=orders \
>      --print
>
>    # 确认无误后执行修复（--execute）
>    pt-table-sync \
>      --replicate=percona.checksums \
>      --sync-to-master \
>      h=192.168.1.101,u=checksum_user,p='Check_P@ss123' \
>      --databases=mydb \
>      --tables=orders \
>      --execute
>    ```
>
>    如果只是少量几条记录，手动处理更可控：
>
>    ```shell
>    -- 在主库上导出缺失的数据
>    SELECT * FROM mydb.orders WHERE id IN (101, 102, 103) 
>    INTO OUTFILE '/tmp/fix_data.csv';
>
>    -- 通过复制自动同步到从库（推荐，在主库执行）
>    REPLACE INTO mydb.orders SELECT * FROM mydb.orders WHERE id IN (101, 102, 103);
>    -- REPLACE 会覆盖已存在的记录，不存在的就插入
>    ```
>
> 2. **大范围不一致：重建从库**
>
>    如果不一致的数据量很大（几十张表、几万行），修修补补不现实，直接重建从库更快更可靠。
>
>    **重建步骤（使用 Xtrabackup）**：
>
>    ```bash
>    # 第一步：在主库上做全量备份
>    xtrabackup --backup --user=xtrabackup --password='Xtra_Str0ng!' \
>      --target-dir=/backup/rebuild --parallel=4
>       
>    # 第二步：传输到从库
>    rsync -avP /backup/rebuild/ slave_host:/backup/rebuild/
>       
>    # 第三步：在从库上 prepare
>    xtrabackup --prepare --target-dir=/backup/rebuild
>       
>    # 第四步：停止从库 MySQL，替换数据目录
>    systemctl stop mysqld
>    mv /var/lib/mysql /var/lib/mysql.bak
>    xtrabackup --move-back --target-dir=/backup/rebuild
>    chown -R mysql:mysql /var/lib/mysql
>       
>    # 第五步：启动并查看位点信息
>    systemctl start mysqld
>    cat /backup/rebuild/xtrabackup_binlog_info
>    # 输出类似：mysql-bin.000015  12345  3E11FA47-...:1-100
>       
>    # 第六步： 配置复制（二选一）
>    -- GTID 模式配置复制
>    RESET MASTER;
>    SET GLOBAL gtid_purged = '3E11FA47-71CA-11E1-9E33-C80AA9429562:1-100';
>    CHANGE REPLICATION SOURCE TO SOURCE_HOST='192.168.1.100', SOURCE_USER='repl',
>      SOURCE_PASSWORD='Repl_P@ss123', SOURCE_AUTO_POSITION=1;
>    START REPLICA;
>       
>    -- 传统模式配置复制
>    CHANGE REPLICATION SOURCE TO SOURCE_HOST='192.168.1.100', SOURCE_USER='repl',
>      SOURCE_PASSWORD='Repl_P@ss123', SOURCE_LOG_FILE='mysql-bin.000015',
>      SOURCE_LOG_POS=12345;
>    START REPLICA;
>    SHOW REPLICA STATUS\G
>    ```
>
> 

#### 1.5 复制延迟分析解决

复制没断，但 `Seconds_Behind_Source` 一直在涨——这说明从库的回放速度跟不上主库的写入速度。

Seconds_Behind_Source有局限性：不精确、大事物会失真、IO线程断了显示NULL

更准确的延迟监控方式是 `pt-heartbeat`：

```shell
# 在主库上启动心跳写入（每秒写一次）
pt-heartbeat --update --host=127.0.0.1 --user=heartbeat_user \
  --password='Hb_P@ss123' --database=percona --create-table --daemonize

# 在从库上监控延迟
pt-heartbeat --monitor --host=127.0.0.1 --user=heartbeat_user \
  --password='Hb_P@ss123' --database=percona
# 输出：0.00s [ 0.00s, 0.00s, 0.00s ]
#       当前延迟  1m平均  5m平均  15m平均
```

**复制延迟的主要原因:**MySQL 默认单线程回放 relay log

**解决措施：**开启并行复制可以大幅缓解

```shell
# my.cnf（从库）
[mysqld]
slave_parallel_workers = 8          # 并行线程数，建议 CPU 核数的一半
slave_parallel_type = LOGICAL_CLOCK  # 基于逻辑时钟的并行策略
slave_preserve_commit_order = ON     # 保持提交顺序
# MySQL 8.0.27+ 参数名变更为 replica_parallel_workers 等，功能一样

# 或者在线修改（无需重启）
STOP REPLICA;
SET GLOBAL slave_parallel_workers = 8;
SET GLOBAL slave_parallel_type = 'LOGICAL_CLOCK';
SET GLOBAL slave_preserve_commit_order = ON;
START REPLICA;

# 并行模式选择：
1. DATABASE			# 不同库的事务可以并行，适用于库架构
2. LOGICAL_CLOCK` 	# 同一组 commit 的事务可以并行，推荐，适合大多数场景
```



#### 1.6 大事物拆分

在主库上把大事务拆成小批次：

```shell
-- 不要这样：DELETE FROM logs WHERE create_time < '2024-01-01';
-- 这样做：分批删除
DELIMITER //
CREATE PROCEDURE batch_delete()
BEGIN
  DECLARE rows_affected INT DEFAULT 1;
  WHILE rows_affected > 0 DO
    DELETE FROM logs WHERE create_time < '2024-01-01' LIMIT 1000;
    SET rows_affected = ROW_COUNT();
    DO SLEEP(0.1);  -- 每批之间给从库喘息时间
  END WHILE;
END//
DELIMITER ;
CALL batch_delete();
```



# 















## Oracle 应急手册

## 达梦 应急手册