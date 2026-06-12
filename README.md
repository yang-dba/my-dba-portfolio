# my-dba-portfolio

> DBA 运维技能作品集 | MySQL 数据库管理与运维实战记录( 后续补录 Oracle、PG、达梦 )

## 📌 项目简介

本项目是我在学习和实践 MySQL DBA（数据库管理员）相关技能过程中整理的作品集，涵盖数据库安装部署、主从复制、备份恢复、性能优化、监控告警、自动化运维等方面的脚本、笔记和操作手册。

**核心目标**：
- 系统化沉淀 DBA 运维知识体系
- 持续更新实战经验与踩坑记录
- 展示数据库运维能力

---

## 📁 仓库结构

```
my-dba-portfolio/
├── infrastructure/           # 基础设施即代码
│   ├── ansible/              # Ansible 自动化部署脚本
│   └── terraform/            # Terraform 云资源管理配置
├── monitoring/               # 监控与告警
│   ├── dashboards/           # Grafana 监控大盘 JSON 配置
│   └── alerts/               # Prometheus 告警规则
├── scripts/                  # 运维脚本
│   ├── backup/               # 备份脚本（mysqldump / Xtrabackup）
│   └── maintenance/          # 日常维护脚本（日志清理、慢查询抓取等）
├── runbook/                  # 运维操作手册（SOP）
└── README.md                 # 项目说明
```

---

## 🛠️ 核心技能点

### 1. MySQL 安装部署
- 二进制方式安装 MySQL 8.4
- 单机 / 主从复制环境部署
- 配置文件调优（Buffer Pool、Redo Log、连接数等）

### 2. 主从复制
- 基于 **GTID** 的主从复制搭建（含踩坑记录）
- `CHANGE REPLICATION SOURCE TO` + `SOURCE_AUTO_POSITION = 1`
- 解决 `caching_sha2_password` 认证问题（`GET_SOURCE_PUBLIC_KEY = 1`）
- 主从延迟排查与处理

### 3. 备份恢复
- **逻辑备份**：`mysqldump` 全量/单库/单表备份
- **物理备份**：`Xtrabackup` 全量/增量备份与恢复
- **时间点恢复（PITR）**：全量备份 + binlog 重放
- 备份自动化脚本 + crontab 定时任务

### 4. 性能优化
- 慢查询日志分析与 `pt-query-digest` 使用
- `EXPLAIN` 执行计划解读（`type`、`rows`、`Extra`）
- 复合索引设计与最左前缀原则
- 覆盖索引避免回表

### 5. InnoDB 核心原理
- B+Tree 索引结构
- 聚簇索引 vs 二级索引
- Redo Log / Undo Log / MVCC
- 事务隔离级别与锁机制

### 6. 监控与告警
- Prometheus + Grafana 监控 MySQL
- 监控指标：QPS、连接数、慢查询、主从延迟、磁盘空间
- 告警规则配置

### 7. 自动化运维
- Shell 脚本：自动备份与清理、慢查询抓取、主从状态监控
- Ansible：一键部署 MySQL / 主从复制（计划中）

---

## 📝 笔记与文档

> 详细笔记已整理为 Markdown 格式，涵盖知识点、命令示例、踩坑记录和面试话术。

- GTID 主从复制搭建 SOP
- Xtrabackup 全量/增量备份恢复 SOP
- 慢查询分析流程
- 复合索引设计法则
- InnoDB 核心概念精简版
- 面试高频问题汇总

---

## 🚀 快速使用

### 1. 克隆仓库
```bash
git clone https://github.com/mrhuangitseeker-jpg/my-dba-portfolio.git
cd my-dba-portfolio
```

### 2. 运行备份脚本示例
```bash
cd scripts/backup
chmod +x full_backup.sh
./full_backup.sh
```

### 3. 查看运维手册
```bash
cd runbook
cat gtid_replication_sop.md
```

---

## 📄 许可证

本项目采用 **MIT 许可证**，可自由使用、修改和分享，请保留原作者声明。

---

## 🙋 关于我

- 持有 OCP（Oracle）、GBase 8s、YCA 证书
- 熟悉 MySQL / Oracle / 国产数据库
- 具备 Linux 运维 + Shell 脚本开发能力
- 从渗透测试转行 DBA，兼具安全视角
- 持续学习，长期深耕数据库运维方向

---

## 📬 联系与交流

- GitHub：[mrhuangitseeker-jpg](https://github.com/mrhuangitseeker-jpg)
- 邮箱：[mrhuangitseeker@gmail.com]

欢迎交流 DBA 学习经验与技术问题。
---

**最后更新**：2026年6月
