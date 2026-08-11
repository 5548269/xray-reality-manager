#!/bin/bash

# 等待1秒, 避免curl下载脚本的打印与脚本本身的显示冲突
sleep 1

echo -e "                     _ ___                   \n ___ ___ __ __ ___ _| |  _|___ __ __   _ ___ \n|-_ |_  |  |  |-_ | _ |   |- _|  |  |_| |_  |\n|___|___|  _  |___|___|_|_|___|  _  |___|___|\n        |_____|               |_____|        "
red='\e[91m'
green='\e[92m'
yellow='\e[93m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

# 脚本版本
VERSION="2.0.13"

# 配置文件路径
CONFIG_FILE="/usr/local/etc/xray/config.json"
CONFIG_DIR="/usr/local/etc/xray"
PORT_INFO_FILE="$HOME/.xray_port_info.json"
LOG_FILE="$HOME/.xray_management.log"
# HAProxy配置文件路径
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}错误: 必须以root权限运行此脚本${none}"
        exit 1
    fi
}

# 记录日志
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 添加日志记录函数的包装
log_info() {
    log "INFO" "$1"
}

log_error() {
    log "ERROR" "$1"
}

log_warn() {
    log "WARN" "$1"
}

# TCP优化函数
optimize_tcp() {
    echo -e "${yellow}正在优化TCP连接参数...${none}"
    log_info "开始优化TCP连接参数"
    
    # 备份原始配置
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S)
    
    # 设置TCP Fast Open
    echo 3 > /proc/sys/net/ipv4/tcp_fastopen
    
    # 调整TCP缓冲区和连接参数
    cat >> /etc/sysctl.conf << EOF
# TCP优化参数
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_mtu_probing = 1
EOF
    
    # 应用配置
    sysctl -p > /dev/null 2>&1
    
    log_info "TCP优化完成"
}

# 获取公共IP的函数
get_public_ip() {
    local ip_type=$1  # 4 for IPv4, 6 for IPv6
    local interface=$2
    local timeout=3

    # IP检测源列表
    local ip_apis=(
        "https://www.cloudflare.com/cdn-cgi/trace"    # Cloudflare
        "https://api.ipify.org"                       # ipify
        "https://ip.sb"                               # ip.sb
        "https://api.ip.sb/ip"                        # ip.sb alternative
        "https://ifconfig.me"                         # ifconfig.me
    )

    for api in "${ip_apis[@]}"; do
        local ip
        if [[ $api == "https://www.cloudflare.com/cdn-cgi/trace" ]]; then
            ip=$(curl -"${ip_type}"s --interface "$interface" -m "$timeout" "$api" 2>/dev/null | grep -oP "ip=\K.*$")
        else
            ip=$(curl -"${ip_type}"s --interface "$interface" -m "$timeout" "$api" 2>/dev/null)
        fi

        if [[ -n "$ip" && $ip =~ ^[0-9a-fA-F:.]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    return 1
}

# 获取本机IP
get_local_ips() {
    local success=false
    IPv4=""
    IPv6=""
    
    # 获取网络接口列表
    InFaces=($(ls /sys/class/net/ | grep -E '^(eth|ens|eno|esp|enp|venet|vif)'))
    
    for i in "${InFaces[@]}"; do
        echo -e "${yellow}正在检测接口 $i ...${none}"
        
        # 尝试获取IPv4
        if [[ -z "$IPv4" ]]; then
            Public_IPv4=$(get_public_ip 4 "$i")
            if [[ -n "$Public_IPv4" ]]; then
                IPv4="$Public_IPv4"
                echo -e "${green}在接口 $i 上成功获取到IPv4: $IPv4${none}"
                log_info "获取到IPv4: $IPv4 (接口: $i)"
                success=true
            fi
        fi
        
        # 尝试获取IPv6
        if [[ -z "$IPv6" ]]; then
            Public_IPv6=$(get_public_ip 6 "$i")
            if [[ -n "$Public_IPv6" ]]; then
                IPv6="$Public_IPv6"
                echo -e "${green}在接口 $i 上成功获取到IPv6: $IPv6${none}"
                log_info "获取到IPv6: $IPv6 (接口: $i)"
                success=true
            fi
        fi
        
        # 如果两种IP都已获取到，可以提前退出循环
        if [[ -n "$IPv4" && -n "$IPv6" ]]; then
            break
        fi
    done

    # 如果通过网络接口获取失败，尝试直接获取
    if [[ -z "$IPv4" ]]; then
        echo -e "${yellow}尝试直接获取IPv4...${none}"
        IPv4=$(get_public_ip 4)
        if [[ -n "$IPv4" ]]; then
            echo -e "${green}成功获取到IPv4: $IPv4${none}"
            log_info "直接获取到IPv4: $IPv4"
            success=true
        fi
    fi
    
    if [[ -z "$IPv6" ]]; then
        echo -e "${yellow}尝试直接获取IPv6...${none}"
        IPv6=$(get_public_ip 6)
        if [[ -n "$IPv6" ]]; then
            echo -e "${green}成功获取到IPv6: $IPv6${none}"
            log_info "直接获取到IPv6: $IPv6"
            success=true
        fi
    fi

    # 检查是否获取到任何IP
    if ! $success; then
        echo -e "${red}警告: 未能获取到任何公共IP地址${none}"
        log_error "未能获取到任何公共IP地址"
        echo -e "${yellow}请检查:${none}"
        echo "1. 网络连接是否正常"
        echo "2. 是否有防火墙限制"
        echo "3. 服务器是否支持公网IP"
        echo "4. DNS设置是否正确"
        return 1
    fi

    return 0
}

error() {
    echo -e "\n$red 输入错误! $none\n"
    log_error "用户输入错误"
}

warn() {
    echo -e "\n$yellow $1 $none\n"
    log_warn "$1"
}

success() {
    echo -e "\n$green $1 $none\n"
    log_info "$1"
}

pause() {
    read -rsp "$(echo -e "按 $green Enter 回车键 $none 继续....或按 $red Ctrl + C $none 取消.")" -d $'\n'
    echo
}

# 创建必要的目录和文件
init_directories() {
    # 创建配置目录
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
    fi
    
    # 初始化配置文件
    if [[ ! -f "$PORT_INFO_FILE" ]]; then
        echo '{"ports":[]}' > "$PORT_INFO_FILE"
        chmod 600 "$PORT_INFO_FILE"
    fi
    
    # 确保日志文件存在
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
}

# 更新 Xray GeoIP 和 GeoSite 数据
update_geodata() {
    echo
    echo -e "$yellow 更新 Xray GeoIP 和 GeoSite 数据 $none"
    echo "----------------------------------------------------------------"
    log_info "开始更新 GeoIP 和 GeoSite 数据"
    
    # 使用官方脚本更新
    if bash -c "$(curl -fL https://raw.githubusercontent.com/5548269/xray-reality-manager/main/install-release.sh
)" @ install-geodata; then
        echo
        echo -e "$green 数据库更新成功! $none"
        log_info "数据库更新成功 (官方脚本)"
        
        # 重启 Xray 服务
        echo
        echo -e "$yellow 重启 Xray 服务... $none"
        if systemctl restart xray; then
            echo -e "$green Xray 服务重启成功! $none"
            log_info "Xray 服务重启成功"
        else
            echo -e "$red Xray 服务重启失败，请手动检查! $none"
            log_error "Xray 服务重启失败"
        fi
    else
        echo -e "$red 数据库更新失败! $none"
        log_error "数据库更新失败 (官方脚本)"
        
        echo
        echo -e "$yellow 尝试手动更新... $none"
        
        # 手动下载更新
        if wget -O /usr/local/share/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && \
           wget -O /usr/local/share/xray/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat; then
            echo -e "$green 数据库手动更新成功! $none"
            log_info "数据库手动更新成功"
            
            # 重启 Xray 服务
            echo
            echo -e "$yellow 重启 Xray 服务... $none"
            if systemctl restart xray; then
                echo -e "$green Xray 服务重启成功! $none"
                log_info "Xray 服务重启成功"
            else
                echo -e "$red Xray 服务重启失败，请手动检查! $none"
                log_error "Xray 服务重启失败"
            fi
        else
            echo -e "$red 数据库手动更新失败! $none"
            log_error "数据库手动更新失败"
        fi
    fi
    
    # 显示当前 Xray 版本信息
    echo
    echo -e "$yellow 当前 Xray 版本信息: $none"
    xray --version
    log_info "当前 Xray 版本: $(xray --version | head -n1)"
    echo
    pause
}

# 检查是否安装了必要的依赖
check_dependencies() {
    local dependencies=("curl" "jq" "lsof" "wget" "systemctl" "haproxy")
    local missing=()

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${yellow}正在安装缺少的依赖: ${missing[*]}${none}"
        apt update -y
        apt install -y "${missing[@]}"
        
        # 再次检查是否成功安装
        for dep in "${missing[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                echo -e "${red}安装 $dep 失败，请手动安装${none}"
                return 1
            fi
        done
    fi
    
    return 0
}

# 保存端口配置信息到JSON文件
save_port_info() {
    local port=$1
    local uuid=$2
    local private_key=$3
    local public_key=$4
    local shortid=$5
    local domain=$6
    
    # 检查端口是否已存在，如果存在则更新配置
    if jq -e ".ports[] | select(.port == $port)" "$PORT_INFO_FILE" > /dev/null; then
        # 更新已存在的端口配置
        jq "(.ports[] | select(.port == $port)) |= {
            \"port\": $port,
            \"uuid\": \"$uuid\",
            \"private_key\": \"$private_key\",
            \"public_key\": \"$public_key\",
            \"shortid\": \"$shortid\",
            \"domain\": \"$domain\",
            \"socks5\": (.socks5 // null),
            \"haproxy\": (.haproxy // null)
        }" "$PORT_INFO_FILE" > "${PORT_INFO_FILE}.tmp"
    else
        # 添加新的端口配置
        jq ".ports += [{
            \"port\": $port,
            \"uuid\": \"$uuid\",
            \"private_key\": \"$private_key\",
            \"public_key\": \"$public_key\",
            \"shortid\": \"$shortid\",
            \"domain\": \"$domain\",
            \"socks5\": null,
            \"haproxy\": null
        }]" "$PORT_INFO_FILE" > "${PORT_INFO_FILE}.tmp"
    fi
    
    mv "${PORT_INFO_FILE}.tmp" "$PORT_INFO_FILE"
    chmod 600 "$PORT_INFO_FILE"
    log_info "保存端口 $port 配置"
}



# 获取特定端口的配置信息
get_port_info() {
    local port=$1
    jq -c ".ports[] | select(.port == $port)" "$PORT_INFO_FILE"
}

# 检查端口是否已配置
check_port_exists() {
    local port=$1
    if jq -e ".ports[] | select(.port == $port)" "$PORT_INFO_FILE" > /dev/null; then
        return 0  # 端口已存在
    fi
    return 1  # 端口不存在
}

# 删除特定端口的配置信息
delete_port_info() {
    local port=$1
    jq "del(.ports[] | select(.port == $port))" "$PORT_INFO_FILE" > "${PORT_INFO_FILE}.tmp"
    mv "${PORT_INFO_FILE}.tmp" "$PORT_INFO_FILE"
    chmod 600 "$PORT_INFO_FILE"
    log_info "删除端口 $port 配置"
}


# 更新Xray配置文件，使用HAProxy作为SOCKS5代理接口
update_config_file() {
    # 备份当前配置
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 创建基本配置，包含DNS设置
    cat > "$CONFIG_FILE" << EOL
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "dns": {
    "servers": [
      "tcp://8.8.8.8",
      "tcp://1.1.1.1",
      "tcp://1.0.0.1",
      "tcp://8.8.4.4",
      "localhost"
    ],
    "queryStrategy": "UseIPv4",
    "disableCache": true,
    "disableFallback": false,
    "tag": "dns-out"
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "dns",
      "tag": "dns-out"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOL
    
    # 读取所有端口配置
    local ports_config=$(jq -c '.ports[]' "$PORT_INFO_FILE")
    
    # 临时文件
    local temp_config=$(mktemp)
    cp "$CONFIG_FILE" "$temp_config"
    
    # 处理每个端口配置
    echo "$ports_config" | while read -r port_info; do
        local port=$(echo "$port_info" | jq -r '.port')
        local uuid=$(echo "$port_info" | jq -r '.uuid')
        local private_key=$(echo "$port_info" | jq -r '.private_key')
        local shortid=$(echo "$port_info" | jq -r '.shortid')
        local domain=$(echo "$port_info" | jq -r '.domain')
        
        # 创建VLESS+Reality的入站配置
        cat > "$temp_config.inbound" << EOL
{
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "${uuid}",
        "flow": "xtls-rprx-vision"
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "dest": "${domain}:443",
      "xver": 0,
      "serverNames": ["${domain}"],
      "privateKey": "${private_key}",
      "shortIds": ["${shortid}"]
    }
  },
  "sniffing": {
    "enabled": false,
    "destOverride": ["http", "tls", "quic"]
  },
  "tag": "inbound-${port}"
}
EOL

        # 添加入站配置到主配置
        jq ".inbounds += [$(cat "$temp_config.inbound")]" "$temp_config" > "$temp_config.new"
        mv "$temp_config.new" "$temp_config"
        
        # 处理SOCKS5代理配置
        local socks5_config=$(echo "$port_info" | jq -r '.socks5')
        
        if [[ "$socks5_config" != "null" && "$(echo "$socks5_config" | jq -r '.enabled')" == "true" ]]; then
            # 获取SOCKS5配置信息
            local haproxy_config=$(echo "$port_info" | jq -r '.haproxy')
            local socks5_address
            local socks5_port
            
            if [[ "$haproxy_config" != "null" && "$(echo "$haproxy_config" | jq -r '.enabled')" == "true" ]]; then
                # 如果启用了HAProxy，使用HAProxy的地址和端口
                socks5_address="127.0.0.1"  # 使用本地地址作为HAProxy监听地址
                socks5_port=$(echo "$haproxy_config" | jq -r '.port')
            else
                # 如果出现异常情况（HAProxy未配置），使用原始SOCKS5端口
                socks5_address=$(echo "$socks5_config" | jq -r '.address')
                socks5_port=$(echo "$socks5_config" | jq -r '.port')
                log_warn "端口 $port 的HAProxy未配置，使用原始SOCKS5设置"
            fi
            
            local udp_over_tcp=$(echo "$socks5_config" | jq -r '.udp_over_tcp')
            local socks5_tag="socks5-out-$port"
            
            # 创建SOCKS5出站配置
            cat > "$temp_config.socks5" << EOL
{
  "protocol": "socks",
  "settings": {
    "servers": [
      {
        "address": "${socks5_address}",
        "port": ${socks5_port}
EOL

            # 添加认证信息
            local auth_needed=$(echo "$socks5_config" | jq -r '.auth_needed')
            if [[ "$auth_needed" == "true" ]]; then
                local socks5_user=$(echo "$socks5_config" | jq -r '.username')
                local socks5_pass=$(echo "$socks5_config" | jq -r '.password')
                
                # 只有当用户名和密码都不为空时才添加认证信息
                if [[ -n "$socks5_user" && -n "$socks5_pass" ]]; then
                    cat >> "$temp_config.socks5" << EOL
        ,
        "users": [
          {
            "user": "${socks5_user}",
            "pass": "${socks5_pass}"
          }
        ]
EOL
                fi
            fi

            # 结束servers配置
            cat >> "$temp_config.socks5" << EOL
      }
    ]
  }
EOL

            if [[ "$udp_over_tcp" == "true" ]]; then
                cat >> "$temp_config.socks5" << EOL
  ,"streamSettings": {"sockopt": {"udpFragmentSize": 1400,"tcpFastOpen": true,"tcpKeepAliveInterval": 15,"mark": 255}},"transportLayer": true
EOL
            else
                cat >> "$temp_config.socks5" << EOL
  ,"streamSettings": {"sockopt": {"tcpFastOpen": true,"tcpKeepAliveInterval": 15,"tcpMptcp": true,"tcpNoDelay": true,"mark": 255}}
EOL
            fi
            
            cat >> "$temp_config.socks5" << EOL
  ,"tag": "${socks5_tag}"
}
EOL

            # 添加SOCKS5出站到主配置
            jq ".outbounds += [$(cat "$temp_config.socks5")]" "$temp_config" > "$temp_config.new"
            mv "$temp_config.new" "$temp_config"
            
            # 创建路由规则，将此入站流量直接导向SOCKS5出站
            # 根据UDP over TCP设置选择合适的网络类型
            local network_type=$(if [[ "$udp_over_tcp" == "true" ]]; then echo "tcp,udp"; else echo "tcp"; fi)
            
            cat > "$temp_config.rule" << EOL
{
  "type": "field",
  "inboundTag": ["inbound-${port}"],
  "outboundTag": "${socks5_tag}"
}
EOL
            
            # 添加路由规则到主配置
            jq ".routing.rules += [$(cat "$temp_config.rule")]" "$temp_config" > "$temp_config.new"
            mv "$temp_config.new" "$temp_config"
        fi
    done
    
    # 应用新配置
    cp "$temp_config" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    
    # 清理临时文件
    rm -f "$temp_config" "$temp_config.inbound" "$temp_config.socks5" "$temp_config.rule" "$temp_config.new" 2>/dev/null

    log_info "配置文件已更新"
}

