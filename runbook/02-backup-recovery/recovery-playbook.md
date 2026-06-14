# 恢复演练手册

## Mysql

### mysqldump 恢复

```bash
# ==================================
# 1. 全库恢复
# ==================================
gunzip /backup/full_20240315_020000.sql.gz			# 解压（如果备份时压缩了）
mysql -u root -p < /backup/full_20240315_020000.sql	# 恢复
# 或者在客户端内： SOURCE /backup/full_20240315_020000.sql;

# ==================================
# 2. 单库恢复
# ==================================
# 先创建目标数据库（如果备份时没用 --databases）
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS myapp;"
mysql -u root -p myapp < /backup/myapp_20240315.sql # 恢复

# ==================================
# 2. 单表恢复
# ==================================
# 方案1：从备份文件中提取 orders 表的结构和数据（这种方式不太可靠，尤其是大文件。）
sed -n '/^-- Table structure for table `orders`/,/^-- Table structure for table/p' \
  /backup/full_backup.sql > /tmp/orders_only.sql
# 用 `--tables` 参数单独备份后恢复，如果你还能连上数据库，直接单独备份那张表再恢复到目标环境。
```

### xrtabackup 恢复

Xtrabackup 的恢复分两步：**准备（prepare）** 和 **拷贝回去（copy-back）**。

1. 解压（如果备份时压缩了）
2. 准备（Prepare）
3. 恢复数据 (copy-back)
4. 恢复验证

1.**解压（如果备份时压缩了）**

```bash
xtrabackup --decompress \
	--target-dir=/backup/full_20240315
```

2.**准备（Prepare）**

```bash
xtrabackup --prepare \
	--target-dir=/backup/full_20240315
```

3.**恢复数据 (copy-back)**

```bash
# 1. 停止 MySQL
sudo systemctl stop mysqld
# 2. 清空原数据目录（危险操作，确认无误后执行）
sudo rm -rf /var/lib/mysql/*

# 3. 拷贝备份数据到数据目录
xtrabackup --copy-back --target-dir=/backup/full_20240315

# 4. 修复属主
sudo chown -R mysql:mysql /var/lib/mysql
# 5. 启动 MySQL
sudo systemctl start mysqld
```

4.**恢复验证**

```sql
-- 确认数据完整
SHOW DATABASES;
SELECT COUNT(*) FROM myapp.orders;

-- 检查 InnoDB 状态
SHOW ENGINE INNODB STATUS\G
```





## Oracle

## 达梦