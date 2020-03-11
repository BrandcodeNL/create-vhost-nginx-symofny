#!/bin/bash

if [ "$(whoami)" != 'root' ]; then
	echo "You have no permission to run $0 as non-root user. Use sudo"
	exit 1;
fi

domain=$1
rootPath=$2
user=$3
password=$4
sitesEnable='/etc/nginx/sites-enabled/'
sitesAvailable='/etc/nginx/sites-available/'
serverRoot='/var/www/'


while [ "$domain" = "" ]
do
	echo "Please provide domain:"
	read domain
done

while [ "$user" = "" ]
do
	echo "Please provide a username:"
	read user
done

while [ "$password" = "" ]
do
	echo "Please provide a password:"
	read -s password
done

if [ -e $sitesAvailable$domain ]; then
	echo "This domain already exists.\nPlease Try Another one"
	exit;
fi


if [ "$rootPath" = "" ]; then
	rootPath=$serverRoot$domain
fi

if ! [ -d $rootPath ]; then
	mkdir $rootPath
	chmod 755 $rootPath
fi

exists=$(grep -c "^$user:" /etc/passwd)
if [ $exists -eq 0 ]; then
	echo "User does not exist, create one"
    adduser --home $rootPath $user
	echo -e "$password\n$password" | passwd $user
	ssh-keygen -t rsa -N "" -f $rootPath/.ssh/id_rsa
	echo "Add the following ssh key as an access key in the git repo:"
	cat $rootPath/.ssh/id_rsa.pub
fi

if ! [ -d $rootPath/shared ]; then
	echo "setting up shared directory"
	mdkir $rootPath/shared
	
fi

if ! [ -d $sitesEnable ]; then
	mkdir $sitesEnable
	chmod 777 $sitesEnable
fi

if ! [ -d $sitesAvailable ]; then
	mkdir $sitesAvailable
	chmod 777 $sitesAvailable
fi

configName=$domain.conf

if ! echo "server {
    server_name $domain;
    root /var/www/$domain/current/public;

    location / {
        # try to serve file directly, fallback to index.php
        try_files \$uri /index.php\$is_args\$args;
    }    

    location ~ ^/index\.php(/|$) {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_split_path_info ^(.+\.php)(/.*)\$;
        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;

        internal;
    }

    # return 404 for all other php files not matching the front controller
    # this prevents access to other php files you don't want to be accessible.
    location ~ \.php\$ {
        return 404;
    }

    error_log /var/log/nginx/$domain.log;
    access_log /var/log/nginx/$domain.log;
}" > $sitesAvailable$configName
then
	echo "There is an ERROR create $configName file"
	exit;
else
	echo "New Virtual Host Created"
fi

ln -s $sitesAvailable$configName $sitesEnable$configName

echo "Creating MySQL database..."
PASSWDDB="$(openssl rand -base64 12)"
MAINDB=${user//[^a-zA-Z0-9]/_}

echo "Please enter root user MySQL password!"
echo "Note: password will be hidden when typing"
read -s rootpasswd
mysql -uroot -p${rootpasswd} -e "CREATE DATABASE ${MAINDB} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
mysql -uroot -p${rootpasswd} -e "CREATE USER ${MAINDB}@localhost IDENTIFIED BY '${PASSWDDB}';"
mysql -uroot -p${rootpasswd} -e "GRANT ALL PRIVILEGES ON ${MAINDB}.* TO '${MAINDB}'@'localhost';"
mysql -uroot -p${rootpasswd} -e "FLUSH PRIVILEGES;"

echo "Database and user created database: $MAINDB user: $MAINDB password: $PASSWDDB"

if ! [ -f $rootPath/shared/.env.local ]; then
	touch $rootPath/shared/.env.local
fi
if ! echo "DATABASE_URL='mysql://$MAINDB:$PASSWDDB@localhost:3306/$MAINDB'" > $rootPath/shared/.env.local
then
	echo "ERROR: Not able to write in file $rootPath/shared/.env.local. Please check permissions."
	exit;
else
	echo "Added DB connection string to $rootPath/shared/.env.local"
fi    
chown $user:$user -R $rootPath

service nginx restart

echo "Complete! \n new Virtual Host created \nYour new host is: http://$domain \nAnd its located at $rootPath"
exit;