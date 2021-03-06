#!/bin/bash

YELLOW='\e[33m'
NC='\e[0m'
RED='\e[41m'

user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
	echo "This script must be run as the root user.  Please re-run it with sudo."
	exit 1
fi

cp .env.clean .env
cp jupyterhub_config.py.clean jupyterhub_config.py
cp Dockerfile.jupyterhub.clean Dockerfile.jupyterhub
cp docker-compose.yml.clean docker-compose.yml

echo -e "${YELLOW}This script was created to guide you in instantiating a one server, Docker-
based JupyterHub environment in support of data science classes being 
taught by the Biomedical Informatics department at the University of Utah.
It will setup and configure JupyterHub, the users' Jupyter/IPython 
notebook servers, MySQL, MongoDB, OrientDB CoreNLP, Nginx, and SSH servers

Let's begin!${NC}"

if [ ! -f /usr/bin/docker ]; then
	echo -e "\nDocker does not appear to be installed on this computer.  Would you like this script to install it on your behalf?"
	select yn in "Yes" "No"; do
		case $yn in
			Yes )	echo -e "\nNow installing Docker..."
				curl -fsSL get.docker.com -o get-docker.sh
				chmod u+x get-docker.sh && sh get-docker.sh
				success=$?
				if [ $success -ne 0 ]; then
					echo -e "\nThe Docker installation has failed.  Please check the output above for clues as to why.\nIf you wouldd like to install Docker manually, more information can be found here:\n\thttps://docs.docker.com/engine/installation/"
					exit 1
				else
					echo -e "\nDocker was successfully installed!"
				fi
				break;;
			No )	echo -e "\nDocker is required for this script to run.  Come back again if you change your mind.  Bye!"
				exit 1;;
			* )		echo -e "\nInvalid choice.  Please select one of the options above."
				continue;;
		esac
	done
fi

if [ ! -f /usr/local/bin/docker-compose ]; then
	echo -e "\nDocker Compose does not appear to be installed on this computer.  Would you like this script to install it on your behalf?"
	select yn in "Yes" "No"; do
		case $yn in
			Yes )	echo -e "\nNow installing Docker Compose..."
				sudo curl -L https://github.com/docker/compose/releases/download/1.17.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
				success=$?
				if [ $success -ne 0 ]; then
					echo -e "\nThe Docker Compose installation has failed.  Please check the output above for clues as to why.\nIf you wouldd like to install Docker Compose manually, more information can be found here:\n\thttps://docs.docker.com/compose/install/"
					exit 1
				else
					echo -e "\nDocker Compose was successfully installed!"
				fi
				break;;
			No )	echo -e "\nDocker Compose is required for this script to run.  Come back again if you change your mind.  Bye!"
				exit 1;;
			* )		echo -e "\nInvalid choice.  Please select one of the options above."
				continue;;
		esac
	done
fi

