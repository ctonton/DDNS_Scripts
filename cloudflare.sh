#!/bin/bash
getopts ":iu" OPT

# uninstall
if [[ $OPT == u ]] ; then
  (sudo crontab -l 2>/dev/null | grep -v 'ddns.sh') | sudo crontab -
  sudo systemctl restart cron
  sudo rm /opt/ddns.sh
  echo "Cloudflare DDNS update service is uninstalled"
  exit 0
fi

# dependencies
curl -V &>/dev/null && dig -v &>/dev/null && jq -V &>/dev/null
[[ $? -eq 0 ]] || (sudo apt update && sudo apt -y install curl dnsutils jq)
[[ $? -ne 0 ]] && echo "Failed to install dependencies" && exit 1

# variables
echo ; read -p "Enter the Cloudflare API Zone ID: " ZON
echo ; read -p "Enter the Cloudflare API Token: " TOK
NEW_4=$(dig @1.1.1.1 whoami.cloudflare txt ch -4 +short +tries=1 | sed '/;;/d;s/"//g')
NEW_6=$(dig @2606:4700:4700::1111 whoami.cloudflare txt ch -6 +short +tries=1 | sed '/;;/d;s/"//g')
[ -z $NEW_4 ] && [ -z $NEW_6 ] && echo "Could not detect any public IP address" && exit 1
REC_4=$(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H "Authorization: Bearer $TOK" | jq '.result[]|"\(.type) \(.id)"' 2>/dev/null | tr -d '"' | grep -e '^A ' | cut -d ' ' -f 2)
REC_6=$(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H "Authorization: Bearer $TOK" | jq '.result[]|"\(.type) \(.id)"' 2>/dev/null | tr -d '"' | grep -e '^AAAA ' | cut -d ' ' -f 2)

# setup
[ ! -z $REC_4 ] && curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_4 -X DELETE -H "Authorization: Bearer $TOK" &>/dev/null
[ ! -z $REC_6 ] && curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_6 -X DELETE -H "Authorization: Bearer $TOK" &>/dev/null
if [ -z $NEW_4 ] ; then
  echo "No public IPv4 address found so DDNS will be disabled for IPv4"
else
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "@",
    "ttl": 1,
    "type": "A",
    "comment": "Domain verification record",
    "content": "'"$NEW_4"'",
    "proxied": false
  }' | grep -q '"success":true' && echo "IPv4 successfully set to $NEW_4"
  ARY_4=($(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H "Authorization: Bearer $TOK" | jq '.result[]|"\(.type) \(.id) \(.name)"' 2>/dev/null | tr -d '"' | grep -e '^A '))
  REC_4=${ARY_4[1]}
  NAM_4=${ARY_4[2]}
fi
if [ -z $NEW_6 ] ; then
  echo "No public IPv6 address found so DDNS will be disabled for IPv6"
else
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "@",
    "ttl": 1,
    "type": "AAAA",
    "comment": "Domain verification record",
    "content": "'"$NEW_6"'",
    "proxied": false
  }' | grep -q '"success":true' && echo "IPv6 successfully set to $NEW_6"
  ARY_6=($(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H "Authorization: Bearer $TOK" | jq '.result[]|"\(.type) \(.id) \(.name)"' 2>/dev/null | tr -d '"' | grep -e '^AAAA '))
  REC_6=${ARY_6[1]}
  NAM_6=${ARY_6[2]}
fi

# install
if [[ $OPT == i ]] ; then
  sudo tee /opt/ddns.sh &>/dev/null <<EOT
#!/bin/bash
TTR=$(($(date +%s) + 604800))
[[ ##(date +%s) -ge ##TTR ]] && RUN=1
EOT
  if [ ! -z $NEW_4 ] ; then
    sudo tee -a /opt/ddns.sh &>/dev/null <<EOT
OLD_4=$NEW_4
NEW_4=##(dig @1.1.1.1 whoami.cloudflare txt ch -4 +short +tries=1 | sed '/;;/d;s/"//g')
if [[ ##OLD_4 != ##NEW_4 || ##RUN == 1 ]] ; then
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_4 -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "$NAM_4",
    "ttl": 1,
    "type": "A",
    "comment": "Domain verification record",
    "content": "'"##NEW_4"'",
    "proxied": false
  }' | grep -q '"success":true'
  [[ ##? -eq 0 ]] && sed -i "s/^OLD_4.*/OLD_4=##NEW_4/;s/^TTR.*/TTR=##((##(date +%s) + 604800))/" ##0
fi
EOT
  fi
  if [ ! -z $NEW_6 ] ; then
    sudo tee -a /opt/ddns.sh &>/dev/null <<EOT
OLD_6=$NEW_6
NEW_6=##(dig @2606:4700:4700::1111 whoami.cloudflare txt ch -6 +short +tries=1 | sed '/;;/d;s/"//g')
if [[ ##OLD_6 != ##NEW_6 || ##RUN == 1 ]] ; then
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_6 -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "$NAM_6",
    "ttl": 1,
    "type": "AAAA",
    "comment": "Domain verification record",
    "content": "'"##NEW_6"'",
    "proxied": false
  }' | grep -q '"success":true'
  [[ ##? -eq 0 ]] && sed -i "s/^OLD_6.*/OLD_6=##NEW_6/;s/^TTR.*/TTR=##((##(date +%s) + 604800))/" ##0
fi
EOT
  fi
  echo "exit 0" | sudo tee -a /opt/ddns.sh &>/dev/null
  sudo sed -i 's/##/$/g' /opt/ddns.sh
  sudo chmod +x /opt/ddns.sh
  (sudo crontab -l 2>/dev/null | grep -v 'ddns.sh' ; echo "*/5 * * * * /opt/ddns.sh &>/dev/null") | sudo crontab -
  sudo systemctl restart cron
  echo "Cloudflare DDNS update service is installed"
fi
exit 0
