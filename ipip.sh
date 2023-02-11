#!/bin/bash
red='\033[0;31m'
green='\033[0;32m'
White='\033[37m'
blue='\033[36m'
yellow='\033[0;33m'
plain='\033[0m'
echoType='echo -e'
DATE=`date +%Y%m%d`
install_ipip(){
	if [[ `lsmod|grep ipip` == "" ]]; then
	modprobe ipip
	fi
	if [[ `which dig` == "" ]]; then
		apt-get install dnsutils  -y>/dev/null ||yum  install dnsutils  -y >/dev/null 
	fi
	if [[ `which iptables` == "" ]]; then
		apt install iptables -y>/dev/null ||yum install iptables -y>/dev/null 
	fi
	echo -ne "请输入对段设备的ddns域名或者IP："
	read ddnsname
	read -p "请输入要创建的tun网卡名称：" tunname
	echo -ne "请输入tun网口的V-IP："
	read vip
	echo -ne "请输入对端的V-IP："
	read remotevip
	if [[ `dig ${ddnsname} @8.8.8.8| grep 'ANSWER SECTION'` == "" ]]; then
		remoteip=${ddnsname}
	else
		remoteip=$(dig ${ddnsname} @8.8.8.8 | awk -F "[ ]+" '/IN/{print $1}' | awk 'NR==2 {print $5}')
	fi
	localip=$(ip a |grep brd|grep global|awk '{print $2}'|awk -F "/" '{print $1}')
	echo "${remoteip}" >/root/.tunnel-ip.txt
	ip tunnel add $tunname mode ipip remote ${remoteip} local $localip ttl 64 # 创建IP隧道
	ip addr add ${vip}/30 dev $tunname # 添加本机VIP
	ip link set $tunname up # 启用隧道虚拟网卡
	ip route add ${remotevip}/32 dev $tunname scope link src ${vip}
	if [[ `iptables -t nat -L|grep "${remotevip}"` == "" ]]; then
		iptables -t nat -A POSTROUTING -s ${remotevip} -j MASQUERADE
	fi
	if [[ `sysctl -p|grep "net.ipv4.ip_forward = 1"` == "" ]]; then
		echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
		sysctl -p /etc/sysctl.conf
	fi
	cat >/root/change-tunnel-ip_${ddnsname}.sh <<EOF
#!/bin/bash
if [[ \`dig ${ddnsname} @8.8.8.8| grep 'ANSWER SECTION'\` == "" ]]; then
	remoteip="${ddnsname}"
else
	remoteip=\$(dig ${ddnsname} @8.8.8.8 | awk -F "[ ]+" '/IN/{print \$1}' | awk 'NR==2 {print \$5}')
fi
oldip="\$(cat /root/.tunnel-ip.txt)"
localip=$(ip a |grep brd|grep global|awk '{print $2}'|awk -F "/" '{print $1}')
if [[ \$oldip != \$remoteip ]]; then
	ip tunnel del $tunname >/dev/null &
	ip tunnel add $tunname mode ipip remote \${remoteip} local \${localip} ttl 64
	ip addr add ${vip}/30 dev $tunname
	ip link set $tunname up
fi
EOF
	echo "开始添加定时任务"
	bashsrc=$(which bash)
	crontab -l 2>/dev/null > /root/crontab_test 
	echo -e "*/2 * * * * ${bashsrc} /root/change-tunnel-ip_${ddnsname}.sh" >> /root/crontab_test 
	crontab /root/crontab_test 
	rm /root/crontab_test
	crontask=$(crontab -l)

	echo -------------------------------------------------------
	echo -e "设置定时任务成功，当前系统所有定时任务清单如下:\n${crontask}"
	echo -------------------------------------------------------
	echo "程序全部执行完毕，脚本退出。。"
	exit 0
}
install_wg(){
	apt-get update 
	apt-get install wireguard -y
	wg genkey | tee /etc/wireguard/privatekey | wg pubkey | tee /etc/wireguard/publickey
	read -p "请输入对端wg使用的V-ip地址:" revip
	read -p "请输入本机wg使用的v-ip地址:" localip1
	read -p "请输入ros端wg的公钥内容:" rospublickey
	read -p "请输入ros端wg调用的端口号:" wgport
	localprivatekey=$(cat /etc/wireguard/privatekey)
	allowedip=$(ip a|grep /30|awk '{print $2}'|awk -F "[ ./]" '{print $1"."$2"."$3}')
	allowedip1=$(echo $revip|awk -F "." '{print  $1"."$2"."$3}')
	echo "[Interface]
ListenPort = $wgport
Address = $localip1/24
PrivateKey = $localprivatekey

[Peer]
PublicKey = $rospublickey
AllowedIPs = $allowedip.0/24,$allowedip1.0/24
Endpoint = ${revip}:$wgport
PersistentKeepalive = 25" > /etc/wireguard/wg0.conf
	wg-quick up wg0
	vpspublickey=$(cat /etc/wireguard/publickey)
	vip=$(ip a|grep "scope global"|grep "/30"|awk '{print $2}'|awk -F "/" '{print $1}')
	linstenport=$(cat /etc/wireguard/wg0.conf|grep "ListenPort"|awk '{print $3}')
	echo "    "
	echo -e "${green}------------------------------------------------------------${plain}"
	echo -e  "${green}请在ros的wireguard选项卡里边的Peers里添加配置，具体填写如下信息：${plain}\nPublic key 填写：${yellow}${vpspublickey}${plain}\nEndpoint 填写：${yellow}${vip}${plain}\nEndpoint port 填写：${yellow}${linstenport}${plain}\nAllowed Address填写：${green}0.0.0.0/0\n祝使用愉快。${plain}"
}
copyright(){
    clear
    echo -e "
${green}###########################################################${plain}
${green}#                                                         #${plain}
${green}#       IPIP tunnel隧道、Wireguard一键部署脚本            #${plain}
${green}#               Power By:翔翎                             #${plain}
${green}#                                                         #${plain}
${green}###########################################################${plain}"
}

main(){
copyright
echo -e "
${red}0.${plain}  退出脚本
${green}———————————————————————————————————————————————————————————${plain}
${green}1.${plain}  一键部署IPIP隧道
${green}2.${plain}  一键部署wireguard
"
    echo -e "${yellow}请选择你要使用的功能${plain}"
    read -p "请输入数字 :" num   
    case "$num" in
        0)
            exit 0
            ;;
        1)
            install_ipip
            ;;
        2)
            install_wg
            ;;
        *)
    clear
    echo -e "${red}出现错误:请输入正确数字 ${plain}"
    sleep 2s
    copyright
    main
    ;;
  esac
}
main
