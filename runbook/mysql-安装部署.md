# mysql-安装部署

## 1.单实例二进制安装

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
>
