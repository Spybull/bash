#!/usr/bin/env bash

usage(){
        echo -e "Usage: \n\t`basename $0` IPv4_address [--raw]"
        exit 1
}

BASE="/root/bin/"
iptables="/etc/sysconfig/iptables"
ipset="/etc/sysconfig/ipset"
RAWOUT=0

unknown=$(echo -e "$1" | tr -d '[:space:]')
if [ -z "$unknown" ]; then
	echo -e "No arguments!\n"
	usage
	exit 1
fi

if [ "$2" = "--raw" ]; then RAWOUT=1; fi

if [[ $unknown =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
    MAIN="$unknown"
else
    usage
    exit 2
fi

#Load rules
all_rules_iptables=$(cat $iptables | grep -v '^\#')
all_rules_ipset=$(cat $ipset)

rules_iptables=$(echo "$all_rules_iptables" | grep -w "$MAIN")
rules_ipset=$(echo "$all_rules_ipset" | grep -w "$MAIN")

source_rules=()
dest_rules=()

if [ -n "$rules_ipset" ]; then

    while IFS= read -r ipset_rules
    do
        ipset_name=$(echo "$ipset_rules" | awk '{print $2}')
        ipset_rules_bank=$(echo "$all_rules_iptables" | grep -w "$ipset_name")

        if [ -z "$ipset_rules_bank" ]; then
            echo "Warning: The set $ipset_name aren't using in iptables!"
            continue;
        fi
                        
        while IFS= read -r ipset_match
        do
            ipset_way=$(echo "$ipset_match" | grep -Eo 'match-set.+' | awk '{print $3}')
                
            if [ "$ipset_way" = "dst" ]; then
                src_ip=$(echo "$ipset_match" | grep -Po '\-s\s\K[0-9.]+')
                if [ "$src_ip" = "0.0.0.0/0" ]; then continue; fi
                source_rules+=($src_ip)
            else
                dst_ip=$(echo "$ipset_match" | grep -Po '\-d\s\K[0-9.]+')
                dport=$(echo "$ipset_match" | grep -Po 'dp.*' | grep -Po '[0-9,]+');
                if [ -z "$dport" ]; then dport="all"; fi
                if [ -z "$dst_ip" ]; then
                    dst_ip=$(echo "$ipset_match" | grep -Po 'dst-range\s+\K[0-9.-]+' | awk -F"-" '{print $1" "$2}')
                    for i in `prips $dst_ip`; do
                        dest_rules+=("${i}:${dport}")
                    done
                    continue
                fi
            dest_rules+=("${dst_ip}:${dport}")
        fi
        done < <(printf "%s\n", "$ipset_rules_bank")
    done < <(printf "%s\n", "$rules_ipset")
fi

if [ -n "$rules_iptables" ]; then

    while IFS= read -r iptables_rule
    do
        ipset_mb=$(echo "$iptables_rule" | grep -Eo 'match-set.+')

        if [ -n "$ipset_mb" ]; then
            ipset_name=$(echo "$ipset_mb" | awk '{print $2}')
            ipset_way=$(echo "$ipset_mb" | awk '{print $3}')
            ipset_ips=$(cat $ipset | grep -w "$ipset_name" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        
            while IFS= read -r ipset_rule
            do
                if [ "$ipset_way" = "dst" ]; then
                    dport=$(echo "$iptables_rule" | grep -Po 'dp.*' | grep -Po '[0-9,]+')
                    if [ -z "$dport" ]; then dport="all"; fi
                    dest_rules+=("${ipset_rule}:${dport}")
                else
                    source_rules+=($ipset_rule)
                fi
            done< <(printf "%s\n", "$ipset_ips")		
        fi	

        src_ip=$(echo "$iptables_rule" | grep -Po '\-s\s\K[0-9./]+')
        src_unmask=$(echo "$src_ip" | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

        if [ "$src_unmask" != "$MAIN" ]; then
            source_rules+=("$src_ip")
        else
            dst_ip=$(echo "$iptables_rule" | grep -Po '\-d\s\K[0-9./]+')
            dport=$(echo "$iptables_rule" | grep -Po 'dp.*' | grep -Po '[0-9,]+');
            if [ -z "$dport" ]; then dport="all"; fi

            if [ -z "$dst_ip" ]; then 
                dst_ip=$(echo "$iptables_rule" | grep -Po 'dst-range\s+\K[0-9.-]+' | awk -F"-" '{print $1" "$2}')
                if [ -z "$dst_ip" ]; then continue; fi
                for i in `prips $dst_ip`; do
                    dest_rules+=("${i}:${dport}")
                done
                continue
            fi
            dest_rules+=("${dst_ip}:${dport}")
        fi
    done< <(printf "%s\n", "$rules_iptables")
fi

if [ "${#dest_rules[@]}" -eq 0 ]; then
    echo "No destinations from $MAIN"
else
    echo -e "\nfrom $MAIN"
    for j in "${dest_rules[@]}"
    do
        tmp="$j"
        ip=$(echo $j | awk -F: '{print $1}')
        if [ -z "$ip" ]; then continue; fi
        DNS_NAME=$(nslookup "$ip" | grep -Po '=.\K.*.?' | awk 'NR==1{print}')
        if [ $RAWOUT -eq 0 ]; then 
            echo -e "\t -> $tmp \t($DNS_NAME)"
        else
            echo "$tmp" | awk -F':' '{print $1}'
        fi
    done
fi
if [ ${#source_rules[@]} -ne 0 ]; then
    echo "to $MAIN"
    for j in "${source_rules[@]}"
    do
        if [ -z "$j" ]; then continue; fi
        DNS_NAME=$(nslookup "$j" | grep -Po '=.\K.*.?' | awk 'NR==1{print}')
        if [ $RAWOUT -eq 0 ]; then 
            echo -e "\t -> $j \t($DNS_NAME)"
        else
            echo "$tmp" | awk -F':' '{print $1}'
        fi  
    done
fi
