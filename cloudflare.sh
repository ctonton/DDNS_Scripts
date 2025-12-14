#!/bin/bash
getopts "iu" OPT

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
ARY_4=($(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H "Authorization: Bearer $TOK" |\
  jq '.result[]|"\(.type) \(.id) \(.name) \(.content)"' 2>/dev/null | tr -d '"' | grep -e '^A '))
if [ ! -z $ARY_4 ] ; then
  REC_4=${ARY_4[1]}
  NAM_4=${ARY_4[2]}
  OLD_4=${ARY_4[3]}
  NEW_4=$(dig @1.1.1.1 whoami.cloudflare txt ch -4 +short +tries=1 | sed '/;;/d;s/"//g')
fi
ARY_6=($(curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records -H "Authorization: Bearer $TOK" |\
  jq '.result[]|"\(.type) \(.id) \(.name) \(.content)"' 2>/dev/null | tr -d '"' | grep -e '^AAAA '))
if [ ! -z $ARY_6 ] ; then
  REC_6=${ARY_6[1]}
  NAM_6=${ARY_6[2]}
  OLD_6=${ARY_6[3]}
  NEW_6=$(dig @2606:4700:4700::1111 whoami.cloudflare txt ch -6 +short +tries=1 | sed '/;;/d;s/"//g')
fi
[ -z $ARY_4 ] && [ -z $ARY_6 ] && echo "Could not retrieve DNS Records from Cloudflare" && exit 1

# install
if [[ $OPT == i ]] ; then
  echo "#!/bin/bash" | sudo tee /opt/ddns.sh &>/dev/null
  if [ -z $ARY_4 ] ; then
    echo "DDNS update service will be disabled for IPv4"
  else
    sudo tee -a /opt/ddns.sh &>/dev/null <<EOT
OLD_4=$NEW_4
NEW_4=##(dig @1.1.1.1 whoami.cloudflare txt ch -4 +short +tries=1 | sed '/;;/d;s/"//g')
if [[ ##OLD_4 == ##NEW_4 ]] ; then
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_4 -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "$NAM_4",
    "ttl": 1,
    "type": "A",
    "comment": "Domain verification record",
    "content": "'"##NEW_4"'",
    "proxied": false
  }' | grep -q '"success":true'
  [[ ##? -eq 0 ]] && sed -i "s/^OLD_4.*/OLD_4=##NEW_4/" ##0
fi
EOT
  fi
  if [ -z $ARY_6 ] ; then
    echo "DDNS update service will be disabled for IPv6"
  else
    sudo tee -a /opt/ddns.sh &>/dev/null <<EOT
OLD_6=$NEW_6
NEW_6=##(dig @2606:4700:4700::1111 whoami.cloudflare txt ch -6 +short +tries=1 | sed '/;;/d;s/"//g')
if [[ ##OLD_6 != ##NEW_6 ]] ; then
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_6 -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "$NAM_6",
    "ttl": 1,
    "type": "AAAA",
    "comment": "Domain verification record",
    "content": "'"##NEW_6"'",
    "proxied": false
  }' | grep -q '"success":true'
  [[ ##? -eq 0 ]] && sed -i "s/^OLD_6.*/OLD_6=##NEW_6/" ##0
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

# update
if [ ! -z $ARY_4 ] && [ ! -z $NEW_4 ] ; then
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_4 -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "'"$NAM_4"'",
    "ttl": 1,
    "type": "A",
    "comment": "Domain verification record",
    "content": "'"$NEW_4"'",
    "proxied": false
  }' | grep -q '"success":true'
  [[ $? -eq 0 ]] && echo "IPv4 updated to $NEW_4" || echo "IPV4 update failed"
fi
if [ ! -z $ARY_6 ] && [ ! -z $NEW_6 ] ; then
  curl -s https://api.cloudflare.com/client/v4/zones/$ZON/dns_records/$REC_6 -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" -d '{
    "name": "'"$NAM_6"'",
    "ttl": 1,
    "type": "AAAA",
    "comment": "Domain verification record",
    "content": "'"$NEW_6"'",
    "proxied": false
  }' | grep -q '"success":true'
  [[ $? -eq 0 ]] && echo "IPv6 updated to $NEW_6" || echo "IPV6 update failed"
fi
exit 0
