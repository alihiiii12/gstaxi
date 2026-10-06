#!/bin/bash
cd /var/www/gstaxi/api
php -r '
require "vendor/autoload.php";
$app=require "bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$q=http_build_query([
  "User"=>config("services.mtn_sms.username"),
  "Pass"=>config("services.mtn_sms.password"),
  "From"=>config("services.mtn_sms.from"),
  "Gsm"=>"963938828814",
  "Msg"=>strtoupper(bin2hex(mb_convert_encoding("test","UCS-2BE","UTF-8"))),
  "Lang"=>0,
]);
file_put_contents("/tmp/mtn_q.txt", $q);
echo "qlen=".strlen($q)."\n";
'
Q=$(cat /tmp/mtn_q.txt)
echo "=== open ports summary (wifi Ghafir) ==="
echo "7443 = SMS API port (CLOSED)"
echo "443  = open but not SMS"
echo "8443 = open but not SMS"
for port in 8443 443; do
  echo "=== try ConcatenatedSender on :$port ==="
  curl -4 -k -sS --interface wlp131s0 --connect-timeout 10 --max-time 20 \
    -o "/tmp/b$port.txt" -w "http=%{http_code} time=%{time_total}\n" \
    -X POST -H "Content-Type: text/xml" --data-binary "" \
    "https://services.mtnsyr.com:${port}/general/MTNSERVICES/ConcatenatedSender.aspx?${Q}"
  echo -n "body: "; head -c 150 "/tmp/b$port.txt"; echo
done
