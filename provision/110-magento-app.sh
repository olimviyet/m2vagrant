#!/bin/bash

# ------------------------------------- #
# Fast VM - Magento2                    #
#                                       #
# Author: zepgram                       #
# Git: https://github.com/zepgram/      #
# ------------------------------------- #

export DEBIAN_FRONTEND=noninteractive

echo '--- Magento installation sequence ---'

# Prepare directory
DIRECTORY_BUILD="/home/vagrant"
if [ "$PROJECT_MOUNT_PATH" == "app" ]; then
	DIRECTORY_BUILD="/tmp"
fi
PROJECT_BUILD="$DIRECTORY_BUILD/$PROJECT_NAME"

### -- Destructive/heavy start --- ###
rm -rf "$PROJECT_BUILD" &>/dev/null
chmod -R 777 /tmp
mkdir -p "$PROJECT_BUILD"
chown -fR vagrant:vagrant "$PROJECT_BUILD"

# Get installation files from source
if [ "$PROJECT_SOURCE" == "composer" ]; then
	echo 'Install using composer'
	sudo -u vagrant composer create-project --no-interaction --no-install --no-progress \
		--repository=https://repo.magento.com/ magento/project-"$PROJECT_EDITION"-edition="$PROJECT_VERSION" "$PROJECT_NAME" -d "$DIRECTORY_BUILD"
elif [ "$PROJECT_SOURCE" == "zip" ]; then
	echo 'Install using zip'
	sudo -u vagrant tar -zxvf extra/magento2ce.tar.gz
	sudo -u vagrant cp -r magento2/. $PROJECT_BUILD/
	rm -rf magento2/
else
	echo 'Install using git'
	sudo -u vagrant git clone "$PROJECT_REPOSITORY" "$PROJECT_BUILD"
	cd "$PROJECT_BUILD"
	sudo -u vagrant git fetch --all
	git checkout "$PROJECT_SOURCE" --force
	rm -f "$PROJECT_BUILD"/app/etc/config.php "$PROJECT_BUILD"/app/etc/env.php
fi

# Composer install
sudo -u vagrant COMPOSER_MEMORY_LIMIT=-1 composer install -d "$PROJECT_BUILD" --no-interaction
### -- Destructive/heavy end --- ###

# Rsync directory
if [ "$PROJECT_BUILD" != "$PROJECT_PATH" ]; then
	rsync -a --remove-source-files "$PROJECT_BUILD"/ "$PROJECT_PATH"/ || true
fi

# Copy auth.json for sample installation
if [ ! -f "$PROJECT_PATH/auth.json" ] && [ -f /home/vagrant/auth.json ]; then
	sudo -u vagrant cp /home/vagrant/auth.json "$PROJECT_PATH"/auth.json
fi

# Symlink
rm -rf /var/www/html/"$PROJECT_NAME"
ln -sfn "$PROJECT_PATH" /var/www/html/"$PROJECT_NAME"

# Apply basic rights on regular mount
chown -fR :www-data "$PROJECT_PATH"

# Run install
chmod +x "$PROJECT_PATH"/bin/magento

if [ -n "$PROJECT_CRYPT_KEY" ] && [ -f /home/vagrant/extra/db-dump.sql.gz ]; then
	echo 'Updating DB settings, when using prebuild composer project'
	if [ -f /home/vagrant/extra/create_quote_tbl.sql ]; then
		mysql -u root -ppassword magento </home/vagrant/extra/create_quote_tbl.sql
	fi
	sudo -u vagrant bin/magento setup:upgrade
else
	sudo -u vagrant "$PROJECT_PATH"/bin/magento setup:uninstall -n -q
	sudo -u vagrant "$PROJECT_PATH"/bin/magento setup:install \
		--base-url="http://${PROJECT_URL}/" \
		--base-url-secure="https://${PROJECT_URL}/" \
		--db-host="localhost" \
		--db-name="${PROJECT_NAME}" \
		--db-user="vagrant" \
		--db-password="vagrant" \
		--admin-firstname="magento.admin" \
		--admin-lastname="magento.admin" \
		--admin-email="${PROJECT_GIT_EMAIL}" \
		--admin-user="magento.admin" \
		--admin-password="admin123" \
		--language="${PROJECT_LANGUAGE}" \
		--currency="${PROJECT_CURRENCY}" \
		--timezone="${PROJECT_TIME_ZONE}" \
		--use-rewrites="1" \
		--backend-frontname="admin"
fi

# Install sample data
if [ "$PROJECT_SAMPLE" == "true" ]; then
	sudo -u vagrant php -d memory_limit=-1 "$PROJECT_PATH"/bin/magento sampledata:deploy
	sudo -u vagrant "$PROJECT_PATH"/bin/magento setup:upgrade
fi
