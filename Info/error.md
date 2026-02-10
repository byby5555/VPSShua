报错信息：
/usr/local/bin/vpsshua: 行 xx: bc: 未找到命令


报错解析：<br/>
说明脚本调用了 bc，但系统没装。新版本会在启动时先检查依赖并提示安装。<br/>
行 248：[: : 需要整数表达式<br/>
说明某个变量因为 bc 执行失败返回了空值，导致后续条件判断失败。

处理方案：<br/>
安装 bc（推荐）<br/>
Ubuntu / Debian：
<pre lang="markdown">sudo apt update && sudo apt install -y bc</pre>

CentOS / RHEL：
<pre lang="markdown">sudo yum install -y bc</pre>

Alpine Linux：
<pre lang="markdown">sudo apk add bc</pre>

<hr>


---

报错信息：
line 1: 404:: command not found

报错解析：<br/>
说明安装或更新时下载到的是 404 页面，而不是真正的脚本文件。通常由下载地址失效、大小写文件名不一致（`vpsshua.sh` / `VPSShua.sh`）导致。<br/>

处理方案：<br/>
1) 重新执行最新安装脚本（新版本会自动校验下载内容，避免写入 404 文件）<br/>
2) 手动检查快捷方式和目标文件：<br/>
<pre lang="markdown">ls -l /usr/local/bin/vpsshua
head -n 3 /etc/VPSShua/vpsshua.sh</pre>
如果第一行不是 `#!/bin/bash`，请重新安装。
