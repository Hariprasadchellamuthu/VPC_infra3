#!/bin/bash

# Web root directory where the HTML files will be served
WEB_ROOT="/var/www/html2"

# GitHub repository URL
GITHUB_REPO="https://github.com/Hariprasadchellamuthu/web_app_code.git"  # Replace with your GitHub repository URL

# Install Apache, php, php-mysql, mysql-client-core to serve web pages
sudo apt update
sudo apt install -y apache2 php
sudo apt-get install -y php-mysql
sudo apt install mysql-client-core-8.0
# Clone the GitHub repository to the web root directory
sudo git clone $GITHUB_REPO $WEB_ROOT
cd $WEB_ROOT
cp index.html /var/www/html
cp process.php /var/www/html

# Restart Apache to apply changes
sudo systemctl restart apache2

# Connecting to the RDS instance
mysql -h pridatabase.cubbgjg2ffrq.us-east-1.rds.amazonaws.com -u priuser -ppripassword -e "CREATE DATABASE pridatabase; USE pridatabase; CREATE TABLE user_data (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255), email VARCHAR(255));"

# Output the URL to access your web page
echo "Your web page is now available at: http://$(curl http://169.254.169.254/latest/meta-data/public-ipv4)"
