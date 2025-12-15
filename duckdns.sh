#!/bin/bash
getopts ":iu" OPT

# uninstall
if [[ $OPT == u ]] ; then
  (sudo crontab -l 2>/dev/null | grep -v 'ddns.sh') | sudo crontab -
  sudo systemctl restart cron
  sudo rm -f /opt/ddns.sh
  echo "DDNS update service is uninstalled"
  exit 0
fi

# dependencies
curl -V &>/dev/null && dig -v &>/dev/null
[[ $? -eq 0 ]] || (sudo apt update && sudo apt -y install curl dnsutils)
[[ $? -ne 0 ]] && echo "Failed to install dependencies" && exit 1

# variables
echo ; read -p "Enter the Token from Duck DNS: " TOK
echo ; read -p "Enter the domain name to update: " DOM
NEW_4=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | sed '/;;/d;s/"//g')
NEW_6=$(dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | sed '/;;/d;s/"//g')
[ -z $NEW_4 ] && [ -z $NEW_6 ] && echo "Could not detect any public IP address" && exit 1

# setup
if [ -z $NEW_4 ] ; then
  echo "No public IPv4 address found so DDNS will be disabled for IPv4"
else
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=$NEW_4" | grep -q 'OK' && echo "IPv4 successfully set to $NEW_4"
fi

if [ -z $NEW_6 ] ; then
  echo "No public IPv6 address found so DDNS will be disabled for IPv6"
else
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ipv6=$NEW_6" | grep -q 'OK' && echo "IPv6 successfully set to $NEW_6"
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
NEW_4=##(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | sed '/;;/d;s/"//g')
if [[ ##OLD_4 != ##NEW_4 || ##RUN == 1 ]] && [ ! -z ##NEW_4 ] ; then
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=##NEW_4" | grep -q 'OK'
  [[ ##? -eq 0 ]] && sed -i "s/^OLD_4.*/OLD_4=##NEW_4/;s/^TTR.*/TTR=##((##(date +%s) + 604800))/" ##0
fi
EOT
  fi
  if [ ! -z $NEW_6 ] ; then
    sudo tee -a /opt/ddns.sh &>/dev/null <<EOT
OLD_6=$NEW_6
NEW_6=##(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | sed '/;;/d;s/"//g')
if [[ ##OLD_6 != ##NEW_6 || ##RUN == 1 ]] && [ ! -z ##NEW_6 ] ; then
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=##NEW_6" | grep -q 'OK'
  [[ ##? -eq 0 ]] && sed -i "s/^OLD_6.*/OLD_6=##NEW_6/;s/^TTR.*/TTR=##((##(date +%s) + 604800))/" ##0
fi
EOT
  fi
  echo "exit 0" | sudo tee -a /opt/ddns.sh &>/dev/null
  sudo sed -i 's/##/$/g' /opt/ddns.sh
  sudo chmod +x /opt/ddns.sh
  (sudo crontab -l 2>/dev/null | grep -v 'ddns.sh' ; echo "*/5 * * * * /opt/ddns.sh &>/dev/null") | sudo crontab -
  sudo systemctl restart cron
  echo "DDNS update service is installed"
fi
exit 0
