#!/bin/bash

YELLOW='\e[33m'
NC='\e[0m'
RED='\e[41m'

cp .env.clean .env
cp jupyterhub_config.py.clean jupyterhub_config.py

echo -e "${YELLOW}This script was created to guide you in instantiating a one server, Docker-
based JupyterHub environment in support of data science classes being 
taught by the Biomedical Informatics department at the University of Utah.
It will setup and configure JupyterHub, the users' Jupyter/IPython 
notebook servers, MySQL, MongoDB, OrientDB CoreNLP, Nginx, and SSH servers

Let's begin!${NC}

First, let's setup a few things for our JupyterHub server.  This script
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

echo -e "\nYou'll need to have created a key/certificate pair in order to allow
users to use JupyterHub securely."

COUNTER=0
while [ $COUNTER -eq 0 ]; do
echo -e "\nWhat is the path to the ${YELLOW}SSL key${NC}?"
read -e sslkey
if [ ! -f "$sslkey" ]; then
	echo -e "\n${RED}The path provided is invalid.${NC}"
else
	cp $sslkey ./secrets/jupyterhub.key
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
	cp $sslcert ./secrets/jupyterhub.crt
	let COUNTER=$COUNTER+1
fi
done

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
				sed -i "s@LOGO_PATH=@LOGO_PATH=$logopath@" ./.env
				jhubpath=/srv/jupyterhub/$(echo $testing | awk -F/ '{ print $NF }')
				sed -i "s@JUPYTERHUB_LOGO=@JUPYTERHUB_LOGO=$jhubpath@" ./.env
				sed -i 's/#c.JupyterHub.logo/c.JupyterHub.logo/' jupyterhub_config.py
				let COUNTER=$COUNTER+1
			fi
			done
			break;;
		No )	break;;
	esac
done

echo -e "As JupyterHub will be listening on port 443 for TLS-encrypted connections, 
we will want to redirect all HTTP traffic to HTTPS.

What is the ${YELLOW}fully qualified domain name (FQDN)${NC} of this server?
It should match your GitHub callback url:  https://${YELLOW}<FQDN>${NC}/hub/oauth_callback"
read fqdn
cp default.clean ./images/nginx-redirect/default.conf
sed -i "s/#server_name/server_name\t$fqdn/" ./images/nginx-redirect/default.conf

echo -e "\nWe will now need to choose a password for the root user on the
database containers.

What ${YELLOW}password${NC} should be used for the ${YELLOW}MySQL root user${NC}?"
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
wget -O - https://physionet.org/mimic2/demo/mimic2dead.sql.gz | gunzip -c > /srv/jupyterhub/mysql/root/mimic2dead.sql


docker network create jupyterhub-network
docker volume create --name jupyterhub-data

docker build -f ./images/jupyter/Dockerfile -t markkeller/datascience-notebook .
docker-compose up -d

sleep 10s
docker exec -it mysql mysql -uroot -p$mysqlroot -e "grant select on mimic2.* to 'jovyan'@'%' identified by 'jovyan';" mimic2
docker exec -it mysql mysql -uroot -p$mysqlroot -e "source /root/mimic2dead.sql" mimic2

docker commit $(docker ps | grep mysql | awk '{ print $1 }') markkeller/mysql:mimic2
sed -i 's@mysql:latest@markkeller/mysql:mimic2@' docker-compose.yml

echo -e "${YELLOW}Installation of the JupyterHub environment is complete. You should now navigate your browser 
to the FQDN of the server, log in using your GitHub credentials, and test things out.  
Assuming everything looks good, you should not run this script again.  Instead 
start the containers by navigating to this directory and execute docker-compose up -d
to get everything running again should you need to reboot.
