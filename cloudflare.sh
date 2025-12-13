#!/bin/bash
getopts "iu" OPTS

if [[ $OPTS == u ]] ; then
  (sudo crontab -l 2>/dev/null | grep -v 'ddns.sh') | sudo crontab -
  sudo systemctl restart cron
  sudo rm /opt/ddns.sh
  echo "Cloudflare DDNS update service is uninstalled"
  exit 0
fi

curl -V &>/dev/null || DEP=1
dig -v &>/dev/null || DEP=1
jq -V &>/dev/null || DEP=1
[[ $DEP -eq 1 ]] && sudo apt update && sudo apt -y install curl dnsutils jq

echo ; read -p "Enter the Cloudflare API Zone ID: " ZONE_ID
echo ; read -p "Enter the Cloudflare API Token: " API_TOKEN
VARS=($(curl -s https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records -H "Authorization: Bearer $API_TOKEN" |\
  jq '.result[]|"\(.type) \(.id) \(.name) \(.content)"' | tr -d '"' | grep -e '^A '))
[ -z $VARS ] && echo -e "\nCould not retrieve DNS Records from Cloudflare." && exit 1
RECORD_ID=${VARS[1]}
DNS_NAME=${VARS[2]}
OLD_IP=${VARS[3]}
NEW_IP=$(dig @1.1.1.1 ch txt whoami.cloudflare +short | tr -d '"')

if [[ $OPTS == i ]] ; then
  sudo tee /opt/ddns.sh &>/dev/null <<EOF
#!/bin/bash
OLD_IP=$NEW_IP
NEW_IP=###(dig @1.1.1.1 ch txt whoami.cloudflare +short | tr -d '"')
[[ ###OLD_IP == ###NEW_IP ]] && exit 0
curl -s https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $API_TOKEN" -d '{
  "name": "$DNS_NAME",
  "ttl": 1,
  "type": "A",
  "comment": "Domain verification record",
  "content": "'"###NEW_IP"'",
  "proxied": false
}' | grep -q '"success":true'
[[ ###? -ne 0 ]] && exit 1
sed -i "s/^OLD_IP.*/OLD_IP=###NEW_IP/" /opt/ddns.sh
exit 0
EOF
  sudo sed -i 's/###/$/g' /opt/ddns.sh
  sudo chmod +x /opt/ddns.sh
  (sudo crontab -l 2>/dev/null | grep -v 'ddns.sh' ; echo "*/10 * * * * /opt/ddns.sh &>/dev/null") | sudo crontab -
  sudo systemctl restart cron
  echo "Cloudflare DDNS update service is installed"
fi

[[ $OLD_IP == $NEW_IP ]] && echo "No update needed" && exit 0
curl -s https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID -X PATCH -H 'Content-Type: application/json' -H "Authorization: Bearer $API_TOKEN" -d '{
  "name": "'"$DNS_NAME"'",
  "ttl": 1,
  "type": "A",
  "comment": "Domain verification record",
  "content": "'"$NEW_IP"'",
  "proxied": false
}' | grep -q '"success":true'
[[ $? -ne 0 ]] && echo "IP update unsuccessful" && exit 1
echo "IP updated to $NEW_IP"
exit 0
