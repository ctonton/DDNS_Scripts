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
curl -V &>/dev/null && dig -v &>/dev/null
[[ $? -eq 0 ]] || (sudo apt update && sudo apt -y install curl dnsutils)
[[ $? -ne 0 ]] && echo "Failed to install dependencies." && exit 1

# variables
echo ; read -p "Enter the Token from Duck DNS: " TOK
echo ; read -p "Enter the domain name to update: " DOM
[[ $VER == 6 ]] || NEW_4=$(dig @1.1.1.1 whoami.cloudflare txt ch -4 +short +tries=1 | sed '/;;/d;s/"//g')
[[ $VER == 4 ]] || NEW_6=$(dig @2606:4700:4700::1111 whoami.cloudflare txt ch -6 +short +tries=1 | sed '/;;/d;s/"//g')
[[ -z $NEW_4 && -z $NEW_6 ]] && echo "No public IP address found." && exit 1

# setup
if [ -z $NEW_6 ] ; then
  [[ $VER == 4 ]] && echo "DDNS is disabled for IPv6." || echo "No public IPv6 address found. DDNS will be disabled for IPv6."
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=$NEW_4" | grep -q 'OK' && echo "IPv4 successfully set to $NEW_4."
  [[ $? != 0 ]] && echo "IP update was unsuccessful. Service will not be installed." && exit 1
fi
if [ -z $NEW_4 ] ; then
  [[ $VER == 6 ]] && echo "DDNS is disabled for IPv4." || echo "No public IPv4 address found. DDNS will be disabled for IPv4."
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ipv6=$NEW_6" | grep -q 'OK' && echo "IPv6 successfully set to $NEW_6."
  [[ $? != 0 ]] && echo "IP update was unsuccessful. Service will not be installed." && exit 1
fi
if [[ ! -z $NEW_4 && ! -z $NEW_6 ]] ; then
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=$NEW_4&ipv6=$NEW_6" | grep -q 'OK' && echo -e "IPv4 successfully set to $NEW_4./nIPv6 successfully set to $NEW_6."
  [[ $? != 0 ]] && echo "IP update was unsuccessful. Service will not be installed." && exit 1
fi
[[ $OPT == "?" ]] && exit 0

# install
sudo tee /opt/ddns.sh &>/dev/null <<EOT
#!/bin/bash
DOM=$DOM
TOK=$TOK
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
[ -z $NEW_6 ] && curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=$NEW_4" | grep -q 'OK'\
  && sed -i "s/^OLD_4.*/OLD_4=$NEW_4/;s/^TTR.*/TTR=$(($(date +%s) + 604800))/" $0 || exit 1
[ -z $NEW_4 ] && curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ipv6=$NEW_6" | grep -q 'OK'\
  && sed -i "s/^OLD_6.*/OLD_6=$NEW_6/;s/^TTR.*/TTR=$(($(date +%s) + 604800))/" $0 || exit 1
[[ ! -z $NEW_4 && ! -z $NEW_6 ]] && curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=$NEW_4&ipv6=$NEW_6" | grep -q 'OK'\
  && sed -i "s/^OLD_4.*/OLD_4=$NEW_4/;s/^OLD_6.*/OLD_6=$NEW_6/;s/^TTR.*/TTR=$(($(date +%s) + 604800))/" $0 || exit 1
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
