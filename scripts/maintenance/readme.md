# 目录说明

## **health-check.sh**

健康检查脚本

## **slow-query-report.sh**

慢查询报告脚本

## **replica_monitor.sh**

名称：主从复制故障自动化监控脚本

使用：

```shell
# crontab 配置
* * * * * /opt/scripts/check_replication.sh || /opt/scripts/send_alert.sh "MySQL 复制异常"
```