# 检查Xray服务状态
check_xray_service() {
    if ! systemctl is-active --quiet xray; then
        echo -e "${red}Xray 服务未运行，尝试启动...${none}"
        systemctl start xray
        sleep 2
        
        if ! systemctl is-active --quiet xray; then
            echo -e "${red}Xray 服务启动失败${none}"
            log_error "Xray服务启动失败"
            return 1
        fi
    fi
    
    echo -e "${green}Xray 服务运行中${none}"
    log_info "Xray服务运行中"
    return 0
}

# 显示所有端口配置
list_port_configurations() {
    echo
    echo -e "$yellow 当前所有端口配置 $none"
    echo "----------------------------------------------------------------"
    
    if [[ ! -s "$PORT_INFO_FILE" ]] || [[ $(jq '.ports | length' "$PORT_INFO_FILE") -eq 0 ]]; then
        echo -e "$red 目前没有配置任何端口，请先添加端口配置 $none"
        return
    fi
    
    echo -e "${cyan}序号   端口    UUID    域名    代理状态    HAProxy状态${none}"
    echo "----------------------------------------------------------------"
    
    local index=1
    jq -c '.ports[]' "$PORT_INFO_FILE" | while read -r port_info; do
        local port=$(echo "$port_info" | jq -r '.port')
        local uuid=$(echo "$port_info" | jq -r '.uuid')
        # 截取UUID的开头和结尾部分，中间用省略号
        local uuid_short="${uuid:0:8}...${uuid:24}"
        local domain=$(echo "$port_info" | jq -r '.domain')
        local socks5_enabled=$(echo "$port_info" | jq -r '.socks5.enabled // false')
        
        if [[ "$socks5_enabled" == "true" ]]; then
            local socks5_address=$(echo "$port_info" | jq -r '.socks5.address')
            local socks5_port=$(echo "$port_info" | jq -r '.socks5.port')
            socks5_status="${green}启用 (${socks5_address}:${socks5_port})${none}"
        else
            socks5_status="${red}禁用${none}"
        fi
        
        # 显示HAProxy状态
        local haproxy_enabled=$(echo "$port_info" | jq -r '.haproxy.enabled // false')
        if [[ "$haproxy_enabled" == "true" ]]; then
            local haproxy_port=$(echo "$port_info" | jq -r '.haproxy.port')
            local haproxy_threads=$(echo "$port_info" | jq -r '.haproxy.threads')
            local haproxy_maxconn=$(echo "$port_info" | jq -r '.haproxy.maxconn')
            haproxy_status="${green}启用 (端口:${haproxy_port}, 线程:${haproxy_threads}, 最大连接:${haproxy_maxconn})${none}"
        else
            haproxy_status="${red}禁用,请配置socks${none}"
        fi
        
        echo -e "${green}$index${none}    ${cyan}$port${none}    ${yellow}$uuid_short${none}    ${magenta}$domain${none}    ${socks5_status}    ${haproxy_status}"
        index=$((index+1))
    done
    
    echo "----------------------------------------------------------------"
    
    # 如果HAProxy服务运行中，显示HAProxy状态
    if systemctl is-active --quiet haproxy; then
        echo -e "${green}HAProxy服务状态: 运行中${none}"
    else
        echo -e "${red}HAProxy服务状态: 未运行${none}"
    fi
    
}

