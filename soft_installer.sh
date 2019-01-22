#!/bin/bash
#set -x
set -e

if [ "$(id -u)" != "0" ]; then
    sudo "$0" "$@"
    exit $?
fi

function do-install {
    local packages=("$@")
    for package in "${packages[@]}"
    do
        echo "Installing $package"
        if ! apt install -y "$package" > /dev/null 2>&1; then
            echo "$package installation error"
            exit 1
        fi
    done
}

function do-addrepository {
    local repository=$1
    echo "Adding $repository"
    if ! add-apt-repository -y "$repository" > /dev/null 2>&1; then
        echo "$repository adding error"
    fi
}

function do-update {
    echo "Updating apt"
    if ! apt update > /dev/null 2>&1; then
        echo "Updating apt error"
        exit 1
    fi
}

function do-addkeyinput {
    if ! apt-key add - > /dev/null 2>&1; then
        echo "Adding key error"
        exit 1
    fi
}

function do-addkeyserver {
    local keyserver=$1
    local recv=$2
    if ! apt-key adv --keyserver "$keyserver" --recv "$recv" > /dev/null 2>&1; then
        echo "Adding key error"
        exit 1
    fi
}

#=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=
#Adding 3rd party repos

#chrome
echo -e "\nAdding repo for Chrome"
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | do-addkeyinput
do-addrepository "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main"

#php
echo -e "\nAdding repo for PHP"
do-addrepository ppa:ondrej/php


#stride
echo -e "\nAdding repo for Stride"
wget -q -O - https://packages.atlassian.com/api/gpg/key/public | do-addkeyinput
do-addrepository "deb https://packages.atlassian.com/debian/stride-apt-client xenial main"

#=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=
#Updating apt
echo -e '\n\n'
do-update

#=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=
#install & configure part

export DEBIAN_FRONTEND="noninteractive"

#configure user
echo -e '\n\n'
if ! id -u "mojam" > /dev/null 2>&1; then
    echo "Adding user"
    useradd -G sudo mojam > /dev/null 2>&1
fi


echo 'mojam:LOCAL ROOT' | chpasswd

#ufw
echo -e '\n\n'
echo "Enabling ufw"
yes | ufw enable > /dev/null 2>&1

#chrome
echo -e '\n\n'
do-install google-chrome-stable
xdg-mime default google-chrome.desktop text/html
xdg-mime default google-chrome.desktop x-scheme-handler/http
xdg-mime default google-chrome.desktop x-scheme-handler/https
xdg-mime default google-chrome.desktop x-scheme-handler/about

#openssh-server
echo -e '\n\n'
do-install openssh-server
ufw allow OpenSSH > /dev/null 2>&1

#PHP
echo -e '\n\n'
phpstuff=( php5.6 \
                  php5.6-bcmath \
                  php5.6-bz2 \
                  php5.6-cgi \
                  php5.6-cli \
                  php5.6-common \
                  php5.6-curl \
                  php5.6-dba \
                  php5.6-fpm \
                  php5.6-gd \
                  php5.6-geoip \
                  php5.6-gettext \
                  php5.6-gmp \
                  php5.6-json \
                  php5.6-intl \
                  php5.6-mbstring \
                  php5.6-mcrypt \
                  php5.6-mysql \
                  php5.6-opcache \
                  php5.6-readline \
                  php5.6-recode \
                  php5.6-soap \
                  php5.6-xml \
                  php5.6-xmlrpc \
                  php5.6-xsl \
                  php5.6-zip \
                  libapache2-mod-php5.6
	php7.0 \
                  php7.0-bcmath \
                  php7.0-bz2 \
                  php7.0-cgi \
                  php7.0-cli \
                  php7.0-common \
                  php7.0-curl \
                  php7.0-dba \
                  php7.0-fpm \
                  php7.0-gd \
                  php7.0-geoip \
                  php7.0-gettext \
                  php7.0-gmp \
                  php7.0-json \
                  php7.0-intl \
                  php7.0-mbstring \
                  php7.0-mcrypt \
                  php7.0-mysql \
                  php7.0-opcache \
                  php7.0-readline \
                  php7.0-recode \
                  php7.0-soap \
                  php7.0-xml \
                  php7.0-xmlrpc \
                  php7.0-xsl \
                  php7.0-zip \
                  libapache2-mod-php7.0
php-xdebug  )
do-install "${phpstuff[@]}"

