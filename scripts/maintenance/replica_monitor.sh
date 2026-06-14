#!/bin/bash
# check_replication.sh — 复制状态巡检脚本，建议 crontab 每分钟执行
MYSQL_USER="monitor"
MYSQL_PASS="Mon_P@ss123"
ALERT_DELAY=30

STATUS=$(mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW REPLICA STATUS\G" 2>/dev/null)
[ -z "$STATUS" ] && echo "CRITICAL: 无法获取复制状态" && exit 2

IO_RUNNING=$(echo "$STATUS" | grep "Replica_IO_Running:" | awk '{print $2}')
SQL_RUNNING=$(echo "$STATUS" | grep "Replica_SQL_Running:" | awk '{print $2}')
DELAY=$(echo "$STATUS" | grep "Seconds_Behind_Source:" | awk '{print $2}')
EXIT_CODE=0

if [ "$IO_RUNNING" != "Yes" ]; then
    echo "CRITICAL: IO 线程停止"
    EXIT_CODE=2
fi
if [ "$SQL_RUNNING" != "Yes" ]; then
    echo "CRITICAL: SQL 线程停止"
    EXIT_CODE=2
fi
if [ "$DELAY" = "NULL" ]; then
    echo "WARNING: 延迟值为 NULL"
    [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
elif [ "$DELAY" -gt "$ALERT_DELAY" ]; then
    echo "WARNING: 复制延迟 ${DELAY}s"
    [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
fi
[ $EXIT_CODE -eq 0 ] && echo "OK: 复制正常，延迟 ${DELAY}s"
exit $EXIT_CODE