echo -e "\nLet's setup a few things for our JupyterHub server.  This script
was set up on the assumption that GitHub OAuth would be used as the 
authenticator.  You will first need to create an OAuth application within
your GitHub account (https://github.com/settings/applications/new).

Now that that's taken care of, tell me a bit about your application.

What is your GitHub ${YELLOW}Client ID${NC}? " 
read oauth_client_id
echo -e "What is your GitHub ${YELLOW}Client Secret${NC}? "
read oauth_client_secret
echo -e "What is your GitHub ${YELLOW}Callback URL${NC}? "
read oauth_callback

sed -i "s/GITHUB_CLIENT_ID=/GITHUB_CLIENT_ID=$oauth_client_id/" ./.env
sed -i "s/GITHUB_CLIENT_SECRET=/GITHUB_CLIENT_SECRET=$oauth_client_secret/" ./.env
sed -i "s@OAUTH_CALLBACK_URL=@OAUTH_CALLBACK_URL=$oauth_callback@" ./.env

if [ ! -d ./images/proxy/ssl ]; then
	mkdir ./images/proxy/ssl
fi

echo -e "\nAs JupyterHub will be listening on port 443 for TLS-encrypted connections, 
we will want to redirect all HTTP traffic to HTTPS.

What is the ${YELLOW}fully qualified domain name (FQDN)${NC} of this server?
It should match your GitHub callback url:  https://${YELLOW}<FQDN>${NC}/hub/oauth_callback"
read fqdn
cp ./nginx.conf.clean ./images/proxy/nginx.conf
sed -i "s/srv_name/$fqdn/g" ./images/proxy/nginx.conf

if [ ! -f ./images/proxy/ssl/server.key ] || [ ! -f ./images/proxy/ssl/server.crt ]; then
	echo -e "\nYou will need to have created a key/certificate pair in order to allow users to use JupyterHub securely.\n\nDo you:"

	select wherecert in "Have some already?" "Want to make a self-signed cert/key?" "Need to exit and have some made?"; do
	case $wherecert in
		"Have some already?" )
			COUNTER=0
			while [ $COUNTER -eq 0 ]; do
			echo -e "\nWhat is the path to the ${YELLOW}SSL key${NC}?"
			read -e sslkey
			if [ ! -f "$sslkey" ]; then
				echo -e "\n${RED}The path provided is invalid.${NC}"
			else
				cp $sslkey ./images/proxy/ssl/server.key
				let COUNTER=$COUNTER+1
			fi
			done
	
			COUNTER=0
			while [ $COUNTER -eq 0 ]; do
			echo -e "\nWhat is the path to the ${YELLOW}certificate${NC}?"
			read -e sslcert
			if [ ! -f "$sslcert" ]; then
				echo -e "\n${RED}The path provided is invalid.${NC}"
			else
				cp $sslcert ./images/proxy/ssl/server.crt
				let COUNTER=$COUNTER+1
			fi
			done
			break;;
		"Want to make a self-signed cert/key?" )
			openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ./images/proxy/ssl/server.key -out ./images/proxy/ssl/server.crt
			if [ ! -f ./images/proxy/ssl/server.key ] || [ ! -f ./images/proxy/ssl/server.crt ]; then
				echo -e "\nCertificate generation seems to have failed.  Please try creating your own key pair.  Exiting."
				exit 1
			fi
			break;;
		"Need to exit and have some made?" )	
			echo -e "\nOkey dokey.  See you soon."
			exit 1;;
		* )
			echo -e "\nInvalid choice.  Please select one of the options above."
			continue;;
	esac
	done
fi

if [ ! -f ./images/proxy/ssl/dhparam.pem ]; then
	echo -e "\n\nWe're now going to generate Diffie-Hellman parameters in order to improve SSL connection security through forward secrecy.  This can take a while.  Hold tight..."
	openssl dhparam -out ./images/proxy/ssl/dhparam.pem 4096
fi

echo -e "\nJupyterHub will require at least one user to administer usage of the system.

What is the ${YELLOW}GitHub username${NC} of the admin user?"
read jhubadmin

echo "$jhubadmin admin" > userlist

echo -e "\nDo you wish to include a custom logo file?"
select yn in "Yes" "No"; do
	case $yn in
		Yes )	COUNTER=0
			while [ $COUNTER -eq 0 ]; do
			echo -e "Please enter the path of the logo file."
			read -e logopath
			if [ ! -f "$logopath" ]; then
				echo -e "${RED}The path provided is invalid.${NC}"
			else
				cp $logopath ./
				logo_fname=$(echo $logopath | awk -F/ ' { print $NF }')
				sed -i "s@LOGO_PATH=@LOGO_PATH=./$logo_fname@" ./.env
				jhubpath=/srv/jupyterhub/$logo_fname
				sed -i "s@JUPYTERHUB_LOGO=@JUPYTERHUB_LOGO=$jhubpath@" ./.env
				echo "COPY ./$logo_fname $jhubpath" >> Dockerfile.jupyterhub
				sed -i 's/#c.JupyterHub.logo/c.JupyterHub.logo/' jupyterhub_config.py
				let COUNTER=$COUNTER+1
			fi
			done
			break;;
		No )	sed -i "s@LOGO_PATH=@@;s@JUPYTERHUB_LOGO=@@" ./.env
			sed -i "s@JUPYTERHUB_LOGO=@#JUPYTERHUB_LOGO@" ./docker-compose.yml
			break;;
		* )
			echo -e "\nInvalid choice.  Please select one of the options above."
			continue;;
	esac
