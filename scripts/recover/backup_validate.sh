#!/bin/bash
# verify-backup.sh — 自动恢复验证
BACKUP_FILE=$1
TEST_PORT=3307

echo "$(date) - 开始恢复验证..."

# 恢复到测试实例
mysql -u root -p'xxx' -P $TEST_PORT < "$BACKUP_FILE" 2>/tmp/restore_err.log

if [ $? -ne 0 ]; then
    echo "FAILED: 恢复出错"
    cat /tmp/restore_err.log
    exit 1
fi

# 检查关键表
TABLES=("myapp.orders" "myapp.users" "myapp.products")
for table in "${TABLES[@]}"; do
    count=$(mysql -u root -p'xxx' -P $TEST_PORT -N -B -e "SELECT COUNT(*) FROM $table" 2>/dev/null)
    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
        echo "WARNING: $table 行数为 0 或查询失败"
    else
        echo "OK: $table = $count rows"
    fi
done

echo "$(date) - 恢复验证完成"