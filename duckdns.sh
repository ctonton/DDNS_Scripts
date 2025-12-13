#!/bin/bash
###
domain=your_domain_here
token=your_token_here
###
day0=
old4=
old6=
new4=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | tr -d '"')
new6=$(dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | tr -d '"')
[[ -z $new4 ]] && [[ -z $new6 ]] && exit 1
[[ -z $new4 ]] && new4=$old4
[[ -z $new6 ]] && new6=$old6
[[ $new4 == $old4 ]] && [[ $new6 == $old6 ]] && [[ $(date +%s) -lt $(( $day0 + 604800 )) ]] && exit 0
curl -k "https://www.duckdns.org/update?domains=$domain&token=$token&ip=$new4&ipv6=$new6" &>/dev/null || exit 1
sed -i "s/^old4.*/old4=$new4/;s/^old6.*/old6=$new6/;s/^day0.*/day0=$(date +%s)/" $0
exit 0