#apache2
echo -e '\n\n'
do-install apache2
ufw allow in 'Apache Full' > /dev/null 2>&1
a2enmod rewrite -q
echo 'ServerName localhost' >> /etc/apache2/apache2.conf
cat <<'EOF' >> /etc/apache2/conf-available/security.conf
<Directory /var/www/> 
    AllowOverride All 
</Directory>
EOF




#mysql-server
echo -e '\n\n'
mysqlstuff=( mysql-server mysql-client )
#because in debconf-#set-selections password can`t be with spaces, #setting temporary password
#and after instalation #setting hardcoded
debconf-set-selections <<< 'mysql-server mysql-server/root_password password LOCAL_DB_ROOT_USER'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password LOCAL_DB_ROOT_USER'
do-install "${mysqlstuff[@]}"

if ! echo "SELECT COUNT(*) FROM mysql.user WHERE user = 'phpmyadmin';" | mysql -u root -p"LOCAL_DB_ROOT_USER" 2> /dev/null | grep 1 &> /dev/null; then
    echo "Creating database user phpmyadmin..."
    mysql -u root -p"LOCAL_DB_ROOT_USER" > /dev/null 2>&1 <<EOF
    CREATE USER 'phpmyadmin'@'localhost' IDENTIFIED BY 'phpmyadmin';
    GRANT ALL PRIVILEGES ON *.* TO 'phpmyadmin'@'localhost';
    FLUSH PRIVILEGES;
EOF
else
    echo "Database user already created. Continue ..."
    mysql -u root -p"LOCAL_DB_ROOT_USER" > /dev/null 2>&1  <<EOF
    SET PASSWORD FOR 'phpmyadmin'@'localhost' = 'phpmyadmin';
    GRANT ALL PRIVILEGES ON *.* TO 'phpmyadmin'@'localhost';
    FLUSH PRIVILEGES;
EOF
fi




#phpMyAdmin
echo -e '\n\n'
debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"  
debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
do-install phpmyadmin

phpenmod mcrypt
phpenmod mbstring

cat <<EOF > /etc/dbconfig-common/phpmyadmin.conf 
dbc_install='true'
dbc_upgrade='true'
dbc_remove='true'
dbc_dbtype='mysql'
dbc_dbuser='phpmyadmin'
dbc_dbpass='phpmyadmin'
dbc_dballow='localhost'
dbc_dbserver='localhost'
dbc_dbport=''
dbc_dbname='phpmyadmin'
dbc_dbadmin='phpmyadmin'
dbc_basepath=''
EOF

dpkg-reconfigure --frontend=noninteractive phpmyadmin > /dev/null 2>&1
systemctl restart apache2


#phpstorm
echo -e '\n\n'
echo "Installing phpstorm"
snap install phpstorm --classic > /dev/null 2>&1
cat <<EOF > /usr/share/applications/phpstorm.desktop
[Desktop Entry]
Name=Phpstorm
Comment=
GenericName=
Keywords=
Exec=/snap/phpstorm/current/bin/phpstorm.sh %f
Terminal=false
Type=Application
Icon=/snap/phpstorm/current/bin/phpstorm.png
Path=
Categories=Development;IDE;
NoDisplay=false
StartupWMClass=jetbrains-phpstorm
EOF


#composer
echo -e '\n\n'
echo "Installing composer"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" > /dev/null 2>&1
php -r "if (hash_file('SHA384', 'composer-setup.php') === '93b54496392c062774670ac18b134c3b3a95e5a5e5c8f1a9f115f203b75bf9a129d5daa8ba6a13e2cc8a1da0806388a8') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php > /dev/null 2>&1
php -r "unlink('composer-setup.php');" > /dev/null 2>&1


#filezilla
echo -e '\n\n'
do-install filezilla

#stride
echo -e '\n\n'
do-install stride

#thunderbird
echo -e '\n\n'
do-install thunderbird

echo -e '\n'
echo "Done!"
read -p "Press any key to continue... " -n1 -s
echo -e '\n'
exit 0
