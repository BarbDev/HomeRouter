#!/bin/bash

modprobe ifb
modprobe ipt_conntrack
modprobe br_netfilter
modprobe xt_ndpi
modprobe sch_cake
modprobe act_mirred
DOWNLINK=4000
UPLINK=600
WEBINT=enp1s0
####################################################################################
# Set up traffic shaping
# delete all old stuff first
tc qdisc del dev ${WEBINT} root #2> /dev/null > /dev/null
tc qdisc del dev ${WEBINT} ingress #2> /dev/null > /dev/null

###################################################################################################################
## downlink via ${WEBINT} ##
tc qdisc add dev ${WEBINT} handle ffff: ingress
tc qdisc del dev ifb0 root
tc qdisc add dev ifb0 root cake bandwidth 4000kbit
ip link set ifb0 up
tc filter add dev ${WEBINT} parent ffff: protocol all prio 10 u32 match u32 0 0 action mirred egress redirect dev ifb0
########################################## End of downlink configuration ##########################################

###################################################################################################################
## uplink via ${WEBINT} ##
tc qdisc add dev ${WEBINT} root cake bandwidth 600kbit
########################################### End of uplink configuration ###########################################

###################################################################################################################

# clear out existing setting
iptables -t mangle -F

# Paquets à destination du LAN, sans distinction
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -d 192.168.1.0/24 -j CLASSIFY --set-class 1:1000
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -d 192.168.1.0/24 -j RETURN
iptables -t mangle -A POSTROUTING -m physdev --physdev-in ${WEBINT} -s 192.168.1.0/24 -j CLASSIFY --set-class 1:1000
iptables -t mangle -A POSTROUTING -m physdev --physdev-in ${WEBINT} -s 192.168.1.0/24 -j RETURN

# Mark les sans mark ???
# Tout ce qui vient du WAN marqué à best effort (0) ??
# TODO: Pour l'instant on mark tout à besteffort par défault
iptables -t mangle -A POSTROUTING -j DSCP --set-dscp 0

#Sets high priority
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p icmp -j DSCP --set-dscp 46   # ICMP
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p icmp -j RETURN   # ICMP
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp --dport 22 -j DSCP --set-dscp 46   # SSH
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp --dport 22 -j RETURN   # SSH
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp --dport 993 -j DSCP --set-dscp 46   # IMAP
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp --dport 993 -j RETURN   # IMAP

# Mark traffic for shaping later
# The lower the MARK the higher the priority
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp --dport 80 -m physdev --physdev-out ${WEBINT} -j DSCP --set-dscp 18  # http
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp --dport 443 -m physdev --physdev-out ${WEBINT} -j DSCP --set-dscp 18 # https

# To speed up downloads while an upload is going on, put short ACK
# packets in the interactive class:
#iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK ACK -m length --length :64 -j MARK --set-mark 10
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp -m tcp --tcp-flags FIN,SYN,RST ACK -m length --length :64 -j DSCP --set-dscp 46
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp -m tcp --tcp-flags FIN,SYN,RST ACK -m length --length :64 -j RETURN

# Mark large downloads (> 500kb)
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m connbytes --connbytes 504857: --connbytes-dir both \
       --connbytes-mode bytes -j DSCP --set-dscp 8
#iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 -m connbytes --connbytes 504857: --connbytes-dir both \
#       --connbytes-mode bytes -j RETURN
# Voir si on ne réduit pas trop le dl

# Maj windows
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m ndpi --windows_update -j DSCP --set-dscp 8
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m ndpi --windows_update -j RETURN
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m ndpi --bittorrent -j DSCP --set-dscp 8
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m ndpi --bittorrent -j RETURN

iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m ndpi --twitch -j DSCP --set-dscp 26
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m ndpi --twitch -j RETURN
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m ndpi --youtube -j DSCP --set-dscp 32
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -m ndpi --youtube -j RETURN

# Mark udp packets for gaming
## GAME
### UDP IP: 192.168.1.73
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 --source 192.168.1.73 -m udp -p udp -j DSCP --set-dscp 32
#### blacklist 27000:27050 (Steam), 69 (tftp), 445 (microsoft SMB)
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 -m udp -p udp --dport 69 -j DSCP --set-dscp 8
#iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 -m udp -p udp --dport 69 -j RETURN
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 -m udp -p udp --dport 445 -j DSCP --set-dscp 8
#iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 -m udp -p udp --dport 445 -j RETURN
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 -m udp -p udp --dport 27000:27050 -j DSCP --set-dscp 8
#iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} ! -d 192.168.1.0/24 -m udp -p udp --dport 27000:27050 -j RETURN

# Look for p2p traffic and add to p2p ipset
# p2p traffic is detected using connlimit to look for multiple connections above port 1024
# - this is a sure sign of p2p acitivity!
# these users are then added to the ipset and then any traffic by the users on ports above
# 1024 is classed as p2p
#iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp -i ethX -m conntrack --ctstate INVALID -j DROP  # drop invalid connections
iptables -t mangle -A POSTROUTING -m physdev --physdev-out ${WEBINT} -p tcp --dport 1024: -m connlimit --connlimit-above 10 \
       -j DSCP --set-dscp 8 #  Detects traffic from Users using >5 ports above 1024 and adds the source address to the P2P list.
#iptables -t mangle -A FORWARD -o ethX -p tcp -m multiport --sport 1024:65535 -m set --set p2p dst \
#       -j MARK --set-mark 60 #  sets incoming traffic to known P2P users from Ports >1024 to lowest priority
#iptables -t mangle -A FORWARD -i ethX -p tcp -m multiport --dport 1024:65535 -m set --set p2p src \
#       -j MARK --set-mark 60 #  sets outgoing traffic from known P2P users to Ports >1024 to lowest priority

################################# End of uplink configuration #####################################################