done

echo -e "\nWe will now need to choose a password for the root user on the
database containers."

if [ -d /srv/jupyterhub/mysql/var ]; then
	echo -e "\n${RED}WARNING!${NC}  This script has detected that the volume directory (/srv/jupyterhub/mysql/var) exists.  This is probably from previously running this script.  When using the existing directory, you will not be able to specify a new MySQL root password.  If you have made no changes to the MySQL settings nor have added databases beyond the Mimic2 dataset this script downloads/installs, You may rename/delete the /srv/jupyterhub/mysql/var directory and this script will recreate it as it previously had.  If you have made changes to the my_mysql container in any way, I would be sure to input the same root password as previously used or exit this script and manually configure your container/compose settings."

	echo -e "\nHow would you like to handle the issue with ${YELLOW}/srv/jupyterhub/mysql/var${NC}?"
	select mysqlvar in "Delete and recreate" "Rename" "Continue with previous root password" "Abort and manually resolve"; do
		case $mysqlvar in
			"Delete and recreate" )	rm -rf /srv/jupyterhub/mysql/var
				mkdir /srv/jupyterhub/mysql/var
				break;;
			"Rename" )	mv /srv/jupyterhub/mysql/var /srv/jupyterhub/mysql/var.old.renamed
				break;;
			"Continue with previous root password" ) break;;
			"Abort and manually resolve" )	echo -e "\nOkay.  Good luck!"
				exit 1;;
			* )	echo -e "\nInvalid choice.  Please select one of the options above."
				continue;;
		esac
	done
fi

echo -e "\nWhat ${YELLOW}password${NC} should be used for the ${YELLOW}MySQL root user${NC}?"
read mysqlroot
sed -i "s/MYROOTPW=/MYROOTPW=$mysqlroot/" ./.env

echo -e "What ${YELLOW}password${NC} should be used for the ${YELLOW}OrientDB root user${NC}?"
read orientroot
sed -i "s/ORIENTROOTPW=/ORIENTROOTPW=$orientroot/" ./.env

echo -e "\nLastly, we will need the credentials to set up on the SSH server for
an unprivileged account.

What is the SSH user's ${YELLOW}username${NC}?"
read sshuser
echo -e "What is the SSH user's ${YELLOW}password${NC}?"
read sshpw

sed -i "s/SSHUSER=/SSHUSER=$sshuser/" ./.env
sed -i "s/SSHPW=/SSHPW=$sshpw/" ./.env

mkdir -p /srv/jupyterhub/{mysql,mongo,orientdb,DATA}
mkdir /srv/jupyterhub/mysql/{root,var}

docker network create jupyterhub-network
docker volume create --name jupyterhub-data

docker build -f ./images/jupyter/Dockerfile -t uujupyterhub_datascience-notebook .
docker-compose up -d


if [ ! -f /srv/jupyterhub/mysql/root/mimic2dead.sql ]; then 
	wget -O - https://physionet.org/mimic2/demo/mimic2dead.sql.gz | gunzip -c > /srv/jupyterhub/mysql/root/mimic2dead.sql
else
	sleep 10s
fi

docker exec -it my_mysql mysql -uroot -p$mysqlroot -e "grant select on mimic2.* to 'jovyan'@'%' identified by 'jovyan';" mimic2
echo -e "\n${YELLOW}Now importing Mimic2 dataset into MySQL container.  This will take a long time.  Bear with us.${NC}"
docker exec -it my_mysql mysql -uroot -p$mysqlroot -e "source /root/mimic2dead.sql" mimic2

docker commit $(docker ps | grep mysql | awk '{ print $1 }') uujupyterhub_mysql

docker stop my_mysql
docker rm my_mysql

sed -i 's@mysql:latest@uujupyterhub_mysql@' docker-compose.yml
docker-compose up -d

echo -e "\n${YELLOW}Installation of the JupyterHub environment is complete. You should now navigate your browser 
to the FQDN of the server, log in using your GitHub credentials, and test things out.  
Assuming everything looks good, you should not run this script again.  Instead 
start the containers by navigating to this directory and execute docker-compose up -d
to get everything running again should you need to reboot.${NC}"

exit
