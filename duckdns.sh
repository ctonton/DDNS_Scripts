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
NEW_4=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | tr -d '"')
NEW_6=$(dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | tr -d '"')

# setup
if [ -z $NEW_6 ] ; then
  echo "No public IPv6 address found so DDNS will be disabled for IPv6"
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=$NEW_4" | grep -q 'OK' && echo "IPv4 successfully set to $NEW_4"
else
  curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=$NEW_4&ipv6=$NEW_6" | grep -q 'OK' && echo -e "IPv4 successfully set to $NEW_4/nIPv6 successfully set to $NEW_6"
fi

# install
if [[ $OPT == i ]] ; then
  sudo tee /opt/ddns.sh &>/dev/null <<EOT
#!/bin/bash
TTR=$(($(date +%s) + 604800))
[[ ##(date +%s) -ge ##TTR ]] && RUN=1
OLD_4=$NEW_4
NEW_4=##(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | tr -d '"')
[ -z ##NEW_4 ] && exit 1
EOT
  if [ -z $NEW_6 ] ; then
    sudo tee -a /opt/ddns.sh &>/dev/null <<EOT
[[ ##OLD_4 == ##NEW_4 || ##RUN != 1 ]] && exit 0
curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=##NEW_4" | grep -q 'OK' || exit 1
sed -i "s/^OLD_4.*/OLD_4=##NEW_4/;s/^TTR.*/TTR=##((##(date +%s) + 604800))/" ##0
exit 0
EOT
  else
    sudo tee -a /opt/ddns.sh &>/dev/null <<EOT
OLD_6=$NEW_6
NEW_6=##(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | tr -d '"')
[ -z ##NEW_6 ] && exit 1
[[ ##OLD_4 == ##NEW_4 && ##OLD_6 == ##NEW_6 && ##RUN != 1 ]] && exit 0
curl -s "https://www.duckdns.org/update?domains=$DOM&token=$TOK&ip=##NEW_6" | grep -q 'OK' || exit 1
sed -i "s/^OLD_4.*/OLD_4=##NEW_4/;s/^OLD_6.*/OLD_6=##NEW_6/;s/^TTR.*/TTR=##((##(date +%s) + 604800))/" ##0
exit 0
EOT
  fi
  sudo sed -i 's/##/$/g' /opt/ddns.sh
  sudo chmod +x /opt/ddns.sh
  (sudo crontab -l 2>/dev/null | grep -v 'ddns.sh' ; echo "*/5 * * * * /opt/ddns.sh &>/dev/null") | sudo crontab -
  sudo systemctl restart cron
  echo "DDNS update service is installed"
fi
exit 0