# 备份当前所有配置
backup_configuration() {
    echo
    echo -e "$yellow 备份当前配置 $none"
    echo "----------------------------------------------------------------"
    
    local backup_dir="$HOME/xray_backup_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份端口配置信息
    if [[ -f "$PORT_INFO_FILE" ]]; then
        cp "$PORT_INFO_FILE" "$backup_dir/"
    fi
    
    # 备份Xray配置
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$backup_dir/"
    fi

    # 备份HAProxy配置
    if [[ -f "$HAPROXY_CONFIG" ]]; then
        cp "$HAPROXY_CONFIG" "$backup_dir/"
    fi
    
    # 备份其他配置文件
    cp -r /usr/local/etc/xray/* "$backup_dir/" 2>/dev/null
    
    echo -e "${green}配置已备份至: $backup_dir${none}"
    log_info "备份配置到 $backup_dir"
    
    # 创建一个压缩包
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${green}备份文件: ${backup_dir}.tar.gz${none}"
    echo -e "使用以下命令恢复: tar -xzf ${backup_dir}.tar.gz -C /"
    
    pause
}


# 恢复配置
restore_configuration() {
    echo
    echo -e "$yellow 恢复配置 $none"
    echo "----------------------------------------------------------------"
    
    echo -e "请输入备份文件路径:"
    read -p "$(echo -e "(例如: ${HOME}/xray_backup_20220101000000.tar.gz): ")" backup_file
    
    if [[ ! -f "$backup_file" ]]; then
        echo -e "${red}备份文件不存在${none}"
        return
    fi
    
    echo -e "${yellow}警告: 恢复将覆盖当前配置，是否继续?${none}"
    read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo -e "${yellow}操作已取消${none}"
        return
    fi
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    echo -e "${yellow}解压备份文件到: $temp_dir${none}"
    
    # 解压备份文件
    if ! tar -xzf "$backup_file" -C "$temp_dir"; then
        echo -e "${red}解压备份文件失败${none}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 显示解压后的文件结构
    echo -e "${yellow}解压后的文件结构:${none}"
    find "$temp_dir" -type f | sort
    
    # 查找配置文件 - 不限定在哪个目录下
    local port_info_file=$(find "$temp_dir" -name ".xray_port_info.json" | head -n 1)
    local xray_config_file=$(find "$temp_dir" -name "config.json" | head -n 1)
    local haproxy_config_file=$(find "$temp_dir" -name "haproxy.cfg" | head -n 1)
    
    echo -e "${yellow}找到的配置文件:${none}"
    echo "端口信息文件: ${port_info_file:-未找到}"
    echo "Xray配置文件: ${xray_config_file:-未找到}"
    echo "HAProxy配置文件: ${haproxy_config_file:-未找到}"
    
    # 恢复端口配置信息
    if [[ -n "$port_info_file" && -f "$port_info_file" ]]; then
        echo -e "${yellow}恢复端口配置信息...${none}"
        cp "$port_info_file" "$PORT_INFO_FILE"
        chmod 600 "$PORT_INFO_FILE"
        echo -e "${green}端口配置信息恢复成功${none}"
    else
        echo -e "${red}未找到端口配置信息文件${none}"
    fi
    
    # 恢复Xray配置
    if [[ -n "$xray_config_file" && -f "$xray_config_file" ]]; then
        echo -e "${yellow}恢复Xray配置...${none}"
        mkdir -p "/usr/local/etc/xray"
        cp "$xray_config_file" "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
        echo -e "${green}Xray配置恢复成功${none}"
    else
        echo -e "${red}未找到Xray配置文件${none}"
    fi

    # 恢复HAProxy配置
    if [[ -n "$haproxy_config_file" && -f "$haproxy_config_file" ]]; then
        echo -e "${yellow}恢复HAProxy配置...${none}"
        mkdir -p "/etc/haproxy"
        cp "$haproxy_config_file" "$HAPROXY_CONFIG"
        chmod 644 "$HAPROXY_CONFIG"
        echo -e "${green}HAProxy配置恢复成功${none}"
    else
        echo -e "${red}未找到HAProxy配置文件${none}"
    fi
    
    # 重启HAProxy服务
    if [[ -n "$haproxy_config_file" && -f "$haproxy_config_file" ]]; then
        echo -e "$yellow 重启 HAProxy 服务... $none"
        if systemctl restart haproxy; then
            echo -e "$green HAProxy 服务重启成功! $none"
            log_info "恢复配置后重启HAProxy成功"
        else
            echo -e "$red HAProxy 服务重启失败，请手动检查! $none"
            log_error "恢复配置后重启HAProxy失败"
        fi
    fi
    
    # 重启Xray服务
    if [[ -n "$xray_config_file" && -f "$xray_config_file" ]]; then
        echo -e "$yellow 重启 Xray 服务... $none"
        if systemctl restart xray; then
            echo -e "$green Xray 服务重启成功! $none"
            log_info "恢复配置后重启Xray成功"
        else
            echo -e "$red Xray 服务重启失败，请手动检查! $none"
            log_error "恢复配置后重启Xray失败"
        fi
    fi
    
    # 删除临时目录
    rm -rf "$temp_dir"
    
    echo -e "${green}配置恢复过程完成${none}"
    log_info "配置恢复过程完成"
    
    pause
}


# 添加新端口配置
add_port_configuration() {
    echo
    echo -e "$yellow 添加新端口配置 $none"
    echo "----------------------------------------------------------------"
    
     # 检查是否安装了Xray
    if ! command -v xray &> /dev/null; then
        echo -e "${red}未检测到Xray安装，无法添加端口配置${none}"
        echo -e "是否现在安装Xray? [y/N]"
        read -r install_xray_now
        if [[ $install_xray_now =~ ^[Yy]$ ]]; then
            install_xray
        else
            echo -e "${yellow}已取消添加端口配置，请先安装Xray${none}"
            return
        fi
    fi

    # 获取本机IP
    if ! get_local_ips; then
        echo -e "${red}获取IP地址失败!${none}"
        echo -e "是否继续安装?[y/N]"
        read -r continue_install
        if [[ ! $continue_install =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # 网络栈选择
    echo
    echo -e "如果你的服务器是${magenta}双栈(同时有IPv4和IPv6的IP)${none}，请选择你要使用的IP类型"
    echo "如果你不懂这段话是什么意思, 请直接回车"
    read -p "$(echo -e "输入 ${cyan}4${none} 表示IPv4, ${cyan}6${none} 表示IPv6: ") " netstack

    # 检查用户选择的合法性
    if [[ $netstack = "4" ]]; then
        # 用户选择了IPv4
        if [[ -z "$IPv4" ]]; then
            echo -e "${red}错误: 你选择了IPv4，但服务器没有公网IPv4地址${none}"
            echo -e "请重新选择:"
            read -p "$(echo -e "输入 ${cyan}6${none} 表示IPv6, 或直接回车自动选择: ") " netstack
            
            if [[ $netstack = "6" ]]; then
                if [[ -z "$IPv6" ]]; then
                    echo -e "${red}错误: 服务器既没有IPv4也没有IPv6公网地址${none}"
                    warn "无法继续配置，请检查网络设置"
                    return 1
                else
                    ip=${IPv6}
                    netstack=6
                fi
            else
                # 用户未选择，检查是否有任何可用IP
                if [[ -n "$IPv4" ]]; then
                    ip=${IPv4}
                    netstack=4
                elif [[ -n "$IPv6" ]]; then
                    ip=${IPv6}
                    netstack=6
                else
                    echo -e "${red}错误: 服务器既没有IPv4也没有IPv6公网地址${none}"
                    warn "无法继续配置，请检查网络设置"
                    return 1
                fi
            fi
        else
            ip=${IPv4}
        fi
    elif [[ $netstack = "6" ]]; then
        # 用户选择了IPv6
        if [[ -z "$IPv6" ]]; then
            echo -e "${red}错误: 你选择了IPv6，但服务器没有公网IPv6地址${none}"
            echo -e "请重新选择:"
            read -p "$(echo -e "输入 ${cyan}4${none} 表示IPv4, 或直接回车自动选择: ") " netstack
            
            if [[ $netstack = "4" ]]; then
                if [[ -z "$IPv4" ]]; then
                    echo -e "${red}错误: 服务器既没有IPv4也没有IPv6公网地址${none}"
                    warn "无法继续配置，请检查网络设置"
                    return 1
                else
                    ip=${IPv4}
                    netstack=4
                fi
            else
                # 用户未选择，检查是否有任何可用IP
                if [[ -n "$IPv4" ]]; then
                    ip=${IPv4}
                    netstack=4
                elif [[ -n "$IPv6" ]]; then
                    ip=${IPv6}
                    netstack=6
                else
                    echo -e "${red}错误: 服务器既没有IPv4也没有IPv6公网地址${none}"
                    warn "无法继续配置，请检查网络设置"
                    return 1
                fi
            fi
        else
            ip=${IPv6}
        fi
    else
        # 用户未选择，默认优先使用IPv4
        if [[ -n "$IPv4" ]]; then
            ip=${IPv4}
            netstack=4
        elif [[ -n "$IPv6" ]]; then
            ip=${IPv6}
            netstack=6
        else
            echo -e "${red}错误: 服务器既没有IPv4也没有IPv6公网地址${none}"
            warn "无法继续配置，请检查网络设置"
            return 1
        fi
    fi

    echo -e "${green}已选择网络类型: ${none}$([ "$netstack" = "4" ] && echo "IPv4" || echo "IPv6")"
    echo -e "${green}使用的IP地址: ${cyan}$ip${none}"
    
    # 端口选择
    while :; do
    read -p "$(echo -e "请输入端口 [${magenta}1-65535${none}]，建议使用大于1024的端口（默认: ${cyan}7999${none}）: ")" port
    if [[ -z "$port" ]]; then
        port=7999
    fi
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        error
        continue
    fi
        
        # 检查端口是否已被配置
        if check_port_exists "$port"; then
            echo -e "${red}端口 $port 已被配置，请选择其他端口${none}"
            continue
        fi
        
        # 检查端口是否被占用
        if lsof -i:"$port" >/dev/null 2>&1; then
            echo -e "${red}端口 $port 已被其他程序占用，请选择其他端口${none}"
            continue
        fi
        
        echo
        echo -e "$yellow 端口 (Port) = ${cyan}${port}${none}"
        echo "----------------------------------------------------------------"
        break
    done
    
    # 生成UUID
    uuidSeed=${ip}$(cat /proc/sys/kernel/hostname)$(cat /etc/timezone)${port}$(date +%s%N)
    default_uuid=$(curl -sL https://www.uuidtools.com/api/generate/v3/namespace/ns:dns/name/${uuidSeed} | grep -oP '[^-]{8}-[^-]{4}-[^-]{4}-[^-]{4}-[^-]{12}')
    
    while :; do
        echo -e "请输入 "${yellow}"UUID"${none}" "
        read -p "$(echo -e "(默认ID: ${cyan}${default_uuid}${none}): ")" uuid
        [ -z "$uuid" ] && uuid=$default_uuid
        
        if [[ ! "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
            error
            continue
        fi
        
        echo
        echo -e "$yellow UUID = ${cyan}$uuid${none}"
        echo "----------------------------------------------------------------"
        break
    done
    
# 生成密钥
echo -e "${yellow}正在自动生成密钥对...${none}"
local key_pair_output
key_pair_output=$(xray x25519)

# 从输出中提取默认的私钥和公钥
local default_private_key
default_private_key=$(echo "$key_pair_output" | awk -F':[[:space:]]*' 'tolower($1) ~ /private[[:space:]]*key/ {print $2; exit}')
local default_public_key
default_public_key=$(echo "$key_pair_output" | awk -F':[[:space:]]*' 'tolower($1) ~ /public[[:space:]]*key/ {print $2; exit}')

# 检查密钥是否成功生成
if [[ -z "$default_private_key" || -z "$default_public_key" ]]; then
    echo -e "${red}错误: 自动生成密钥失败! xray x25519 输出如下:${none}"
    echo "$key_pair_output"
    log_error "自动生成密钥失败: $key_pair_output"
    return 1
fi

echo -e "请输入 "$yellow"x25519 Private Key"$none" x25519私钥 :"
read -p "$(echo -e "(留空使用默认生成的私钥): ")" private_key

local public_key
if [[ -z "$private_key" ]]; then
    # 用户接受默认值
    private_key=$default_private_key
    public_key=$default_public_key
else
    # 用户输入了自定义私钥，我们需要为其计算公钥
    echo -e "${yellow}正在为您输入的私钥计算对应的公钥...${none}"
    public_key=$(xray x25519 -i "$private_key" 2>&1 | awk -F':[[:space:]]*' 'tolower($1) ~ /public[[:space:]]*key/ {print $2; exit}')
    if [[ -z "$public_key" ]]; then
       echo -e "${red}无法从您输入的私钥派生出公钥，请检查私钥是否正确。${none}"
       log_error "无法从用户输入的私钥派生公钥"
       return 1
    fi
fi

echo
echo -e "$yellow 私钥 (PrivateKey) = ${cyan}${private_key}${none}"
echo -e "$yellow 公钥 (PublicKey) = ${cyan}${public_key}${none}"
echo "----------------------------------------------------------------"

   
    # ShortID
    default_shortid=$(echo -n ${uuid} | sha1sum | head -c 16)
    while :; do
        echo -e "请输入 "$yellow"ShortID"$none" :"
        read -p "$(echo -e "(默认ShortID: ${cyan}${default_shortid}${none}): ")" shortid
        [ -z "$shortid" ] && shortid=$default_shortid
        
        if [[ ${#shortid} -gt 16 ]]; then
            error
            continue
        elif [[ $(( ${#shortid} % 2 )) -ne 0 ]]; then
            error
            continue
        fi
        
        echo
        echo -e "$yellow ShortID = ${cyan}${shortid}${none}"
        echo "----------------------------------------------------------------"
        break
    done
    
    # 目标网站
    echo -e "请输入一个 ${magenta}合适的域名${none} 作为 SNI"
    read -p "$(echo -e "(例如: learn.microsoft.com): ")" domain
    [ -z "$domain" ] && domain="learn.microsoft.com"
    
    echo
    echo -e "$yellow SNI = ${cyan}$domain${none}"
    echo "----------------------------------------------------------------"
    
    # 保存基本端口配置
    save_port_info "$port" "$uuid" "$private_key" "$public_key" "$shortid" "$domain"
    
    # SOCKS5 代理设置
    echo
    echo -e "$yellow 是否为此端口配置 SOCKS5 转发代理? $none"
    read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" socks5_enabled
    [ -z "$socks5_enabled" ] && socks5_enabled="n"
    
    if [[ $socks5_enabled = "y" ]]; then
        configure_socks5_for_port "$port"
        
        # 自动配置HAProxy（不给选项，直接启用）
        echo
        echo -e "${yellow}正在为SOCKS5代理配置HAProxy...${none}"
        
        # 默认HAProxy端口为VLESS端口+10
        local default_haproxy_port=$((port + 10))
        
        # 检查端口是否被占用
        while lsof -i:"$default_haproxy_port" >/dev/null 2>&1; do
            echo -e "${yellow}端口 $default_haproxy_port 已被占用，自动选择下一个可用端口${none}"
            default_haproxy_port=$((default_haproxy_port + 1))
        done
        
        # 使用默认线程数和最大连接数
        local haproxy_threads=12
        local haproxy_maxconn=400
        
        # 保存HAProxy配置
        set_port_haproxy_config "$port" "y" "$default_haproxy_port" "$haproxy_threads" "$haproxy_maxconn"
        update_haproxy_config
        
        echo -e "${green}HAProxy已配置，端口: $default_haproxy_port, 线程数: $haproxy_threads, 最大连接数: $haproxy_maxconn${none}"
        log_info "为端口 $port 自动配置HAProxy，端口: $default_haproxy_port"
    fi
    
    # 更新配置文件
    update_config_file
    
    # 重启 Xray
    echo
    echo -e "$yellow 重启 Xray 服务... $none"
    if systemctl restart xray; then
        echo -e "$green Xray 服务重启成功! $none"
        log_info "添加端口 $port 后重启 Xray 成功"
    else
        echo -e "$red Xray 服务重启失败，请手动检查! $none"
        log_error "添加端口 $port 后重启 Xray 失败"
    fi
    
    # 生成连接信息
    generate_connection_info "$port" "$uuid" "$public_key" "$shortid" "$domain" "$ip" "$netstack"
    
    echo
    echo -e "$green 端口配置成功添加! $none"
    log_info "端口 $port 配置成功添加"
    pause
}


# 生成单个端口的连接信息
generate_connection_info() {
    local port=$1
    local uuid=$2
    local public_key=$3
    local shortid=$4
    local domain=$5
    local ip=$6
    local netstack=$7
    
    echo
    echo "---------- 端口 $port 的 Xray 配置信息 -------------"
    echo -e "$green ---提示..这是 VLESS Reality 服务器配置--- $none"
    echo -e "$yellow 地址 (Address) = $cyan${ip}$none"
    echo -e "$yellow 端口 (Port) = ${cyan}${port}${none}"
    echo -e "$yellow 用户ID (User ID / UUID) = $cyan${uuid}$none"
    echo -e "$yellow 流控 (Flow) = ${cyan}xtls-rprx-vision${none}"
    echo -e "$yellow 加密 (Encryption) = ${cyan}none${none}"
    echo -e "$yellow 传输协议 (Network) = ${cyan}tcp$none"
    echo -e "$yellow 伪装类型 (header type) = ${cyan}none$none"
    echo -e "$yellow 底层传输安全 (TLS) = ${cyan}reality$none"
    echo -e "$yellow SNI = ${cyan}${domain}$none"
    echo -e "$yellow 指纹 (Fingerprint) = ${cyan}random${none}"
    echo -e "$yellow 公钥 (PublicKey) = ${cyan}${public_key}$none"
    echo -e "$yellow ShortId = ${cyan}${shortid}$none"
    echo -e "$yellow SpiderX = ${cyan}${none}"
    
    # 检查是否配置了SOCKS5代理
    local port_info=$(get_port_info "$port")
    if [[ -n "$port_info" ]]; then
        local socks5_enabled=$(echo "$port_info" | jq -r '.socks5.enabled // false')
        if [[ "$socks5_enabled" == "true" ]]; then
            local socks5_address=$(echo "$port_info" | jq -r '.socks5.address')
            local socks5_port=$(echo "$port_info" | jq -r '.socks5.port')
            echo -e "$yellow SOCKS5代理 = ${cyan}已启用 (${socks5_address}:${socks5_port})$none"
            
            # 显示HAProxy信息
            local haproxy_enabled=$(echo "$port_info" | jq -r '.haproxy.enabled // false')
            if [[ "$haproxy_enabled" == "true" ]]; then
                local haproxy_port=$(echo "$port_info" | jq -r '.haproxy.port')
                local haproxy_threads=$(echo "$port_info" | jq -r '.haproxy.threads')
                local haproxy_maxconn=$(echo "$port_info" | jq -r '.haproxy.maxconn')
                echo -e "$yellow HAProxy = ${cyan}已启用$none"
                echo -e "$yellow HAProxy端口 = ${cyan}${haproxy_port}$none"
                echo -e "$yellow HAProxy线程 = ${cyan}${haproxy_threads}$none"
                echo -e "$yellow HAProxy最大连接 = ${cyan}${haproxy_maxconn}$none"
                
                # 生成HAProxy连接地址
                local haproxy_ip
                if [[ $netstack = "6" ]]; then
                    haproxy_ip="[$ip]"
                else
                    haproxy_ip="$ip"
                fi
                
                echo -e "$yellow HAProxy地址 = ${cyan}${haproxy_ip}:${haproxy_port}$none"
                
                # 生成SOCKS5客户端配置示例
                echo
                echo "---------- SOCKS5 客户端配置示例 (通过HAProxy转发) ----------"
                echo -e "地址: ${cyan}${haproxy_ip}${none}"
                echo -e "端口: ${cyan}${haproxy_port}${none}"
                
                # 如果SOCKS5需要认证，显示认证信息
                local auth_needed=$(echo "$port_info" | jq -r '.socks5.auth_needed // false')
                if [[ "$auth_needed" == "true" ]]; then
                    local socks5_user=$(echo "$port_info" | jq -r '.socks5.username')
                    echo -e "用户名: ${cyan}${socks5_user}${none}"
                    echo -e "密码: ${cyan}请使用配置时设置的密码${none}"
                fi
            fi
        fi
    fi
    
    # 生成链接
    if [[ $netstack = "6" ]]; then
        ip="[$ip]"
    fi
    
    vless_reality_url="vless://${uuid}@${ip}:${port}?flow=xtls-rprx-vision&encryption=none&type=tcp&security=reality&sni=${domain}&fp=random&pbk=${public_key}&sid=${shortid}&#VLESS_R_${port}"
    
    echo
    echo "---------- VLESS Reality URL ----------"
    echo -e "${cyan}${vless_reality_url}${none}"
    echo
    
      
    # 生成SOCKS5链接（如果配置了HAProxy）
    if [[ -n "$port_info" ]]; then
        local haproxy_enabled=$(echo "$port_info" | jq -r '.haproxy.enabled // false')
        if [[ "$haproxy_enabled" == "true" ]]; then
            local haproxy_port=$(echo "$port_info" | jq -r '.haproxy.port')
            local haproxy_ip
            if [[ $netstack = "6" ]]; then
                haproxy_ip="[$ip]"
            else
                haproxy_ip="$ip"
            fi
            
            echo
            echo "---------- SOCKS5 直连URL (HAProxy) ----------"
            local auth_needed=$(echo "$port_info" | jq -r '.socks5.auth_needed // false')
            local socks5_url
            
            if [[ "$auth_needed" == "true" ]]; then
                local socks5_user=$(echo "$port_info" | jq -r '.socks5.username')
                socks5_url="socks5://${socks5_user}:password@${haproxy_ip}:${haproxy_port}"
                echo -e "${cyan}${socks5_url}${none} (请替换password为实际密码)"
            else
                socks5_url="socks5://${haproxy_ip}:${haproxy_port}"
                echo -e "${cyan}${socks5_url}${none}"
            fi
            
     
        fi
    fi
    
    # 保存信息到文件
    local output_file="$HOME/vless_reality_${port}.txt"
    echo "---------- 端口 $port 的 Xray 配置信息 -------------" > "$output_file"
    echo "VLESS Reality 服务器配置" >> "$output_file"
    echo "地址 (Address) = ${ip}" >> "$output_file"
    echo "端口 (Port) = ${port}" >> "$output_file"
    echo "用户ID (User ID / UUID) = ${uuid}" >> "$output_file"
    echo "流控 (Flow) = xtls-rprx-vision" >> "$output_file"
    echo "加密 (Encryption) = none" >> "$output_file"
    echo "传输协议 (Network) = tcp" >> "$output_file"
    echo "伪装类型 (header type) = none" >> "$output_file"
    echo "底层传输安全 (TLS) = reality" >> "$output_file"
    echo "SNI = ${domain}" >> "$output_file"
    echo "指纹 (Fingerprint) = random" >> "$output_file"
    echo "公钥 (PublicKey) = ${public_key}" >> "$output_file"
    echo "ShortId = ${shortid}" >> "$output_file"
    echo "SpiderX = " >> "$output_file"
    
    # 添加SOCKS5和HAProxy信息到文件
    if [[ -n "$port_info" ]]; then
        local socks5_enabled=$(echo "$port_info" | jq -r '.socks5.enabled // false')
        if [[ "$socks5_enabled" == "true" ]]; then
            local socks5_address=$(echo "$port_info" | jq -r '.socks5.address')
            local socks5_port=$(echo "$port_info" | jq -r '.socks5.port')
            echo "SOCKS5代理 = 已启用 (${socks5_address}:${socks5_port})" >> "$output_file"
            
            local haproxy_enabled=$(echo "$port_info" | jq -r '.haproxy.enabled // false')
            if [[ "$haproxy_enabled" == "true" ]]; then
                local haproxy_port=$(echo "$port_info" | jq -r '.haproxy.port')
                local haproxy_threads=$(echo "$port_info" | jq -r '.haproxy.threads')
                local haproxy_maxconn=$(echo "$port_info" | jq -r '.haproxy.maxconn')
                
                echo "HAProxy = 已启用" >> "$output_file"
                echo "HAProxy端口 = ${haproxy_port}" >> "$output_file"
                echo "HAProxy线程 = ${haproxy_threads}" >> "$output_file"
                echo "HAProxy最大连接 = ${haproxy_maxconn}" >> "$output_file"
                
                local haproxy_ip
                if [[ $netstack = "6" ]]; then
                    haproxy_ip="[$ip]"
                else
                    haproxy_ip="$ip"
                fi
                
                echo "HAProxy地址 = ${haproxy_ip}:${haproxy_port}" >> "$output_file"
                
                echo >> "$output_file"
                echo "---------- SOCKS5 客户端配置示例 (通过HAProxy转发) ----------" >> "$output_file"
                echo "地址: ${haproxy_ip}" >> "$output_file"
                echo "端口: ${haproxy_port}" >> "$output_file"
                
                local auth_needed=$(echo "$port_info" | jq -r '.socks5.auth_needed // false')
                if [[ "$auth_needed" == "true" ]]; then
                    local socks5_user=$(echo "$port_info" | jq -r '.socks5.username')
                    echo "用户名: ${socks5_user}" >> "$output_file"
                    echo "密码: 请使用配置时设置的密码" >> "$output_file"
                fi
            fi
        fi
    fi
    
    echo >> "$output_file"
    echo "---------- VLESS Reality URL ----------" >> "$output_file"
    echo "${vless_reality_url}" >> "$output_file"
    
    # 如果配置了HAProxy，添加SOCKS5链接
    if [[ -n "$port_info" ]]; then
        local haproxy_enabled=$(echo "$port_info" | jq -r '.haproxy.enabled // false')
        if [[ "$haproxy_enabled" == "true" ]]; then
            local haproxy_port=$(echo "$port_info" | jq -r '.haproxy.port')
            local haproxy_ip
            if [[ $netstack = "6" ]]; then
                haproxy_ip="[$ip]"
            else
                haproxy_ip="$ip"
            fi
            
            echo >> "$output_file"
            echo "---------- SOCKS5 直连URL (HAProxy) ----------" >> "$output_file"
            local auth_needed=$(echo "$port_info" | jq -r '.socks5.auth_needed // false')
            
            if [[ "$auth_needed" == "true" ]]; then
                local socks5_user=$(echo "$port_info" | jq -r '.socks5.username')
                echo "socks5://${socks5_user}:password@${haproxy_ip}:${haproxy_port} (请替换password为实际密码)" >> "$output_file"
            else
                echo "socks5://${haproxy_ip}:${haproxy_port}" >> "$output_file"
            fi
        fi
    fi
    
    echo
    echo "链接信息已保存到 $output_file"
    log_info "生成端口 $port 的连接信息，保存到 $output_file"
}

# 为指定端口配置SOCKS5代理
configure_socks5_for_port() {
    local port=$1
    local socks5_address=""
    
    # 循环直到获取有效的非本地地址
    while true; do
        read -p "$(echo -e "请输入 SOCKS5 服务器地址: ")" input_address
        if [ -z "$input_address" ]; then
            error
            continue
        fi
        
        # 检查是否为本地地址
        if [[ "$input_address" == "127.0.0.1" || "$input_address" == "localhost" ]]; then
            echo -e "${red}错误: 不能将SOCKS5地址设置为本地地址 ($input_address)${none}"
            echo -e "${yellow}请配置SOCKS5地址为公网IP或域名${none}"
            continue
        fi
        
        socks5_address=$input_address
        break
    done
    
    # SOCKS5 端口
    local socks5_port=""
    while true; do
        read -p "$(echo -e "请输入 SOCKS5 端口: ")" input_port
        if [ -z "$input_port" ] || ! [[ "$input_port" =~ ^[0-9]+$ ]] || [[ "$input_port" -lt 1 ]] || [[ "$input_port" -gt 65535 ]]; then
            error
            continue
        fi
        
        socks5_port=$input_port
        break
    done
    
    # 是否需要认证
    echo -e "是否需要用户名密码认证?"
    read -r -p "$(echo -e "(y/n, 默认: ${cyan}y${none}): ")" auth_needed
    [ -z "$auth_needed" ] && auth_needed="y"

    local socks5_user=""
    local socks5_pass=""
    if [[ $auth_needed = "y" ]]; then
        while [[ -z "$socks5_user" ]]; do
            read -r -p "$(echo -e "请输入 SOCKS5 用户名: ")" socks5_user
            [[ -z "$socks5_user" ]] && echo -e "${red}用户名不能为空${none}"
        done

        while [[ -z "$socks5_pass" ]]; do
            read -r -s -p "$(echo -e "请输入 SOCKS5 密码（输入时不会显示）: ")" socks5_pass
            echo
            [[ -z "$socks5_pass" ]] && echo -e "${red}密码不能为空${none}"
        done
    fi
    
    # 是否启用 UDP over TCP
    echo -e "是否启用 UDP over TCP?"
    read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" udp_over_tcp
    [ -z "$udp_over_tcp" ] && udp_over_tcp="n"
    
    if [[ $udp_over_tcp = "n" ]]; then
        echo -e "$yellow 注意：未启用 UDP over TCP，仅进行 TCP 转发 $none"
    fi
    
    # 设置SOCKS5代理配置
    set_port_socks5_config "$port" "y" "$socks5_address" "$socks5_port" "$auth_needed" "$socks5_user" "$socks5_pass" "$udp_over_tcp"

    # HAProxy配置部分
    # 默认HAProxy端口为VLESS端口+10
    local default_haproxy_port=$((port + 10))
    
    # 检查端口是否被占用
    while lsof -i:"$default_haproxy_port" >/dev/null 2>&1; do
        echo -e "${yellow}端口 $default_haproxy_port 已被占用，自动选择下一个可用端口${none}"
        default_haproxy_port=$((default_haproxy_port + 1))
    done
    
    # 使用默认线程数和最大连接数
    local haproxy_threads=12
    local haproxy_maxconn=400
    
    # 保存HAProxy配置
    set_port_haproxy_config "$port" "y" "$default_haproxy_port" "$haproxy_threads" "$haproxy_maxconn"
    update_haproxy_config
    
    echo -e "${green}SOCKS5代理和HAProxy配置成功添加到端口 $port${none}"
    log_info "为端口 $port 配置SOCKS5代理和HAProxy"
    return 0
}

# 设置端口的SOCKS5代理配置
set_port_socks5_config() {
    local port=$1
    local enabled=$2
    local socks5_address=$3
    local socks5_port=$4
    local auth_needed=$5
    local socks5_user=$6
    local socks5_pass=$7
    local udp_over_tcp=$8
    
    # 创建SOCKS5配置对象
    local socks5_config
    if [[ "$enabled" == "y" ]]; then
        socks5_config=$(jq -n --arg address "$socks5_address" \
                           --arg port "$socks5_port" \
                           --arg auth_needed "$([ "$auth_needed" == "y" ] && echo "true" || echo "false")" \
                           --arg username "$socks5_user" \
                           --arg password "$socks5_pass" \
                           --arg udp_over_tcp "$([ "$udp_over_tcp" == "y" ] && echo "true" || echo "false")" \
                           '{
                               "enabled": true,
                               "address": $address,
                               "port": ($port | tonumber),
                               "auth_needed": ($auth_needed == "true"),
                               "username": $username,
                               "password": $password,
                               "udp_over_tcp": ($udp_over_tcp == "true")
                           }')
    else
        socks5_config="null"
    fi
    
    # 更新端口的SOCKS5配置
    jq "(.ports[] | select(.port == $port)) |= (.socks5 = $socks5_config)" "$PORT_INFO_FILE" > "${PORT_INFO_FILE}.tmp"
    mv "${PORT_INFO_FILE}.tmp" "$PORT_INFO_FILE"
    chmod 600 "$PORT_INFO_FILE"
    log_info "设置端口 $port 的SOCKS5代理配置: 启用=$enabled"
}

# 设置端口的HAProxy配置
set_port_haproxy_config() {
    local port=$1
    local enabled=$2
    local haproxy_port=$3
    local haproxy_threads=$4
    local haproxy_maxconn=$5
    
    # 创建HAProxy配置对象
    local haproxy_config
    if [[ "$enabled" == "y" ]]; then
        haproxy_config="{
            \"enabled\": true,
            \"port\": $haproxy_port,
            \"threads\": $haproxy_threads,
            \"maxconn\": $haproxy_maxconn
        }"
    else
        haproxy_config="null"
    fi
    
    # 更新端口的HAProxy配置
    jq "(.ports[] | select(.port == $port)) |= (.haproxy = $haproxy_config)" "$PORT_INFO_FILE" > "${PORT_INFO_FILE}.tmp"
    mv "${PORT_INFO_FILE}.tmp" "$PORT_INFO_FILE"
    chmod 600 "$PORT_INFO_FILE"
    log_info "设置端口 $port 的HAProxy配置: 启用=$enabled, 端口=$haproxy_port"
}

# 更新HAProxy配置文件
update_haproxy_config() {
    # 确保HAProxy目录存在
    mkdir -p /etc/haproxy
    
    # 备份当前配置
    if [[ -f "$HAPROXY_CONFIG" ]]; then
        cp "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 创建基本配置
    # 找到启用HAProxy的配置中最大的线程数
    local max_threads=12
    jq -c '.ports[] | select(.haproxy != null and .haproxy.enabled == true)' "$PORT_INFO_FILE" | while read -r port_info; do
        local threads=$(echo "$port_info" | jq -r '.haproxy.threads')
        if [[ $threads -gt $max_threads ]]; then
            max_threads=$threads
        fi
    done
    
    cat > "$HAPROXY_CONFIG" << EOL
global
    maxconn 5000
    nbthread $max_threads        # 使用所有配置中最大的线程数
    tune.bufsize 32768
    tune.maxrewrite 1024

defaults
    mode tcp
    timeout connect 15s
    timeout client 30s
    timeout server 30s
    option tcp-smart-accept
    option tcp-smart-connect
    option tcplog

EOL
    
    # 添加每个启用了HAProxy的端口配置
    jq -c '.ports[] | select(.haproxy != null and .haproxy.enabled == true)' "$PORT_INFO_FILE" | while read -r port_info; do
        local port=$(echo "$port_info" | jq -r '.port')
        local haproxy_port=$(echo "$port_info" | jq -r '.haproxy.port')
        local haproxy_maxconn=$(echo "$port_info" | jq -r '.haproxy.maxconn')
        local socks5_address=$(echo "$port_info" | jq -r '.socks5.address')
        local socks5_port=$(echo "$port_info" | jq -r '.socks5.port')
        
        cat >> "$HAPROXY_CONFIG" << EOL
frontend socks_front_$port
    bind *:$haproxy_port
    default_backend socks_servers_$port

backend socks_servers_$port
    server socks1 $socks5_address:$socks5_port maxconn $haproxy_maxconn check inter 5000 rise 2 fall 3

EOL
    done
    
    # 重启HAProxy服务
    if systemctl is-active --quiet haproxy; then
        systemctl restart haproxy
    else
        systemctl start haproxy
    fi
    
    # 检查HAProxy服务是否正常运行
    sleep 2
    if systemctl is-active --quiet haproxy; then
        echo -e "${green}HAProxy重启成功${none}"
        log_info "HAProxy服务重启成功"
    else
        log_error "HAProxy服务启动失败"
        echo -e "${red}HAProxy服务启动失败，请检查配置${none}"
    fi
}


# 修改端口配置
modify_port_configuration() {
    echo
    echo -e "$yellow 修改端口配置 $none"
    echo "----------------------------------------------------------------"
    
    if [[ ! -s "$PORT_INFO_FILE" ]] || [[ $(jq '.ports | length' "$PORT_INFO_FILE") -eq 0 ]]; then
        echo -e "$red 目前没有配置任何端口，请先添加端口配置 $none"
        return
    fi
    
    # 显示所有端口
    list_port_configurations
    
    # 选择要修改的端口
    local port_count=$(jq '.ports | length' "$PORT_INFO_FILE")
    while :; do
        read -p "$(echo -e "请选择要修改的配置序号 [${green}1-$port_count${none}]: ")" port_index
        
        if [[ -z "$port_index" ]] || ! [[ "$port_index" =~ ^[0-9]+$ ]] || [[ "$port_index" -lt 1 ]] || [[ "$port_index" -gt "$port_count" ]]; then
            error
            continue
        fi
        
        # 获取对应的端口信息
        local selected_port_info=$(jq -c ".ports[$(($port_index-1))]" "$PORT_INFO_FILE")
        local port=$(echo "$selected_port_info" | jq -r '.port')
        
        echo
        echo -e "$yellow 正在修改端口 ${cyan}$port${none} 的配置 $none"
        break
    done
    
    # 备份当前配置信息，用于后续比较
    local original_config_md5=$(jq -c '.ports' "$PORT_INFO_FILE" | md5sum | cut -d ' ' -f1)
    
    # 获取网络环境信息，并保存到本地变量
    local current_ip=""
    local current_netstack=""
    
    # 确保我们有IP地址
    if ! get_local_ips; then
        echo -e "${red}获取IP地址失败!${none}"
        echo -e "继续配置可能会导致连接信息不完整"
    fi
    
    # 根据用户最初的选择确定使用的网络类型和IP
    # 尝试读取这个端口最初使用的网络栈类型
    local port_connection_file="$HOME/vless_reality_${port}.txt"
    
    if [[ -f "$port_connection_file" ]]; then
        # 尝试从连接信息文件中获取之前使用的IP类型
        if grep -q "\[" "$port_connection_file"; then
            # 包含方括号的IP地址是IPv6
            current_netstack=6
            current_ip=$IPv6
            echo -e "${green}检测到此端口之前使用IPv6配置${none}"
        else
            # 否则假定为IPv4
            current_netstack=4
            current_ip=$IPv4
            echo -e "${green}检测到此端口之前使用IPv4配置${none}"
        fi
    fi
    
    # 如果无法确定之前的选择，使用默认优先级
    if [[ -z "$current_ip" ]]; then
        if [[ -n "$IPv4" ]]; then
            current_ip=$IPv4
            current_netstack=4
            echo -e "${yellow}使用默认IPv4配置${none}"
        elif [[ -n "$IPv6" ]]; then
            current_ip=$IPv6
            current_netstack=6
            echo -e "${yellow}使用默认IPv6配置${none}"
        fi
    fi
    
    # 如果选择的网络类型没有对应的IP地址，提示错误并尝试切换
    if [[ "$current_netstack" == "4" && -z "$IPv4" ]]; then
        echo -e "${red}错误: 之前配置使用IPv4，但现在无法获取IPv4地址${none}"
        if [[ -n "$IPv6" ]]; then
            echo -e "${yellow}自动切换到IPv6${none}"
            current_ip=$IPv6
            current_netstack=6
        else
            echo -e "${red}无法获取任何公网IP地址${none}"
        fi
    elif [[ "$current_netstack" == "6" && -z "$IPv6" ]]; then
        echo -e "${red}错误: 之前配置使用IPv6，但现在无法获取IPv6地址${none}"
        if [[ -n "$IPv4" ]]; then
            echo -e "${yellow}自动切换到IPv4${none}"
            current_ip=$IPv4
            current_netstack=4
        else
            echo -e "${red}无法获取任何公网IP地址${none}"
        fi
    fi
    
    # 修改菜单
    echo "----------------------------------------------------------------"
    echo -e "  ${green}1.${none} 修改UUID"
    echo -e "  ${green}2.${none} 修改域名(SNI)"
    echo -e "  ${green}3.${none} 修改ShortID"
    echo -e "  ${green}4.${none} 修改SOCKS5代理设置"
    echo -e "  ${green}5.${none} 管理HAProxy设置"  # 新增选项
    echo -e "  ${green}6.${none} 返回上一级菜单"   # 原来的选项5改为6
    echo "----------------------------------------------------------------"
    
    read -p "$(echo -e "请选择 [${green}1-6${none}]: ")" modify_choice  # 修改为1-6
    
    case $modify_choice in
        1)
            # 修改UUID
            modify_port_uuid "$port"
            ;;
            
        2)
            # 修改域名
            modify_port_domain "$port"
            ;;
            
        3)
            # 修改ShortID
            modify_port_shortid "$port"
            ;;
            
        4)
            # 修改SOCKS5代理设置
            modify_port_socks5 "$port"
            ;;
            
        5)
            # 管理HAProxy设置
            modify_port_haproxy "$port"
            ;;
            
        6)
            return
            ;;
            
        *)
            error
            return
            ;;
    esac
    
    # 检查配置是否实际发生了变化
    local new_config_md5=$(jq -c '.ports' "$PORT_INFO_FILE" | md5sum | cut -d ' ' -f1)
    
    if [[ "$original_config_md5" != "$new_config_md5" ]]; then
        # 配置已更改，需要更新Xray配置文件
        echo -e "$yellow 配置已更改，更新Xray配置... $none"
        
        # 更新配置文件
        update_config_file
        
        # 重启 Xray
        echo
        echo -e "$yellow 重启 Xray 服务... $none"
        if systemctl restart xray; then
            echo -e "$green Xray 服务重启成功! $none"
            log_info "修改端口 $port 配置后重启 Xray 成功"
        else
            echo -e "$red Xray 服务重启失败，请手动检查! $none"
            log_error "修改端口 $port 配置后重启 Xray 失败"
        fi
        
        # 使用保存的网络环境信息为修改后的端口生成新的连接信息
        local port_info=$(get_port_info "$port")
        local uuid=$(echo "$port_info" | jq -r '.uuid')
        local public_key=$(echo "$port_info" | jq -r '.public_key')
        local shortid=$(echo "$port_info" | jq -r '.shortid')
        local domain=$(echo "$port_info" | jq -r '.domain')
        
        # 使用之前保存的网络环境信息
        generate_connection_info "$port" "$uuid" "$public_key" "$shortid" "$domain" "$current_ip" "$current_netstack"
    else
        echo -e "$yellow 未检测到配置变更，保持现有配置 $none"
        log_info "查看端口 $port 配置，未进行修改"
    fi
    
    pause
}



# 修改端口的UUID
modify_port_uuid() {
    local port=$1
    local port_info=$(get_port_info "$port")
    local old_uuid=$(echo "$port_info" | jq -r '.uuid')
    
    echo
    echo -e "$yellow 修改UUID $none"
    echo "----------------------------------------------------------------"
    echo -e "当前UUID: $cyan$old_uuid$none"
    
    # 生成新的默认UUID
    local ip=$([ "$netstack" = "6" ] && echo "$IPv6" || echo "$IPv4")
    local uuidSeed=${ip}$(cat /proc/sys/kernel/hostname)$(cat /etc/timezone)
    local default_uuid=$(curl -sL https://www.uuidtools.com/api/generate/v3/namespace/ns:dns/name/${uuidSeed} | grep -oP '[^-]{8}-[^-]{4}-[^-]{4}-[^-]{4}-[^-]{12}')
    
    while :; do
        echo -e "请输入新的UUID"
        read -p "$(echo -e "(留空使用随机UUID: ${cyan}${default_uuid}${none}): ")" new_uuid
        [ -z "$new_uuid" ] && new_uuid=$default_uuid
        
        if [[ ! "$new_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
            error
            continue
        fi
        
        # 生成新的密钥
        local seed=$(echo -n ${new_uuid} | md5sum | head -c 32 | base64 -w 0 | tr '+/' '-_' | tr -d '=')
        local tmp_key=$(echo -n ${seed} | xargs xray x25519 -i 2>&1)
        local new_private_key=$(echo "$tmp_key" | awk -F':[[:space:]]*' 'tolower($1) ~ /^private[[:space:]]*key$/ {print $2; exit}')
        local new_public_key=$(echo "$tmp_key" | awk -F':[[:space:]]*' 'tolower($1) ~ /^public[[:space:]]*key$/ {print $2; exit}')

        # 获取旧密钥对
        local old_private_key=$(echo "$port_info" | jq -r '.private_key')
        local old_public_key=$(echo "$port_info" | jq -r '.public_key')

        echo
        echo -e "$yellow 旧UUID = ${cyan}$old_uuid${none}"
        echo -e "$yellow 旧私钥 = ${cyan}$old_private_key${none}"
        echo -e "$yellow 旧公钥 = ${cyan}$old_public_key${none}"
        echo
        echo -e "$yellow 新UUID = ${cyan}$new_uuid${none}"
        echo -e "$yellow 新私钥 = ${cyan}$new_private_key${none}"
        echo -e "$yellow 新公钥 = ${cyan}$new_public_key${none}"
        echo
        
        # 生成新的ShortID
        local new_shortid=$(echo -n ${new_uuid} | sha1sum | head -c 16)
        
        echo
        echo -e "$yellow 新UUID = ${cyan}$new_uuid${none}"
        echo -e "$yellow 新私钥 = ${cyan}$new_private_key${none}"
        echo -e "$yellow 新公钥 = ${cyan}$new_public_key${none}"
        echo -e "$yellow 新ShortID = ${cyan}$new_shortid${none}"
        echo
        
        # 保存修改
        local domain=$(echo "$port_info" | jq -r '.domain')
        save_port_info "$port" "$new_uuid" "$new_private_key" "$new_public_key" "$new_shortid" "$domain"
        
        # 保持SOCKS5配置不变
        local socks5_config=$(echo "$port_info" | jq -r '.socks5')
        if [[ "$socks5_config" != "null" ]]; then
            local socks5_enabled=$(echo "$socks5_config" | jq -r '.enabled // false')
            if [[ "$socks5_enabled" == "true" ]]; then
                local socks5_address=$(echo "$socks5_config" | jq -r '.address')
                local socks5_port=$(echo "$socks5_config" | jq -r '.port')
                local auth_needed=$(echo "$socks5_config" | jq -r '.auth_needed')
                local auth_needed_yn=$([ "$auth_needed" == "true" ] && echo "y" || echo "n")
                local socks5_user=$(echo "$socks5_config" | jq -r '.username')
                local socks5_pass=$(echo "$socks5_config" | jq -r '.password')
                local udp_over_tcp=$(echo "$socks5_config" | jq -r '.udp_over_tcp')
                local udp_over_tcp_yn=$([ "$udp_over_tcp" == "true" ] && echo "y" || echo "n")
                
                set_port_socks5_config "$port" "y" "$socks5_address" "$socks5_port" "$auth_needed_yn" "$socks5_user" "$socks5_pass" "$udp_over_tcp_yn"
            fi
        fi
        
        # 保持HAProxy配置不变
        local haproxy_config=$(echo "$port_info" | jq -r '.haproxy')
        if [[ "$haproxy_config" != "null" ]]; then
            local haproxy_enabled=$(echo "$haproxy_config" | jq -r '.enabled // false')
            if [[ "$haproxy_enabled" == "true" ]]; then
                local haproxy_port=$(echo "$haproxy_config" | jq -r '.port')
                local haproxy_threads=$(echo "$haproxy_config" | jq -r '.threads')
                local haproxy_maxconn=$(echo "$haproxy_config" | jq -r '.maxconn')
                
                set_port_haproxy_config "$port" "y" "$haproxy_port" "$haproxy_threads" "$haproxy_maxconn"
            fi
        fi
        
        success "UUID修改成功!"
        log_info "修改端口 $port 的UUID: $old_uuid -> $new_uuid"
        break
    done
}


# 修改端口的域名
modify_port_domain() {
    local port=$1
    local port_info=$(get_port_info "$port")
    local old_domain=$(echo "$port_info" | jq -r '.domain')
    
    echo
    echo -e "$yellow 修改域名(SNI) $none"
    echo "----------------------------------------------------------------"
    echo -e "当前域名: $cyan$old_domain$none"
    
    echo -e "请输入新的域名作为SNI"
    read -p "$(echo -e "(例如: learn.microsoft.com): ")" new_domain
    [ -z "$new_domain" ] && new_domain="learn.microsoft.com"
    
    echo
    echo -e "$yellow 新域名 = ${cyan}$new_domain${none}"
    
    # 保存修改
    local uuid=$(echo "$port_info" | jq -r '.uuid')
    local private_key=$(echo "$port_info" | jq -r '.private_key')
    local public_key=$(echo "$port_info" | jq -r '.public_key')
    local shortid=$(echo "$port_info" | jq -r '.shortid')
    
    save_port_info "$port" "$uuid" "$private_key" "$public_key" "$shortid" "$new_domain"
    
    # 保持SOCKS5配置不变
    local socks5_config=$(echo "$port_info" | jq -r '.socks5')
    if [[ "$socks5_config" != "null" ]]; then
        local socks5_enabled=$(echo "$socks5_config" | jq -r '.enabled // false')
        if [[ "$socks5_enabled" == "true" ]]; then
            local socks5_address=$(echo "$socks5_config" | jq -r '.address')
            local socks5_port=$(echo "$socks5_config" | jq -r '.port')
            local auth_needed=$(echo "$socks5_config" | jq -r '.auth_needed')
            local auth_needed_yn=$([ "$auth_needed" == "true" ] && echo "y" || echo "n")
            local socks5_user=$(echo "$socks5_config" | jq -r '.username')
            local socks5_pass=$(echo "$socks5_config" | jq -r '.password')
            local udp_over_tcp=$(echo "$socks5_config" | jq -r '.udp_over_tcp')
            local udp_over_tcp_yn=$([ "$udp_over_tcp" == "true" ] && echo "y" || echo "n")
            
            set_port_socks5_config "$port" "y" "$socks5_address" "$socks5_port" "$auth_needed_yn" "$socks5_user" "$socks5_pass" "$udp_over_tcp_yn"
        fi
    fi

    # 保持HAProxy配置不变
    local haproxy_config=$(echo "$port_info" | jq -r '.haproxy')
    if [[ "$haproxy_config" != "null" ]]; then
        local haproxy_enabled=$(echo "$haproxy_config" | jq -r '.enabled // false')
        if [[ "$haproxy_enabled" == "true" ]]; then
            local haproxy_port=$(echo "$haproxy_config" | jq -r '.port')
            local haproxy_threads=$(echo "$haproxy_config" | jq -r '.threads')
            local haproxy_maxconn=$(echo "$haproxy_config" | jq -r '.maxconn')
            
            set_port_haproxy_config "$port" "y" "$haproxy_port" "$haproxy_threads" "$haproxy_maxconn"
        fi
    fi
    
    success "域名修改成功!"
    log_info "修改端口 $port 的域名: $old_domain -> $new_domain"
}

# 修改端口的ShortID
modify_port_shortid() {
    local port=$1
    local port_info=$(get_port_info "$port")
    local old_shortid=$(echo "$port_info" | jq -r '.shortid')
    local uuid=$(echo "$port_info" | jq -r '.uuid')
    
    echo
    echo -e "$yellow 修改ShortID $none"
    echo "----------------------------------------------------------------"
    echo -e "当前ShortID: $cyan$old_shortid$none"
    
    # 生成默认ShortID
    local default_shortid=$(echo -n ${uuid} | sha1sum | head -c 16)
    
    while :; do
        echo -e "请输入新的ShortID"
        read -p "$(echo -e "(默认ShortID: ${cyan}${default_shortid}${none}): ")" new_shortid
        [ -z "$new_shortid" ] && new_shortid=$default_shortid
        
        if [[ ${#new_shortid} -gt 16 ]]; then
            error
            continue
        elif [[ $(( ${#new_shortid} % 2 )) -ne 0 ]]; then
            error
            continue
        fi
        
        echo
        echo -e "$yellow 新ShortID = ${cyan}$new_shortid${none}"
        
        # 保存修改
        local private_key=$(echo "$port_info" | jq -r '.private_key')
        local public_key=$(echo "$port_info" | jq -r '.public_key')
        local domain=$(echo "$port_info" | jq -r '.domain')
        
        save_port_info "$port" "$uuid" "$private_key" "$public_key" "$new_shortid" "$domain"
        
        # 保持SOCKS5配置不变
        local socks5_config=$(echo "$port_info" | jq -r '.socks5')
        if [[ "$socks5_config" != "null" ]]; then
            local socks5_enabled=$(echo "$socks5_config" | jq -r '.enabled // false')
            if [[ "$socks5_enabled" == "true" ]]; then
                local socks5_address=$(echo "$socks5_config" | jq -r '.address')
                local socks5_port=$(echo "$socks5_config" | jq -r '.port')
                local auth_needed=$(echo "$socks5_config" | jq -r '.auth_needed')
                local auth_needed_yn=$([ "$auth_needed" == "true" ] && echo "y" || echo "n")
                local socks5_user=$(echo "$socks5_config" | jq -r '.username')
                local socks5_pass=$(echo "$socks5_config" | jq -r '.password')
                local udp_over_tcp=$(echo "$socks5_config" | jq -r '.udp_over_tcp')
                local udp_over_tcp_yn=$([ "$udp_over_tcp" == "true" ] && echo "y" || echo "n")
                
                set_port_socks5_config "$port" "y" "$socks5_address" "$socks5_port" "$auth_needed_yn" "$socks5_user" "$socks5_pass" "$udp_over_tcp_yn"
            fi
        fi

        # 保持HAProxy配置不变
        local haproxy_config=$(echo "$port_info" | jq -r '.haproxy')
        if [[ "$haproxy_config" != "null" ]]; then
            local haproxy_enabled=$(echo "$haproxy_config" | jq -r '.enabled // false')
            if [[ "$haproxy_enabled" == "true" ]]; then
                local haproxy_port=$(echo "$haproxy_config" | jq -r '.port')
                local haproxy_threads=$(echo "$haproxy_config" | jq -r '.threads')
                local haproxy_maxconn=$(echo "$haproxy_config" | jq -r '.maxconn')
                
                set_port_haproxy_config "$port" "y" "$haproxy_port" "$haproxy_threads" "$haproxy_maxconn"
            fi
        fi
        
        success "ShortID修改成功!"
        log_info "修改端口 $port 的ShortID: $old_shortid -> $new_shortid"
        break
    done
}



# 修改端口的SOCKS5代理设置
modify_port_socks5() {
    local port=$1
    local port_info=$(get_port_info "$port")
    local socks5_config=$(echo "$port_info" | jq -r '.socks5')
    
    echo
    echo -e "$yellow 修改SOCKS5代理设置 $none"
    echo "----------------------------------------------------------------"
    
    if [[ "$socks5_config" != "null" && "$(echo "$socks5_config" | jq -r '.enabled // false')" == "true" ]]; then
        echo -e "当前状态: ${green}已启用${none}"
        local socks5_address=$(echo "$socks5_config" | jq -r '.address')
        local socks5_port=$(echo "$socks5_config" | jq -r '.port')
        local auth_needed=$(echo "$socks5_config" | jq -r '.auth_needed')
        local socks5_user=$(echo "$socks5_config" | jq -r '.username')
        local socks5_pass=$(echo "$socks5_config" | jq -r '.password')
        local udp_over_tcp=$(echo "$socks5_config" | jq -r '.udp_over_tcp')
        
        echo -e "SOCKS5服务器: $cyan$socks5_address:$socks5_port$none"
        if [[ "$auth_needed" == "true" ]]; then
            echo -e "认证: ${green}启用${none} (用户名: $cyan$socks5_user$none)"
        else
            echo -e "认证: ${red}禁用${none}"
        fi
        
        if [[ "$udp_over_tcp" == "true" ]]; then
            echo -e "UDP over TCP: ${green}启用${none}"
        else
            echo -e "UDP over TCP: ${red}禁用${none}"
        fi
        
        echo
        echo -e "是否要${red}禁用${none} SOCKS5代理?"
        read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" disable_socks5
        
        if [[ "$disable_socks5" == "y" ]]; then
            # 禁用SOCKS5
            set_port_socks5_config "$port" "n" "" "" "" "" "" ""
            
            # 同时禁用对应的HAProxy配置
            local haproxy_config=$(echo "$port_info" | jq -r '.haproxy')
            if [[ "$haproxy_config" != "null" && "$(echo "$haproxy_config" | jq -r '.enabled // false')" == "true" ]]; then
                echo -e "${yellow}SOCKS5代理已禁用，同时禁用相关的HAProxy配置${none}"
                set_port_haproxy_config "$port" "n" "" "" ""
                update_haproxy_config
            fi
            
            success "SOCKS5代理已禁用!"
            log_info "禁用端口 $port 的SOCKS5代理"
        else
            # 修改SOCKS5设置
            echo
            local new_socks5_address=""
            
            # 循环直到获取有效的非本地地址
            while true; do
                echo -e "请输入新的SOCKS5服务器地址 (当前: $cyan$socks5_address$none)"
                read -p "$(echo -e "(留空保持不变): ")" input_address
                
                if [ -z "$input_address" ]; then
                    new_socks5_address=$socks5_address
                    # 如果用户保持当前地址且为本地地址，也给出警告
                    if [[ "$new_socks5_address" == "127.0.0.1" || "$new_socks5_address" == "localhost" ]]; then
                        echo -e "${red}错误: 不能使用本地地址 ($new_socks5_address)${none}"
                        echo -e "${yellow}请配置SOCKS5地址为公网IP或域名${none}"
                        continue
                    fi
                else
                    # 检查用户是否输入了本地地址
                    if [[ "$input_address" == "127.0.0.1" || "$input_address" == "localhost" ]]; then
                        echo -e "${red}错误: 不能将SOCKS5地址设置为本地地址 ($input_address)${none}"
                        echo -e "${yellow}请配置SOCKS5地址为公网IP或域名${none}"
                        continue
                    fi
                    new_socks5_address=$input_address
                fi
                break
            done
            
            echo -e "请输入新的SOCKS5端口 (当前: $cyan$socks5_port$none)"
            read -p "$(echo -e "(留空保持不变): ")" new_socks5_port
            [ -z "$new_socks5_port" ] && new_socks5_port=$socks5_port
            
            echo -e "是否需要用户名密码认证? (当前: $cyan$([ "$auth_needed" == "true" ] && echo "是" || echo "否")$none)"
            read -p "$(echo -e "(y/n, 默认: ${cyan}$([ "$auth_needed" == "true" ] && echo "y" || echo "n")${none}): ")" new_auth_needed
            [ -z "$new_auth_needed" ] && new_auth_needed=$([ "$auth_needed" == "true" ] && echo "y" || echo "n")
            
            new_socks5_user=$socks5_user
            new_socks5_pass=$socks5_pass
            if [[ "$new_auth_needed" == "y" ]]; then
                echo -e "请输入用户名 (当前: $cyan$socks5_user$none)"
                read -p "$(echo -e "(留空保持不变): ")" temp_user
                [ -n "$temp_user" ] && new_socks5_user=$temp_user
                
                echo -e "请输入密码 (当前: $cyan$socks5_pass$none)"
                read -p "$(echo -e "(留空保持不变): ")" temp_pass
                echo  # 为了换行
                [ -n "$temp_pass" ] && new_socks5_pass=$temp_pass
            fi
            
            echo -e "是否启用UDP over TCP? (当前: $cyan$([ "$udp_over_tcp" == "true" ] && echo "是" || echo "否")$none)"
            read -p "$(echo -e "(y/n, 默认: ${cyan}$([ "$udp_over_tcp" == "true" ] && echo "y" || echo "n")${none}): ")" new_udp_over_tcp
            [ -z "$new_udp_over_tcp" ] && new_udp_over_tcp=$([ "$udp_over_tcp" == "true" ] && echo "y" || echo "n")
            
            # 保存SOCKS5设置
            set_port_socks5_config "$port" "y" "$new_socks5_address" "$new_socks5_port" "$new_auth_needed" "$new_socks5_user" "$new_socks5_pass" "$new_udp_over_tcp"
            
            # 自动配置HAProxy
            echo -e "${yellow}正在为SOCKS5代理配置HAProxy...${none}"
            
            # 获取当前HAProxy配置
            local haproxy_config=$(echo "$port_info" | jq -r '.haproxy')
            local haproxy_enabled=$(echo "$haproxy_config" | jq -r '.enabled // false')
            local haproxy_port
            local haproxy_threads
            local haproxy_maxconn
            
            if [[ "$haproxy_enabled" == "true" ]]; then
                # 使用现有的HAProxy配置
                haproxy_port=$(echo "$haproxy_config" | jq -r '.port')
                haproxy_threads=$(echo "$haproxy_config" | jq -r '.threads')
                haproxy_maxconn=$(echo "$haproxy_config" | jq -r '.maxconn')
                
                # 检查端口是否被占用
                if lsof -i:"$haproxy_port" >/dev/null 2>&1 && ! systemctl is-active --quiet haproxy; then
                    echo -e "${yellow}端口 $haproxy_port 已被占用，自动选择新端口${none}"
                    haproxy_port=$((port + 10))
                    while lsof -i:"$haproxy_port" >/dev/null 2>&1; do
                        haproxy_port=$((haproxy_port + 1))
                    done
                fi
            else
                # 创建新的HAProxy配置，默认端口为VLESS端口+10
                haproxy_port=$((port + 10))
                while lsof -i:"$haproxy_port" >/dev/null 2>&1; do
                    echo -e "${yellow}端口 $haproxy_port 已被占用，自动选择下一个端口${none}"
                    haproxy_port=$((haproxy_port + 1))
                done
                haproxy_threads=12
                haproxy_maxconn=400
            fi
            
            # 保存HAProxy配置
            set_port_haproxy_config "$port" "y" "$haproxy_port" "$haproxy_threads" "$haproxy_maxconn"
            update_haproxy_config
            
            echo -e "${green}HAProxy已配置，端口: $haproxy_port, 线程数: $haproxy_threads, 最大连接数: $haproxy_maxconn${none}"
            
            success "SOCKS5代理设置已更新!"
            log_info "更新端口 $port 的SOCKS5代理设置"
        fi
    else
        echo -e "当前状态: ${red}未启用${none}"
        echo
        echo -e "是否要${green}启用${none} SOCKS5代理?"
        read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" enable_socks5
        
        if [[ "$enable_socks5" == "y" ]]; then
            # 调用 configure_socks5_for_port 函数，确保该函数也有检查本地地址的逻辑
            configure_socks5_for_port "$port"
        fi
    fi
    
    # 更新Xray配置
    update_config_file
}



# 修改端口的HAProxy设置
modify_port_haproxy() {
    local port=$1
    local port_info=$(get_port_info "$port")
    local haproxy_config=$(echo "$port_info" | jq -r '.haproxy')
    
    echo
    echo -e "$yellow 管理HAProxy设置 $none"
    echo "----------------------------------------------------------------"
    
    # 检查SOCKS5是否已配置
    local socks5_config=$(echo "$port_info" | jq -r '.socks5')
    if [[ "$socks5_config" == "null" || "$(echo "$socks5_config" | jq -r '.enabled // false')" != "true" ]]; then
        echo -e "${red}请先配置SOCKS5代理，HAProxy需要SOCKS5代理支持${none}"
        pause
        return
    fi
    
    # 检查SOCKS5地址是否为本地地址
    local socks5_address=$(echo "$socks5_config" | jq -r '.address')
    local socks5_port=$(echo "$socks5_config" | jq -r '.port')
    
    if [[ "$haproxy_config" != "null" && "$(echo "$haproxy_config" | jq -r '.enabled // false')" == "true" ]]; then
        local haproxy_port=$(echo "$haproxy_config" | jq -r '.port')
        local haproxy_threads=$(echo "$haproxy_config" | jq -r '.threads')
        local haproxy_maxconn=$(echo "$haproxy_config" | jq -r '.maxconn')
        
        echo -e "当前状态: ${green}已启用${none}"
        echo -e "HAProxy端口: $cyan$haproxy_port$none"
        echo -e "线程数: $cyan$haproxy_threads$none"
        echo -e "最大连接数: $cyan$haproxy_maxconn$none"
        
        echo
        echo -e "选择操作:"
        echo -e "  ${green}1.${none} 修改配置"
        echo -e "  ${green}2.${none} 返回"
        
        read -p "$(echo -e "请选择 [${green}1-2${none}]: ")" haproxy_action
        
        case $haproxy_action in
            1)
                # 修改配置
                echo -e "请输入新的HAProxy端口 (当前: $cyan$haproxy_port$none)"
                read -p "$(echo -e "(留空保持不变): ")" new_haproxy_port
                [ -z "$new_haproxy_port" ] && new_haproxy_port=$haproxy_port
                
                # 检查端口是否被占用（除了当前使用的端口）
                if [[ "$new_haproxy_port" != "$haproxy_port" ]] && lsof -i:"$new_haproxy_port" >/dev/null 2>&1; then
                    echo -e "${yellow}端口 $new_haproxy_port 已被占用，请指定其他端口${none}"
                    read -p "$(echo -e "请输入 HAProxy 端口: ")" new_haproxy_port
                    [ -z "$new_haproxy_port" ] && new_haproxy_port=$haproxy_port
                fi
                
                echo -e "请输入新的HAProxy线程数 (当前: $cyan$haproxy_threads$none)"
                read -p "$(echo -e "(留空保持不变): ")" new_haproxy_threads
                [ -z "$new_haproxy_threads" ] && new_haproxy_threads=$haproxy_threads
                
                echo -e "请输入新的HAProxy最大连接数 (当前: $cyan$haproxy_maxconn$none)"
                read -p "$(echo -e "(留空保持不变): ")" new_haproxy_maxconn
                [ -z "$new_haproxy_maxconn" ] && new_haproxy_maxconn=$haproxy_maxconn
                
                # 更新HAProxy配置
                set_port_haproxy_config "$port" "y" "$new_haproxy_port" "$new_haproxy_threads" "$new_haproxy_maxconn"
                update_haproxy_config
                
                success "HAProxy配置已更新!"
                log_info "更新端口 $port 的HAProxy配置"
                ;;
                
            2)
                return
                ;;
                
            *)
                error
                ;;
        esac
    else
        echo -e "当前状态: ${red}未启用${none}"
        
        # 检查SOCKS5地址是否为本地地址
        if [[ "$socks5_address" == "127.0.0.1" || "$socks5_address" == "localhost" ]]; then
            echo -e "${red}错误: SOCKS5代理使用了本地地址 ($socks5_address)${none}"
            echo -e "${yellow}本地地址不能用于HAProxy转发，请先修改SOCKS5代理配置为非本地地址${none}"
            echo -e "${yellow}请返回上级菜单，选择\"修改SOCKS5代理设置\"进行配置${none}"
            pause
            return
        fi
        
        echo
        echo -e "是否要${green}启用${none} HAProxy?"
        read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" enable_haproxy
        
        if [[ "$enable_haproxy" == "y" ]]; then
            # 默认HAProxy端口为VLESS端口+1
            local default_haproxy_port=$((port + 1))
            
            # 检查端口是否被占用
            while lsof -i:"$default_haproxy_port" >/dev/null 2>&1; do
                echo -e "${yellow}端口 $default_haproxy_port 已被占用，请指定其他端口${none}"
                read -p "$(echo -e "请输入 HAProxy 端口: ")" default_haproxy_port
                if [ -z "$default_haproxy_port" ] || ! [[ "$default_haproxy_port" =~ ^[0-9]+$ ]] || [[ "$default_haproxy_port" -lt 1 ]] || [[ "$default_haproxy_port" -gt 65535 ]]; then
                    error
                    default_haproxy_port=$((port + 1))
                    continue
                fi
            done
            
            # 设置HAProxy线程数
            read -p "$(echo -e "请输入 HAProxy 最大线程数 (默认: ${cyan}12${none}): ")" haproxy_threads
            [ -z "$haproxy_threads" ] && haproxy_threads=12
            
            # 设置HAProxy最大连接数
            read -p "$(echo -e "请输入 HAProxy 最大连接数 (默认: ${cyan}400${none}): ")" haproxy_maxconn
            [ -z "$haproxy_maxconn" ] && haproxy_maxconn=400
            
            # 保存HAProxy配置
            set_port_haproxy_config "$port" "y" "$default_haproxy_port" "$haproxy_threads" "$haproxy_maxconn"
            update_haproxy_config
            
            success "HAProxy配置已启用!"
            log_info "为端口 $port 启用HAProxy配置"
        fi
    fi
    
}



# 删除端口配置
delete_port_configuration() {
    echo
    echo -e "$yellow 删除端口配置 $none"
    echo "----------------------------------------------------------------"
    
    if [[ ! -s "$PORT_INFO_FILE" ]] || [[ $(jq '.ports | length' "$PORT_INFO_FILE") -eq 0 ]]; then
        echo -e "$red 目前没有配置任何端口，请先添加端口配置 $none"
        return
    fi
    
    # 显示所有端口
    list_port_configurations
    
    # 选择要删除的端口
    local port_count=$(jq '.ports | length' "$PORT_INFO_FILE")
    while :; do
        read -p "$(echo -e "请选择要删除的配置序号 [${green}1-$port_count${none}], 输入 0 取消: ")" port_index
        
        if [[ "$port_index" == "0" ]]; then
            echo -e "$yellow 操作已取消 $none"
            return
        fi
        
        if [[ -z "$port_index" ]] || ! [[ "$port_index" =~ ^[0-9]+$ ]] || [[ "$port_index" -lt 1 ]] || [[ "$port_index" -gt "$port_count" ]]; then
            error
            continue
        fi
        
        # 获取对应的端口信息
        local selected_port_info=$(jq -c ".ports[$(($port_index-1))]" "$PORT_INFO_FILE")
        local port=$(echo "$selected_port_info" | jq -r '.port')
        
        echo
        echo -e "$yellow 确认要删除端口 ${cyan}$port${none} 的配置吗? $none"
        read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" confirm_delete
        
        if [[ "$confirm_delete" == "y" ]]; then
            # 删除端口信息
            delete_port_info "$port"
            
            # 删除对应的连接信息文件
            local connection_file="$HOME/vless_reality_${port}.txt"
            if [[ -f "$connection_file" ]]; then
                rm -f "$connection_file"
                echo -e "$green 已删除端口 $port 的连接信息文件 $none"
            fi
            
            # 检查是否还有端口配置
            if [[ $(jq '.ports | length' "$PORT_INFO_FILE") -eq 0 ]]; then
                # 如果没有端口配置了，停止服务
                echo -e "$yellow 已删除所有端口配置，停止 Xray 和 HAProxy 服务 $none"
                
                # 停止 HAProxy 服务
                if systemctl is-active --quiet haproxy; then
                    systemctl stop haproxy
                    echo -e "$green HAProxy 服务已停止 $none"
                    log_info "所有端口删除后，HAProxy 服务已停止"
                fi
                
                # 停止 Xray 服务
                if systemctl is-active --quiet xray; then
                    systemctl stop xray
                    echo -e "$green Xray 服务已停止 $none"
                    log_info "所有端口删除后，Xray 服务已停止"
                fi
                
                # 删除配置文件
                if [[ -f "$CONFIG_FILE" ]]; then
                    mv "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
                    echo -e "$green Xray 配置文件已备份并删除 $none"
                    log_info "所有端口删除后，Xray 配置文件已备份"
                fi
                
                # 删除 HAProxy 配置文件
                if [[ -f "$HAPROXY_CONFIG" ]]; then
                    mv "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
                    echo -e "$green HAProxy 配置文件已备份并删除 $none"
                    log_info "所有端口删除后，HAProxy 配置文件已备份"
                fi
                
                echo -e "$green 所有服务和配置已清理 $none"
                log_info "所有端口删除后，服务和配置已清理"
            else
                # 还有其他端口配置，正常更新
                update_config_file
                update_haproxy_config
                
                # 重启 Xray
                echo
                echo -e "$yellow 重启 Xray 服务... $none"
                if systemctl restart xray; then
                    echo -e "$green Xray 服务重启成功! $none"
                    log_info "删除端口 $port 配置后重启 Xray 成功"
                else
                    echo -e "$red Xray 服务重启失败，请手动检查! $none"
                    log_error "删除端口 $port 配置后重启 Xray 失败"
                fi
            fi
            
            success "端口 $port 配置已删除!"
            log_info "端口 $port 配置已删除"
        else
            echo -e "$yellow 操作已取消 $none"
        fi
        
        break
    done
    
    pause
}

# 卸载 Xray 的函数
uninstall_xray() {
    echo
    echo -e "$yellow 卸载 Xray $none"
    echo "----------------------------------------------------------------"
    
    echo -e "${red}警告: 此操作将完全卸载 Xray 和 HAProxy 并删除所有配置信息!${none}"
    echo -e "${red}      所有端口配置和连接信息将被清除!${none}"
    echo
    
    read -p "$(echo -e "确认卸载? 输入 ${red}uninstall${none} 确认操作: ")" confirm
    
    if [[ "$confirm" != "uninstall" ]]; then
        echo -e "$yellow 操作已取消 $none"
        return
    fi
    
    # 停止并禁用HAProxy服务
    echo -e "$yellow 正在停止并禁用HAProxy服务... $none"
    if systemctl is-active --quiet haproxy; then
        systemctl stop haproxy
        systemctl disable haproxy
        echo -e "$green HAProxy服务已停止和禁用! $none"
    else
        echo -e "$yellow HAProxy服务未运行 $none"
    fi
    
    # 删除HAProxy配置文件
    if [[ -f "$HAPROXY_CONFIG" ]]; then
        rm -f "$HAPROXY_CONFIG"
        echo -e "$green HAProxy配置文件已删除 $none"
    fi
    
    # 卸载 Xray
    echo -e "$yellow 正在卸载 Xray... $none"
    
    # 使用官方脚本卸载
    if bash -c "$(curl -fL https://raw.githubusercontent.com/5548269/xray-reality-manager/main/install-release.sh
)" @ remove --purge; then
        echo -e "$green Xray 卸载成功! $none"
    else
        echo -e "$red Xray 卸载失败! 请检查错误信息 $none"
    fi
    
    # 删除配置信息文件
    if [[ -f "$PORT_INFO_FILE" ]]; then
        rm -f "$PORT_INFO_FILE"
        echo -e "$green 端口配置信息已删除 $none"
    fi
    
    # 删除连接信息文件(vless_reality开头的txt文件)
    rm -f "$HOME/vless_reality_"*.txt 2>/dev/null
    echo -e "$green 连接信息文件已删除 $none"
    
    # 删除日志文件
    if [[ -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE"
        echo -e "$green 日志文件已删除 $none"
    fi
    
    # 询问是否要卸载HAProxy软件包
    echo
    echo -e "$yellow 是否要卸载 HAProxy 软件包? $none"
    read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" uninstall_haproxy
    
    if [[ "$uninstall_haproxy" == "y" ]]; then
        echo -e "$yellow 正在卸载 HAProxy 软件包... $none"
        if apt -y remove haproxy && apt -y autoremove; then
            echo -e "$green HAProxy 软件包卸载成功! $none"
        else
            echo -e "$red HAProxy 软件包卸载失败! 请检查错误信息 $none"
        fi
    fi
    
    echo
    echo -e "$green Xray 和 HAProxy 已完全卸载! $none"
    log_info "Xray 和 HAProxy 已完全卸载"
    pause
    
    # 询问是否退出脚本
    read -p "$(echo -e "是否退出脚本? (y/n, 默认: ${cyan}y${none}): ")" exit_script
    [ -z "$exit_script" ] && exit_script="y"
    
    if [[ "$exit_script" == "y" ]]; then
        exit 0
    else
        show_menu
    fi
}

# 显示所有或特定端口的连接信息
show_all_connections() {
    echo
    echo -e "$yellow 端口连接信息 $none"
    echo "----------------------------------------------------------------"
    
    if [[ ! -s "$PORT_INFO_FILE" ]] || [[ $(jq '.ports | length' "$PORT_INFO_FILE") -eq 0 ]]; then
        echo -e "$red 目前没有配置任何端口，请先添加端口配置 $none"
        return
    fi
    
    # 获取本机IP
    if ! get_local_ips; then
        echo -e "${red}获取IP地址失败!${none}"
        return
    fi
    
    # 显示所有配置的端口列表
    echo -e "${cyan}序号   端口    UUID    域名${none}"
    echo "----------------------------------------------------------------"
    
    local index=1
    local ports=()
    
    jq -c '.ports[]' "$PORT_INFO_FILE" | while read -r port_info; do
        local port=$(echo "$port_info" | jq -r '.port')
        ports+=("$port")
        local uuid=$(echo "$port_info" | jq -r '.uuid')
        # 截取UUID的开头和结尾部分，中间用省略号
        local uuid_short="${uuid:0:8}...${uuid:24}"
        local domain=$(echo "$port_info" | jq -r '.domain')
        
        echo -e "${green}$index${none}    ${cyan}$port${none}    ${yellow}$uuid_short${none}    ${magenta}$domain${none}"
        index=$((index+1))
    done
    
    echo "----------------------------------------------------------------"
    
    # 提供选择显示方式的选项
    echo -e "请选择要显示的端口连接信息:"
    echo -e "  ${green}0.${none} 返回上级菜单"
    echo -e "  ${green}1.${none} 显示所有端口的连接信息"
    
    # 动态添加端口选项
    local port_count=$(jq '.ports | length' "$PORT_INFO_FILE")
    local display_index=2
    
    jq -c '.ports[]' "$PORT_INFO_FILE" | while read -r port_info; do
        local port=$(echo "$port_info" | jq -r '.port')
        echo -e "  ${green}$display_index.${none} 显示端口 ${cyan}$port${none} 的连接信息"
        display_index=$((display_index+1))
    done
    
    echo "----------------------------------------------------------------"
    
    while true; do
        read -p "$(echo -e "请选择 [${green}0-$((port_count+1))${none}]: ")" view_choice
        
        if [[ "$view_choice" == "0" ]]; then
            return
        elif [[ "$view_choice" == "1" ]]; then
            # 显示所有端口的连接信息
            echo
            echo -e "$yellow 显示所有端口的连接信息 $none"
            echo "----------------------------------------------------------------"
            
            # 根据当前网络环境选择IP
            local ip
            local netstack
            if [[ -n "$IPv4" ]]; then
                ip=$IPv4
                netstack=4
            elif [[ -n "$IPv6" ]]; then
                ip=$IPv6
                netstack=6
            fi
            
            jq -c '.ports[]' "$PORT_INFO_FILE" | while read -r port_info; do
                local port=$(echo "$port_info" | jq -r '.port')
                local uuid=$(echo "$port_info" | jq -r '.uuid')
                local public_key=$(echo "$port_info" | jq -r '.public_key')
                local shortid=$(echo "$port_info" | jq -r '.shortid')
                local domain=$(echo "$port_info" | jq -r '.domain')
                
                generate_connection_info "$port" "$uuid" "$public_key" "$shortid" "$domain" "$ip" "$netstack"
            done
            
            break
        elif [[ "$view_choice" -ge 2 ]] && [[ "$view_choice" -le $((port_count+1)) ]]; then
            # 显示特定端口的连接信息
            local selected_port_index=$((view_choice-2))
            local selected_port_info=$(jq -c ".ports[$selected_port_index]" "$PORT_INFO_FILE")
            local port=$(echo "$selected_port_info" | jq -r '.port')
            local uuid=$(echo "$selected_port_info" | jq -r '.uuid')
            local public_key=$(echo "$selected_port_info" | jq -r '.public_key')
            local shortid=$(echo "$selected_port_info" | jq -r '.shortid')
            local domain=$(echo "$selected_port_info" | jq -r '.domain')
            
            # 根据当前网络环境选择IP
            local ip
            local netstack
            if [[ -n "$IPv4" ]]; then
                ip=$IPv4
                netstack=4
            elif [[ -n "$IPv6" ]]; then
                ip=$IPv6
                netstack=6
            fi
            
            # 显示该端口的连接信息
            echo
            echo -e "$yellow 显示端口 ${cyan}$port${none} 的连接信息 $none"
            echo "----------------------------------------------------------------"
            generate_connection_info "$port" "$uuid" "$public_key" "$shortid" "$domain" "$ip" "$netstack"
            break
        else
            error
        fi
    done
    
    pause
}


# 格式化字节大小
format_bytes() {
    local bytes=$1
    local suffix=("B" "KB" "MB" "GB" "TB")
    local i=0
    local value=$bytes
    
    while (( value > 1024 && i < 4 )); do
        value=$(echo "scale=2; $value / 1024" | bc)
        ((i++))
    done
    
    echo "$value ${suffix[$i]}"
}




# 显示使用帮助信息
show_help() {
    echo
    echo -e "$yellow Xray 多端口管理脚本使用帮助 $none"
    echo "----------------------------------------------------------------"
    echo -e "  ${green}1.${none} 安装/重装 Xray: 安装或重新安装 Xray，并初始化配置。"
    echo -e "  ${green}2.${none} 添加新端口配置: 添加新的 VLESS Reality 端口，并可选配置 SOCKS5 代理。"
    echo -e "  ${green}3.${none} 查看所有端口配置: 显示当前配置的所有端口信息。"
    echo -e "  ${green}4.${none} 修改端口配置: 修改现有端口的 UUID、域名、ShortID 或 SOCKS5 代理设置。"
    echo -e "  ${green}5.${none} 删除端口配置: 删除指定端口的配置。"
    echo -e "  ${green}6.${none} 显示所有端口连接信息: 生成并显示所有端口的详细连接信息。"
    echo -e "  ${green}7.${none} 更新 GeoIP 和 GeoSite 数据: 手动更新 Xray 的 GeoIP 和 GeoSite 数据库。"
    echo -e "  ${green}8.${none} 流量统计: 显示各端口的流量使用情况（需配置 Xray API）。"
    echo -e "  ${green}9.${none} 设置定时更新: 配置定时任务自动更新 GeoIP 和 GeoSite 数据。"
    echo -e "  ${green}10.${none} 备份与恢复: 备份当前配置或从备份恢复配置。"
    echo -e "  ${green}11.${none} 检查脚本更新: 检查并更新脚本到最新版本。"
    echo -e "  ${green}12.${none} 查看日志: 显示 Xray 运行日志。"
    echo -e "  ${green}0.${none} 退出: 退出脚本。"
    echo "----------------------------------------------------------------"
    echo -e "当前版本: ${cyan}$VERSION${none}"
    echo -e "Bug 反馈: ${cyan}https://github.com/your-username/xray-multi-port/issues${none}"
    echo "----------------------------------------------------------------"
    
    pause
}

# 查看Xray日志
view_xray_logs() {
    echo
    echo -e "$yellow 查看 Xray 日志 $none"
    echo "----------------------------------------------------------------"
    
    echo -e "请选择要查看的日志:"
    echo -e "  ${green}1.${none} 访问日志 (access.log)"
    echo -e "  ${green}2.${none} 错误日志 (error.log)"
    echo -e "  ${green}3.${none} 返回"
    
    read -p "$(echo -e "请选择 [${green}1-3${none}]: ")" log_choice
    
    case $log_choice in
        1)
            if [[ -f "/var/log/xray/access.log" ]]; then
                echo -e "${yellow}访问日志 (最后 100 行):${none}"
                echo "----------------------------------------------------------------"
                tail -n 100 /var/log/xray/access.log
            else
                echo -e "${red}访问日志文件不存在${none}"
            fi
            ;;
            
        2)
            if [[ -f "/var/log/xray/error.log" ]]; then
                echo -e "${yellow}错误日志 (最后 100 行):${none}"
                echo "----------------------------------------------------------------"
                tail -n 100 /var/log/xray/error.log
            else
                echo -e "${red}错误日志文件不存在${none}"
            fi
            ;;
            
        3)
            return
            ;;
            
        *)
            error
            ;;
    esac
    
    pause
}



# 从Xray配置文件直接生成HAProxy配置，并更新端口信息文件
generate_haproxy_config_direct() {
    echo
    echo -e "$yellow 直接从Xray配置生成HAProxy配置 $none"
    echo "----------------------------------------------------------------"
    
    # 检查Xray配置文件是否存在
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${red}Xray配置文件不存在${none}"
        return 1
    fi
    
    # 检查HAProxy配置文件是否存在
    local haproxy_exists=false
    if [[ -f "$HAPROXY_CONFIG" ]]; then
        haproxy_exists=true
        echo -e "${green}检测到HAProxy配置文件${none}"
    else
        echo -e "${yellow}未检测到HAProxy配置文件，将创建新配置${none}"
    fi
    
    # 确保端口信息文件存在，如果不存在则创建
    if [[ ! -f "$PORT_INFO_FILE" ]]; then
        echo '{"ports":[]}' > "$PORT_INFO_FILE"
        chmod 600 "$PORT_INFO_FILE"
        echo -e "${green}创建了新的端口信息文件${none}"
    fi
    
    # 提取并保存所有inbound配置到端口信息文件
    echo -e "${yellow}正在从Xray配置中提取并更新端口信息...${none}"
    
    # 首先清空端口信息文件中的ports数组
    local reset_ports=$(jq '.ports = []' "$PORT_INFO_FILE")
    echo "$reset_ports" > "$PORT_INFO_FILE"
    
    # 使用临时文件来存储处理结果和状态标记
    local TEMP_FILE=$(mktemp)
    local HAS_SOCKS5_FILE=$(mktemp)
    local NEEDS_HAPROXY_FILE=$(mktemp)
    
    # 初始化状态文件
    echo "false" > "$HAS_SOCKS5_FILE"
    echo "false" > "$NEEDS_HAPROXY_FILE"
    
    # 遍历所有inbound并将结果写入临时文件
    jq -c '.inbounds[]' "$CONFIG_FILE" > "$TEMP_FILE"
    
    # 读取现有HAProxy配置，提取已配置的端口和IP
    local haproxy_configs=()
    if $haproxy_exists; then
        # 从HAProxy配置文件中提取前端和后端配置
        local current_frontend=""
        local current_backend=""
        local vless_port=""
        local haproxy_port=""
        local socks5_address=""
        local socks5_port=""
        
        while IFS= read -r line; do
            # 检测frontend部分
            if [[ "$line" =~ ^frontend\ socks_front_([0-9]+)$ ]]; then
                vless_port="${BASH_REMATCH[1]}"
                current_frontend="frontend"
                continue
            fi
            
            # 在frontend部分中读取端口
            if [[ "$current_frontend" == "frontend" && "$line" =~ bind\ \*:([0-9]+) ]]; then
                haproxy_port="${BASH_REMATCH[1]}"
                continue
            fi
            
            # 检测backend部分
            if [[ "$line" =~ ^backend\ socks_servers_([0-9]+)$ ]]; then
                vless_port="${BASH_REMATCH[1]}"
                current_frontend=""
                current_backend="backend"
                continue
            fi
            
            # 在backend部分中读取SOCKS5地址和端口
            if [[ "$current_backend" == "backend" && "$line" =~ server\ socks1\ ([^:]+):([0-9]+) ]]; then
                socks5_address="${BASH_REMATCH[1]}"
                socks5_port="${BASH_REMATCH[2]}"
                
                # 保存配置信息到数组
                if [[ -n "$vless_port" && -n "$haproxy_port" && -n "$socks5_address" && -n "$socks5_port" ]]; then
                    haproxy_configs+=("{\"vless_port\":$vless_port,\"haproxy_port\":$haproxy_port,\"socks5_address\":\"$socks5_address\",\"socks5_port\":$socks5_port}")
                    echo -e "${green}读取到HAProxy配置: VLESS端口=$vless_port, HAProxy端口=$haproxy_port, SOCKS5=$socks5_address:$socks5_port${none}"
                fi
                
                # 重置变量
                current_backend=""
                vless_port=""
                haproxy_port=""
                socks5_address=""
                socks5_port=""
            fi
        done < "$HAPROXY_CONFIG"
    fi
    
    # 读取临时文件进行处理
    while read -r inbound; do
        local port=$(echo "$inbound" | jq -r '.port')
        local protocol=$(echo "$inbound" | jq -r '.protocol')
        
        # 只处理VLESS+Reality协议
        if [[ "$protocol" == "vless" ]]; then
            local security=$(echo "$inbound" | jq -r '.streamSettings.security')
            
            if [[ "$security" == "reality" ]]; then
                local uuid=$(echo "$inbound" | jq -r '.settings.clients[0].id')
                local private_key=$(echo "$inbound" | jq -r '.streamSettings.realitySettings.privateKey')
                
                # 生成公钥（尝试使用xray命令）
                local tmp_key=$(echo -n ${private_key} | xargs xray x25519 -i 2>/dev/null || echo "Failed")
                local public_key
                if [[ "$tmp_key" == "Failed" ]]; then
                    public_key="auto_generated_public_key"
                else
                    public_key=$(echo ${tmp_key} | awk '{print $6}')
                fi
                
                local shortid=$(echo "$inbound" | jq -r '.streamSettings.realitySettings.shortIds[0]')
                local domain=$(echo "$inbound" | jq -r '.streamSettings.realitySettings.serverNames[0]')
                
                # 检查是否有关联的SOCKS5出站
                local tag=$(echo "$inbound" | jq -r '.tag')
                local socks5_tag=""
                
                # 查找与此inbound关联的SOCKS5出站
                for rule in $(jq -c '.routing.rules[]' "$CONFIG_FILE"); do
                    local inbound_tags=$(echo "$rule" | jq -r '.inboundTag[]? // empty')
                    if [[ "$inbound_tags" == *"$tag"* ]]; then
                        local outbound_tag=$(echo "$rule" | jq -r '.outboundTag')
                        if [[ "$outbound_tag" == *"socks5"* ]]; then
                            socks5_tag="$outbound_tag"
                            break
                        fi
                    fi
                done
                
                # 构建端口信息
                local port_info="{\"port\": $port, \"uuid\": \"$uuid\", \"private_key\": \"$private_key\", \"public_key\": \"$public_key\", \"shortid\": \"$shortid\", \"domain\": \"$domain\""
                
                # 如果有SOCKS5出站，添加SOCKS5信息
                if [[ -n "$socks5_tag" ]]; then
                    # 标记存在SOCKS5配置
                    echo "true" > "$HAS_SOCKS5_FILE"
                    
                    local socks5_config=$(jq -c --arg tag "$socks5_tag" '.outbounds[] | select(.tag == $tag)' "$CONFIG_FILE")
                    
                    # 获取SOCKS5服务器地址和端口
                    local socks5_address=$(echo "$socks5_config" | jq -r '.settings.servers[0].address')
                    local socks5_port=$(echo "$socks5_config" | jq -r '.settings.servers[0].port')
                    
                    # 检查是否需要认证以及用户名密码
                    local auth_needed="false"
                    local socks5_user=""
                    local socks5_pass=""
                    
                    # 检查SOCKS5配置中是否包含用户验证
                    if echo "$socks5_config" | jq -e '.settings.servers[0].users' > /dev/null; then
                        auth_needed="true"
                        socks5_user=$(echo "$socks5_config" | jq -r '.settings.servers[0].users[0].user // ""')
                        socks5_pass=$(echo "$socks5_config" | jq -r '.settings.servers[0].users[0].pass // ""')
                        
                        # 如果用户名或密码是占位符，提示用户输入
                        if [[ "$socks5_user" == "1" || -z "$socks5_user" || "$socks5_pass" == "1" || -z "$socks5_pass" ]]; then
                            echo -e "${yellow}检测到端口 $port 的SOCKS5认证信息不完整${none}"
                            while [[ -z "$socks5_user" || "$socks5_user" == "1" || -z "$socks5_pass" || "$socks5_pass" == "1" ]]; do
                                echo -e "请输入 SOCKS5 用户名:"
                                read -r -p "$(echo -e "> ")" new_socks5_user
                                echo -e "请输入 SOCKS5 密码（输入时不会显示）:"
                                read -r -s -p "$(echo -e "> ")" new_socks5_pass
                                echo

                                if [[ -n "$new_socks5_user" && -n "$new_socks5_pass" ]]; then
                                    socks5_user="$new_socks5_user"
                                    socks5_pass="$new_socks5_pass"
                                else
                                    echo -e "${red}用户名和密码均不能为空，请重新输入${none}"
                                fi
                            done
                        fi
                    fi
                    
                    # 检查是否启用了UDP over TCP
                    local udp_over_tcp="false"
                    if echo "$socks5_config" | jq -e '.streamSettings.sockopt.udpFragmentSize' > /dev/null; then
                        udp_over_tcp="true"
                    fi
                    
                    # 查找对应端口在HAProxy配置中的信息
                    local existing_haproxy_config=""
                    local haproxy_socks5_address=""
                    local haproxy_socks5_port=""
                    local current_haproxy_port=""
                    
                    for config in "${haproxy_configs[@]}"; do
                        local config_vless_port=$(echo "$config" | jq -r '.vless_port')
                        if [[ "$config_vless_port" == "$port" ]]; then
                            existing_haproxy_config="$config"
                            haproxy_socks5_address=$(echo "$config" | jq -r '.socks5_address')
                            haproxy_socks5_port=$(echo "$config" | jq -r '.socks5_port')
                            current_haproxy_port=$(echo "$config" | jq -r '.haproxy_port')
                            break
                        fi
                    done
                    
                    # 检查SOCKS5地址是否为本地地址
                    if [[ "$socks5_address" == "127.0.0.1" || "$socks5_address" == "localhost" ]]; then
                        echo -e "${yellow}检测到端口 $port 的SOCKS5地址为本地地址 ($socks5_address)${none}"
                        
                        if [[ -n "$existing_haproxy_config" ]]; then
                            # 已存在HAProxy配置
                            if [[ "$haproxy_socks5_address" == "127.0.0.1" || "$haproxy_socks5_address" == "localhost" ]]; then
                                # HAProxy配置也使用了本地地址
                                echo -e "${red}警告: 端口 $port 的HAProxy配置也使用了本地地址 ($haproxy_socks5_address)${none}"
                                echo -e "${yellow}本地地址不能用于HAProxy转发，请重新配置SOCKS5代理${none}"
                                
                                # 添加SOCKS5配置但不添加HAProxy配置
                                port_info="$port_info, \"socks5\": {\"enabled\": true, \"address\": \"$socks5_address\", \"port\": $socks5_port, \"auth_needed\": $auth_needed, \"username\": \"$socks5_user\", \"password\": \"$socks5_pass\", \"udp_over_tcp\": $udp_over_tcp}"
                                port_info="$port_info, \"haproxy\": null"
                            else
                                # HAProxy配置使用了非本地地址，保留现有HAProxy配置
                                echo -e "${green}注意: 端口 $port 的SOCKS5使用本地地址，但HAProxy配置使用非本地地址 ($haproxy_socks5_address:$haproxy_socks5_port)${none}"
                                echo -e "${yellow}保留现有HAProxy配置不变${none}"
                                
                                # 添加SOCKS5配置和保留现有HAProxy配置（使用HAProxy中的地址和端口，而不是Xray配置中的地址）
                                port_info="$port_info, \"socks5\": {\"enabled\": true, \"address\": \"$haproxy_socks5_address\", \"port\": $haproxy_socks5_port, \"auth_needed\": $auth_needed, \"username\": \"$socks5_user\", \"password\": \"$socks5_pass\", \"udp_over_tcp\": $udp_over_tcp}"
                                port_info="$port_info, \"haproxy\": {\"enabled\": true, \"port\": $current_haproxy_port, \"threads\": 12, \"maxconn\": 400}"
                                
                                # 标记需要配置HAProxy
                                echo "true" > "$NEEDS_HAPROXY_FILE"
                            fi
                        else
                            # 不存在HAProxy配置
                            echo -e "${yellow}本地地址不能用于HAProxy转发，不会创建HAProxy配置${none}"
                            
                            # 添加SOCKS5配置但不添加HAProxy配置
                            port_info="$port_info, \"socks5\": {\"enabled\": true, \"address\": \"$socks5_address\", \"port\": $socks5_port, \"auth_needed\": $auth_needed, \"username\": \"$socks5_user\", \"password\": \"$socks5_pass\", \"udp_over_tcp\": $udp_over_tcp}"
                            port_info="$port_info, \"haproxy\": null"
                        fi
                    else
                        # SOCKS5配置是非本地地址
                        # 检查对应端口是否在现有HAProxy配置中
                        if [[ -n "$existing_haproxy_config" ]]; then
                            # 使用现有HAProxy配置
                            echo -e "${green}使用现有HAProxy配置: 端口=$current_haproxy_port, SOCKS5=$haproxy_socks5_address:$haproxy_socks5_port${none}"
                            
                            # 添加SOCKS5配置和现有HAProxy配置
                            port_info="$port_info, \"socks5\": {\"enabled\": true, \"address\": \"$socks5_address\", \"port\": $socks5_port, \"auth_needed\": $auth_needed, \"username\": \"$socks5_user\", \"password\": \"$socks5_pass\", \"udp_over_tcp\": $udp_over_tcp}"
                            port_info="$port_info, \"haproxy\": {\"enabled\": true, \"port\": $current_haproxy_port, \"threads\": 12, \"maxconn\": 400}"
                        else
                            # 为HAProxy配置设置新端口（原来端口+1）
                            local haproxy_port=$((port + 1))
                            while lsof -i:"$haproxy_port" >/dev/null 2>&1; do
                                echo -e "${yellow}端口 $haproxy_port 已被占用，尝试下一个端口${none}"
                                haproxy_port=$((haproxy_port + 1))
                            done
                            echo -e "${green}为端口 $port 分配新的HAProxy端口: $haproxy_port${none}"
                            
                            # 添加SOCKS5配置和HAProxy配置到端口信息
                            port_info="$port_info, \"socks5\": {\"enabled\": true, \"address\": \"$socks5_address\", \"port\": $socks5_port, \"auth_needed\": $auth_needed, \"username\": \"$socks5_user\", \"password\": \"$socks5_pass\", \"udp_over_tcp\": $udp_over_tcp}"
                            port_info="$port_info, \"haproxy\": {\"enabled\": true, \"port\": $haproxy_port, \"threads\": 12, \"maxconn\": 400}"
                        fi
                        
                        # 标记需要配置HAProxy
                        echo "true" > "$NEEDS_HAPROXY_FILE"
                    fi
                else
                    # 不存在SOCKS5配置，添加空配置
                    port_info="$port_info, \"socks5\": null, \"haproxy\": null"
                fi
                
                # 结束端口信息JSON
                port_info="$port_info}"
                
                # 添加到端口信息文件
                local updated_ports=$(jq ".ports += [$(echo $port_info)]" "$PORT_INFO_FILE")
                echo "$updated_ports" > "$PORT_INFO_FILE"
                chmod 600 "$PORT_INFO_FILE"
                
                echo -e "${green}已添加端口 $port 的配置信息${none}"
            fi
        fi
    done < "$TEMP_FILE"
    
    # 读取状态标记
    local has_socks5=$(cat "$HAS_SOCKS5_FILE")
    local needs_haproxy=$(cat "$NEEDS_HAPROXY_FILE")
    
    # 清理临时文件
    rm -f "$TEMP_FILE" "$HAS_SOCKS5_FILE" "$NEEDS_HAPROXY_FILE"
    
    # 使用已有的update_config_file函数来更新Xray配置，确保配置一致性
    echo -e "${yellow}正在使用端口信息更新Xray配置文件...${none}"
    update_config_file
    
    # 检查是否需要更新HAProxy配置
    if [[ "$needs_haproxy" == "true" ]]; then
        echo -e "${yellow}检测到需要配置HAProxy的端口，正在更新HAProxy配置...${none}"
        update_haproxy_config
    else
        echo -e "${yellow}未检测到需要配置HAProxy的端口，跳过HAProxy配置更新${none}"
        
        # 只有当完全没有SOCKS5配置时，才询问是否关闭HAProxy
        if [[ "$has_socks5" == "false" ]] && [[ -f "$HAPROXY_CONFIG" ]] && systemctl is-active --quiet haproxy; then
            echo -e "${yellow}未检测到任何SOCKS5配置，是否停止HAProxy服务?${none}"
            read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" stop_haproxy
            
            if [[ "$stop_haproxy" == "y" ]]; then
                echo -e "${yellow}正在停止HAProxy服务...${none}"
                systemctl stop haproxy
                echo -e "${green}HAProxy服务已停止${none}"
            fi
        fi
    fi
    
    # 重启Xray服务
    echo -e "${yellow}正在重启Xray服务...${none}"
    if systemctl restart xray; then
        echo -e "${green}Xray服务已重启${none}"
    else
        echo -e "${red}Xray服务重启失败，请检查配置${none}"
    fi
    
    echo -e "${green}已完成配置同步和HAProxy配置生成!${none}"
    pause
    return 0
}



# 安装 Xray 的主函数
install_xray() {
    # 说明
    echo
    echo -e "$yellow 此脚本仅兼容于 Debian 10+ 系统. 如果你的系统不符合,请Ctrl+C退出脚本 $none"
    echo -e "脚本版本: ${cyan}$VERSION${none}"
    echo "----------------------------------------------------------------"

    # 安装依赖
    echo -e "${yellow}安装依赖...${none}"
    apt update
    apt install -y curl sudo jq net-tools lsof wget haproxy

    # 确保HAProxy服务启用
    systemctl enable haproxy

    # 检查是否已安装Xray
    if command -v xray &> /dev/null; then
        echo -e "${yellow}检测到已安装 Xray，是否重新安装?${none}"
        read -p "$(echo -e "(y/n, 默认: ${cyan}n${none}): ")" reinstall
        
        if [[ "$reinstall" != "y" ]]; then
            echo -e "${yellow}跳过安装 Xray${none}"
            return
        fi
    fi

    # Xray官方脚本安装最新版本
    echo
    echo -e "${yellow}Xray官方脚本安装最新版本$none"
    echo "----------------------------------------------------------------"
    bash -c "$(curl -fL https://raw.githubusercontent.com/5548269/xray-reality-manager/main/install-release.sh
)" @ install
    
    # 检查安装结果
    if ! command -v xray &> /dev/null; then
        echo -e "${red}Xray 安装失败，请检查网络连接或手动安装${none}"
        log_error "Xray 安装失败"
        return 1
    fi

    # 更新 geodata
    update_geodata

    # 打开BBR
    echo
    echo -e "$yellow打开BBR$none"
    echo "----------------------------------------------------------------"
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    
    # 确保配置目录存在
    init_directories
    
    # 提示用户添加端口
    echo
    echo -e "$green Xray 安装完成！$none"
    log_info "Xray 安装完成"

    # 优化TCP参数
    # optimize_tcp

    echo -e "$yellow 接下来您需要添加端口配置 $none"
    pause
    
    # 添加第一个端口配置
    add_port_configuration
}

# 主菜单
show_menu() {
    local keep_running=true
    
    while $keep_running; do
        echo
        echo "---------- Xray 多端口管理脚本 V${VERSION} -------------"
        echo -e "  ${green}1.${none} 安装/重装 Xray"
        echo -e "  ${green}2.${none} 添加新端口配置"
        echo -e "  ${green}3.${none} 查看所有端口配置"
        echo -e "  ${green}4.${none} 修改端口配置"
        echo -e "  ${green}5.${none} 删除端口配置"
        echo -e "  ${green}6.${none} 显示所有端口连接信息"
        echo -e "  ${green}7.${none} 更新 GeoIP 和 GeoSite 数据"
        echo -e "  ${green}8.${none} 备份与恢复"
        echo -e "  ${green}9.${none} 查看 Xray 日志"
        echo -e "  ${green}10.${none} 帮助信息"
        echo -e "  ${green}11.${none} 卸载 Xray"
        echo -e "  ${green}12.${none} 根据当前Xray配置信息生成HAProxy配置（会同时修改当前xray配置）"
        echo -e "  ${green}0.${none} 退出"
        echo "------------------------------------"
        read -p "请选择 [0-12]: " choice

        case $choice in
            1)
                install_xray
                ;;
            2)
                add_port_configuration
                ;;
            3)
                list_port_configurations
                pause
                ;;
            4)
                modify_port_configuration
                ;;
            5)
                delete_port_configuration
                ;;
            6)
                show_all_connections
                ;;
            7)
                update_geodata
                ;;
            8)
                local return_to_main=false
                while ! $return_to_main; do
                    echo
                    echo -e "  ${green}1.${none} 备份配置"
                    echo -e "  ${green}2.${none} 恢复配置"
                    echo -e "  ${green}0.${none} 返回上级菜单"
                    read -p "请选择 [0-2]: " backup_choice
                    case $backup_choice in
                        1)
                            backup_configuration
                            ;;
                        2)
                            restore_configuration
                            ;;
                        0)
                            return_to_main=true
                            ;;
                        *)
                            error
                            ;;
                    esac
                done
                ;;
            9)
                view_xray_logs
                ;;
            10)
                show_help
                ;;
            11)
                uninstall_xray
                # 检查是否需要在卸载后退出
                if [[ $? -eq 0 ]]; then
                    local exit_after_uninstall
                    read -p "$(echo -e "是否退出脚本? (y/n, 默认: ${cyan}y${none}): ")" exit_after_uninstall
                    [ -z "$exit_after_uninstall" ] && exit_after_uninstall="y"
                    
                    if [[ "$exit_after_uninstall" == "y" ]]; then
                        keep_running=false
                    fi
                fi
                ;;
            12)
                generate_haproxy_config_direct
                ;;
            0)
                echo -e "${green}感谢使用 Xray 多端口管理脚本${none}"
                keep_running=false
                ;;
            *)
                error
                ;;
        esac
    done
    
    # 脚本结束
    exit 0
}

# 检查是否以root权限运行
check_root

# 初始化必要的目录和文件
init_directories

# 检查依赖
check_dependencies

# 记录脚本启动信息
log_info "脚本启动，版本 $VERSION"

# 如果没有带参数运行，显示菜单
if [ $# -eq 0 ]; then
    show_menu
else
    # 如果带参数运行，直接安装
    install_xray "$@"
fi
