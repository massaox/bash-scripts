echo "What web server would you like to install?"
echo " httpd or nginx?"
read WEBSERVER
echo "Type your domain"
read DOMAIN
echo "Okay, I will install $webserver and all packages necessary for the LAMP stack"

# installing all necessary packages
yum install ${WEBSERVER} php mod_ssl php-mysql mariadb-server mariab php-fpm -y

# Creates Document if does not already exist

if [ -d /var/www/vhosts/$DOMAIN/httpdocs ]
then
        echo "Document root already exists"
else
        mkdir -p /var/www/vhosts/$DOMAIN/httpdocs
fi

# Chooses between VHost or Server Block according to the choice of web server

case ${WEBSERVER}  in

httpd)

echo "<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot /var/www/vhosts/$DOMAIN/httpdocs/
    ProxyPassMatch ^/(.*\.php(/.*)?)$ unix:/var/run/raf.sock|fcgi://127.0.0.1:9000/var/www/vhosts/$DOMAIN/httpdocs/
    <Directory /var/www/vhosts/$DOMAIN/httpdocs>
        Options -Indexes +FollowSymLinks +MultiViews
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/$DOMAIN-error.log
    CustomLog /var/log/httpd//$DOMAIN-access.log combined

</VirtualHost>


#<VirtualHost *:443>
#    ServerName $DOMAIN
#       ServerAlias www.$DOMAIN
#    DocumentRoot /var/www/vhosts/$DOMAIN/httpdocs/
#    <Directory /var/www/vhosts/$DOMAIN/httpdocs>
#        Options -Indexes +FollowSymLinks +MultiViews
#        AllowOverride None
#        Require all granted
#    </Directory>
#    SSLCertificateFile      /etc/pki/tls/certs/$DOMAIN.crt
#    SSLCertificateKeyFile   /etc/pki/tls/private/$DOMAIN.key
#    ErrorLog /var/log/httpd/$DOMAIN-ssl-error.log
#    CustomLog /var/log/httpd/$DOMAIN-ssl-access.log combined
#</VirtualHost>" > /etc/httpd/conf.d/$DOMAIN.conf

if [ $(httpd -t &> /dev/null && echo $?) == 0 ]
then
systemctl start httpd
else
echo "Please check your Vhost configuration before starting Apache"
fi
;;

nginx)

echo "server {
    listen       80;
    server_name  $DOMAIN www.$DOMAIN;

    # note that these lines are originally from the "location /" block
    root   /var/www/vhosts/$DOMAIN/httpdocs/;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass unix:/var/run/php-fpm/raf.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}" > /etc/nginx/conf.d/$DOMAIN.conf

if [ $(httpd -t &> /dev/null && echo $?) == 0 ]
then
systemctl start httpd
else
echo "Please check your Vhost configuration before starting Apache"
fi
;;

*)
echo "This webserver is currently not supported"
;;
esac


# Setting up php-fpm using www.conf as template and using socket

cp -a /etc/php-fpm.d/www.conf /etc/php-fpm.d/$DOMAIN.conf;
sed -i 's%listen = 127.0.0.1:9000%listen = /var/run/test.sock%g' /etc/php-fpm.d/$DOMAIN.conf;
systemctl enable httpd php-fpm; systemctl start httpd php-fpm;
echo "<?php phpinfo() ?>" >> /var/www/vhosts/$DOMAIN/httpdocs/index.php;

# Going to MYSQL config now

SQLROOT=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

# Make sure that NOBODY can access the server without a password
mysql -e "UPDATE mysql.user SET Password = PASSWORD('${SQLROOT}') WHERE User = 'root'"
# Kill the anonymous users
mysql -e "DROP USER ''@'localhost'"
# Because our hostname varies we'll use some Bash magic here.
mysql -e "DROP USER ''@'$(hostname)'"
# Kill off the demo database
mysql -e "DROP DATABASE test"
# Make our changes take effect
mysql -e "FLUSH PRIVILEGES"
# Any subsequent tries to run queries this way will get access denied because lack of usr/pwd param

echo "[client]
username=root
password=${SQLROOT}" > /root/.my.cnf
chmod 600 /root/.my.cnf

