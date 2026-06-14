# 备份操作手册

## Mysql

### mysqldump 备份

```shell
# ==================================
# 1. 全备
# ==================================
mysqldump -u root -p \
  --all-databases \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --set-gtid-purged=OFF \
  --flush-logs \
  --source-data=2 \
  | gzip > /backup/full_$(date +%Y%m%d_%H%M%S).sql.gz
  
# ==================================
# 2. 单库备份
# ==================================
mysqldump -u root -p \
	--single-transaction  \
	--routines --triggers --events \
  	myapp \
  	> /backup/myapp_$(date +%Y%m%d).sql
  	
# ==================================
# 3. 多库备份
# ==================================
mysqldump -u root -p \
  --single-transaction \
  --databases myapp analytics user_center \
  > /backup/multi_db_$(date +%Y%m%d).sql
  
# ==================================
# 4. 表备份 （ myapp是数据库，orders是其中的表文件）
# ==================================
  # 单表备份
  mysqldump -u root -p \
  --single-transaction \
  myapp orders > /backup/orders_$(date +%Y%m%d).sql
  
  # 只备份表结构（不含数据）
  mysqldump -u root -p \
  --no-data \
  myapp > /backup/myapp_schema.sql
  
  # 只备份数据，不含表结构
  mysqldump -u root -p \
  --no-create-info \
  myapp > /backup/myapp_data.sql
  
  # 备份时排除某些表
  mysqldump -u root -p \
  --single-transaction \
  myapp \
  --ignore-table=myapp.access_log \
  --ignore-table=myapp.tmp_data \
  > /backup/myapp_$(date +%Y%m%d).sql
```

注意：备份不验证等于没备份，切记，并周期性的验证+恢复测试

```bash
# 检查备份文件是否完整（文件末尾应有 "Dump completed" 字样）
tail -5 /backup/full_backup.sql
```



### xrtabackup 备份

> 数据库 mysql 8.4
>
> Xtrabackup 8.4

**1.安装 Xtrabackup**

```shell
# 1. 安装 Percona 官方 YUM 仓库：
sudo yum install -y https://repo.percona.com/yum/percona-release-latest.noarch.rpm
# 2. 启用 XtraBackup 8.4 的 LTS（长期支持）仓库：
sudo percona-release enable pxb-84-lts
# 3. 安装 XtraBackup：
sudo yum install -y percona-xtrabackup-84 -y
# Rocky Linux 9 / RHEL 9 官方仓库不再提供 compat-openssl10，因为它包含的 OpenSSL 1.0.x 已经 EOL（结束支持）。所以即使 XtraBackup 的 RPM 声明需要这个依赖，YUM 在官方仓库里也找不到它。
# Percona 官方论坛也确认了这一点，并建议用户手动安装 compat-openssl10 
# 手动安装 compat-openssl10 解决 Rocky Linux9 依赖问题
# 1. 下载 compat-openssl10 RPM
wget https://dl.rockylinux.org/pub/rocky/8/Devel/x86_64/os/Packages/c/compat-openssl10-1.0.2o-4.el8_6.x86_64.rpm
sudo rpm -ivh compat-openssl10-1.0.2o-4.el8_6.x86_64.rpm
sudo yum install -y make # 安装make依赖
sudo ldconfig # 更新动态链接库缓存
ldconfig -p | grep libssl.so.10

# 4. 验证安装：
xtrabackup --version

# 如果需要 percona-xtrabackup-84 及其所有依赖（只下载，不安装），用于离线环境安装
# sudo dnf download --resolve percona-xtrabackup-84
```

**2.执行全量备份**

```shell
xtrabackup --backup \
  --user=root --password='YourPassword' \
  --target-dir=/data/backup/full_$(date +%Y%m%d) \
  --parallel=4 \
  --compress \
  --compress-threads=4
```





## Oracle

## 达梦