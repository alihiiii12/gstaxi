#!/bin/bash
echo "sg www-data iface name:"
sg www-data -c 'curl -4 -sS --interface wlp131s0 --connect-timeout 8 --max-time 12 https://api.ipify.org' 2>&1; echo
echo "sg www-data bind IP:"
sg www-data -c 'curl -4 -sS --interface 192.168.1.132 --connect-timeout 8 --max-time 12 https://api.ipify.org' 2>&1; echo
echo "php curl bind:"
php -r '
$ch=curl_init("https://api.ipify.org");
curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>1,CURLOPT_INTERFACE=>"wlp131s0",CURLOPT_TIMEOUT=>12]);
$b=curl_exec($ch); echo "iface=".($b?:curl_error($ch))."\n";
$ch=curl_init("https://api.ipify.org");
curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>1,CURLOPT_INTERFACE=>"192.168.1.132",CURLOPT_TIMEOUT=>12]);
$b=curl_exec($ch); echo "ip=".($b?:curl_error($ch))."\n";
'
