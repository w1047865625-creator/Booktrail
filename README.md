# Booktrail

**Booktrail v4.9.2** 是一款运行于 **Kindle 原生系统**的本地阅读统计工具，用于记录、整理和查看阅读轨迹。

## 功能

- 📚 记录阅读会话、阅读时间与阅读进度
- 📖 按书籍查看累计阅读时长、阅读进度和阅读详情
- 📅 查看每日、每周、每月及年度阅读数据
- 📊 查看阅读统计与阅读轨迹
- 📚 对同一本书的不同版本标题进行归一化与聚合，避免同一本书被重复统计
- 🖼️ 支持书籍封面与书籍详情展示
- ⚙️ 提供本地设置与采集控制
- 💾 数据保存在 Kindle 本地 SQLite 数据库，不依赖云服务
- 🔒 无登录、Token、HTTP、云同步或网络服务依赖
- ⚡ 针对 Kindle ARMHF 硬件和原生阅读系统设计

## 适用环境

- 已越狱的 Kindle
- Kindle 原生阅读系统
- 已安装并可以正常使用 **KUAL（Kindle Unified Application Launcher）**
- 已验证的 Kindle 固件：**5.17.1.0.4**

Booktrail 不替换 Kindle 原有阅读器，也不适用于未越狱设备。

## 安装

### 1. 准备安装包

使用对应版本的发布包：

```text
Booktrail-4.9.2.zip
```

不要混用不同版本的部署文件。

### 2. 安装 Booktrail

将安装包中的：

```text
extensions/booktrail/
```

完整复制到 Kindle：

```text
/mnt/us/extensions/booktrail/
```

安装完成后应为：

```text
/mnt/us/extensions/booktrail/
├── bin/
│   ├── kindle-reading-gtk
│   ├── booktrail-session-append
│   ├── booktrail-start.sh
│   ├── booktrail-stop.sh
│   ├── booktrail-restart.sh
│   ├── krg_collector.sh
│   ├── metrics.sh
│   ├── metrics_setup.sh
│   └── libsqlite3.so.0
├── etc/
│   └── syslog-ng.conf
├── config.xml
└── menu.json
```

**不要多嵌套一层目录。**

错误：

```text
/mnt/us/extensions/booktrail/Booktrail-4.9.2/extensions/booktrail/
```

正确：

```text
/mnt/us/extensions/booktrail/bin/
```

### 3. 安装 Kindle 主页入口

将：

```text
documents/Booktrail.sh
```

复制到：

```text
/mnt/us/documents/Booktrail.sh
```

不要修改文件名，也不要把整个 `documents` 文件夹复制进去。

### 4. 从 KUAL 启动

安全断开 Kindle 与电脑的连接后：

1. 打开 **KUAL**
2. 找到 **Booktrail 阅读统计**
3. 点击后启动 Booktrail

4.9.2 的 KUAL 菜单会根据主程序是否存在显示相应状态。

## 数据库

Booktrail 使用本地 SQLite 数据库：

```text
/mnt/us/extensions/booktrail/booktrail.db
```

数据库记录书籍信息、阅读会话及统计数据。

升级版本时，请保留原有数据库和备份文件。不要直接删除数据库，以免丢失历史阅读数据。

## 阅读数据采集

Booktrail 通过 Kindle 系统阅读日志采集阅读事件，并由后台组件整理为阅读会话。

主要组件：

- `krg_collector.sh`：阅读事件采集
- `booktrail-session-append`：将阅读会话写入 SQLite
- `metrics_setup.sh`：采集配置管理
- `metrics.sh`：统计及 GUI 启动入口
- `booktrail-start.sh` / `booktrail-stop.sh`：启动或停止后台采集
- `booktrail-restart.sh`：重启采集流程

采集配置涉及 Kindle 的 `syslog-ng`。**不要直接覆盖 Kindle 原有的 syslog-ng 配置文件**，应使用 Booktrail 提供的管理流程，以保留配置合并、校验和恢复逻辑。

## 安装验证

安装完成后建议依次确认：

1. Kindle 主页能够看到 **Booktrail** 入口；
2. 点击主页入口能够启动 Booktrail；
3. KUAL 中能够看到 **Booktrail 阅读统计**；
4. Booktrail GUI 能够正常打开；
5. `/mnt/us/extensions/booktrail/booktrail.db` 已创建；
6. 阅读一段时间后，重新打开 Booktrail，确认阅读统计发生变化；
7. 如果 GUI 无法启动，先检查安装目录、可执行文件和数据库状态。

## 卸载

卸载前应先停止 Booktrail 后台采集，并保留数据库备份。

同时删除：

```text
/mnt/us/documents/Booktrail.sh
```

以及：

```text
/mnt/us/extensions/booktrail/
```

**不要直接删除或清空 Kindle 系统中的 `syslog-ng.conf`。** 采集配置可能已经合并到系统日志配置中，卸载时应使用 Booktrail 提供的停用流程恢复配置。

## 从源码构建

Booktrail GUI 使用：

- C++17
- Meson
- GTK+ 2
- GDK Pixbuf 2
- SQLite3
- Kindle ARMHF / Linux

宿主环境可以运行：

```sh
meson setup build-local --buildtype=debug
meson compile -C build-local
meson test -C build-local --print-errorlogs
```

Kindle ARMHF Release 构建：

```sh
./scripts/build-kindlhf-release.sh
```

交叉编译需要设置：

```sh
export BOOKTRAIL_ARMHF_TOOLCHAIN=/path/to/arm-kindlehf-linux-gnueabihf
export BOOKTRAIL_ARMHF_SYSROOT=/path/to/kindle-sysroot
```

完整编译规则请参阅 [Booktrail-GUI/BUILD.md](Booktrail-GUI/BUILD.md)。

## 源码与发布包

当前版本：

**v4.9.2**

4.9.2 发布目录包含：

- `Booktrail-4.9.2.zip`：Kindle 部署包
- `Booktrail-GUI-4.9.2-source.zip`：纯净 GUI 源码包
- `SHA256SUMS`：部署包完整性校验
- `VERSION`：版本信息

## 项目地址

https://github.com/w1047865625-creator/Booktrail
