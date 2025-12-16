#!/bin/bash
getopts ":i:u" OPT
[[ $OPT == i ]] && VER=$OPTARG
[[ $VER == 4 || $VER == 6 || -z $VER ]]
[[ $? -ne 0 ]] && echo "Invalid argument for -i." && exit 1

# uninstall
if [[ $OPT == u ]] ; then
  (sudo crontab -l 2>/dev/null | grep -v 'ddns.sh') | sudo crontab -
  sudo systemctl restart cron
  sudo rm -f /opt/ddns.sh
  echo "DDNS update service is uninstalled."
  rm $0
  exit 0
fi

# dependencies
curl -V &>/dev/null && dig -v &>/dev/null && jq -V &>/dev/null
[[ $? -eq 0 ]] || (sudo apt update && sudo apt -y install curl dnsutils jq)
[[ $? -ne 0 ]] && echo "Failed to install dependencies." && exit 1

# variables
echo ; read -p "Enter the Cloudflare API Zone ID: " ZON
echo ; read -p "Enter the Cloudflare API Token: " TOK
[[ $VER == 6 ]] || NEW_4=$(dig @1.1.1.1 whoami.cloudflare txt ch -4 +short +tries=1 | sed '/;;/d;s/"//g')
[[ $VER == 4 ]] || NEW_6=$(dig @2606:4700:4700::1111 whoami.cloudflare txt ch -6 +short +tries=1 | sed '/;;/d;s/"//g')
[[ -z $NEW_4 && -z $NEW_6 ]] && echo "No public IP address found." && exit 1
REC_4=$(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records?type=A -H "Authorization: Bearer $TOK" | jq '.result[].id' 2>/dev/null | tr -d '"')
REC_6=$(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records?type=AAAA -H "Authorization: Bearer $TOK" | jq '.result[].id' 2>/dev/null | tr -d '"')

# setup
[ -z $REC_4 ] || curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_4 -X DELETE -H "Authorization: Bearer $TOK" &>/dev/null
[ -z $REC_6 ] || curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_6 -X DELETE -H "Authorization: Bearer $TOK" &>/dev/null
if [ -z $NEW_4 ] ; then
  [[ $VER == 6 ]] && echo "DDNS is disabled for IPv4." || echo "No public IPv4 address found. DDNS will be disabled for IPv4."
else
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "@",
    "ttl": 1,
    "type": "A",
    "comment": "Domain verification record",
    "content": "'"$NEW_4"'",
    "proxied": false
  }' | grep -q '"success":true' && echo "IPv4 successfully set to $NEW_4"
  [[ $? != 0 ]] && echo "IPv4 setup was unsuccessful. Service will not be installed." && exit 1
  REC_4=$(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records?type=A -H "Authorization: Bearer $TOK" | jq '.result[].id' 2>/dev/null | tr -d '"')
fi
if [ -z $NEW_6 ] ; then
  [[ $VER == 4 ]] && echo "DDNS is disabled for IPv6." || echo "No public IPv6 address found. DDNS will be disabled for IPv6."
else
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "@",
    "ttl": 1,
    "type": "AAAA",
    "comment": "Domain verification record",
    "content": "'"$NEW_6"'",
    "proxied": false
  }' | grep -q '"success":true' && echo "IPv6 successfully set to $NEW_6"
  [[ $? != 0 ]] && echo "IPv6 setup was unsuccessful. Service will not be installed." && exit 1
  REC_6=$(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records?type=AAAA -H "Authorization: Bearer $TOK" | jq '.result[].id' 2>/dev/null | tr -d '"')
fi
[[ $OPT == "?" ]] && exit 0

# install
sudo tee /opt/ddns.sh &>/dev/null <<EOT
#!/bin/bash
ZON=$ZON
TOK=$TOK
REC_4=$REC_4
REC_6=$REC_6
EOT
sudo tee -a /opt/ddns.sh &>/dev/null <<'EOF'
TTR=
OLD_4=
OLD_6=
NEW_4=$(dig @1.1.1.1 whoami.cloudflare txt ch -4 +short +tries=1 | sed '/;;/d;s/"//g')
NEW_6=$(dig @2606:4700:4700::1111 whoami.cloudflare txt ch -6 +short +tries=1 | sed '/;;/d;s/"//g')
[[ -z $NEW_4 && -z $NEW_6 ]] && exit 1
[[ $(date +%s) -ge $TTR ]] && RUN=1
[[ $OLD_4 == $NEW_4 && $OLD_6 == $NEW_6 && $RUN != 1 ]] && exit 0
[ ! -z $NEW_4 ] && [[ $OLD_4 != $NEW_4 || $RUN == 1 ]] && curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_4 \
  -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{ "content": "'"$NEW_4"'" }' |
  grep -q '"success":true' && sed -i "s/^OLD_4.*/OLD_4=$NEW_4/;s/^TTR.*/TTR=$(($(date +%s) + 604800))/" $0 || ERR=1
[ ! -z $NEW_6 ] && [[ $OLD_6 != $NEW_6 || $RUN == 1 ]] && curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_6 \
  -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{ "content": "'"$NEW_6"'" }' |
  grep -q '"success":true' && sed -i "s/^OLD_6.*/OLD_6=$NEW_6/;s/^TTR.*/TTR=$(($(date +%s) + 604800))/" $0 || ERR=1
[[ $ERR -eq 1 ]] && exit 1
exit 0
EOF
[ -z $NEW_4 ] && sudo sed -i 's/^NEW_4=.*/NEW_4=/' /opt/ddns.sh
[ -z $NEW_6 ] && sudo sed -i 's/^NEW_6=.*/NEW_6=/' /opt/ddns.sh
sudo chmod +x /opt/ddns.sh
(sudo crontab -l 2>/dev/null | grep -v 'ddns.sh' ; echo "*/5 * * * * /opt/ddns.sh &>/dev/null") | sudo crontab -
sudo systemctl restart cron
echo "DDNS update service is installed."
rm $0
exit 0
