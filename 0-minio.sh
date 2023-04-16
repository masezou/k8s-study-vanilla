#!/usr/bin/env bash

#########################################################

MCLOGINUSER=miniologinuser
MCLOGINPASSWORD=miniologinuser
# If you want to use erasure coding, before running this script, please mount at least a disk (/dev/sdc1) to MINIOPATH with xfs.
MINIOPATH=/disk/minio
MINIOCONFIGPATH=/root/.minio/

#FORCE_LOCALIP=192.168.16.2
#FORCE_LOCALHOSTNAME=minio.example.corp

#########################################################

# Uninstall
#systemctl stop minio.service
#systemctl disable  minio.service
#rm -rf /usr/local/bin/minio /usr/local/bin/mc
#rm -rf /disk/minio/ /etc/systemd/system/minio.service /etc/default/minio /root/.mc

#########################################################
MINIOBINPATH=/usr/local/bin
MINIO_ROOT_USER=minioadminuser
MINIO_ROOT_PASSWORD=minioadminuser

### UID Check ###
if [ ${EUID:-${UID}} != 0 ]; then
	echo "This script must be run as root"
	exit 1
else
	echo "I am root user."
fi

### Distribution Check ###
UBUNTUVER=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d "=" -f2)
case ${UBUNTUVER} in
"20.04")
        echo -e "\e[32m${UBUNTUVER} is OK. \e[m"
        ;;
"22.04")
        echo "${UBUNTUVER} is OK.."
        #exit 255
        ;;
*)
        echo -e "\e[31m${UBUNTUVER} is NG. \e[m"
        exit 255
        ;;
esac
if [ ! -f /usr/share/doc/ubuntu-server/copyright ]; then
	echo -e "\e[31m It seemed his VM is installed Ubuntu Desktop media. VM which is installed from Ubuntu Desktop media is not supported. Please re-create VM from Ubuntu Server media! \e[m"
	exit 255
fi

### ARCH Check ###
PARCH=$(arch)
if [ ${PARCH} = aarch64 ]; then
	ARCH=arm64
	echo ${ARCH}
elif [ ${PARCH} = arm64 ]; then
	ARCH=arm64
	echo ${ARCH}
elif [ ${PARCH} = x86_64 ]; then
	ARCH=amd64
	echo ${ARCH}
else
	echo "${ARCH} platform is not supported"
	exit 1
fi

#### LOCALIP #########
if [ -z ${FORCE_LOCALIP} ]; then
	ip address show ens160 >/dev/null
	retval=$?
	if [ ${retval} -eq 0 ]; then
		LOCALIPADDR=$(ip -f inet -o addr show ens160 | cut -d\  -f 7 | cut -d/ -f 1)
	else
		ip address show ens192 >/dev/null
		retval2=$?
		if [ ${retval2} -eq 0 ]; then
			LOCALIPADDR=$(ip -f inet -o addr show ens192 | cut -d\  -f 7 | cut -d/ -f 1)
		else
			LOCALIPADDR=$(ip -f inet -o addr show eth0 | cut -d\  -f 7 | cut -d/ -f 1)
		fi
	fi
else
	LOCALIPADDR=${FORCE_LOCALIP}
fi
if [ -z ${LOCALIPADDR} ]; then
	echo -e "\e[31m Local IP address setting was failed, please set FORCE_LOCALIP and re-run.  \e[m"
	exit 255
else
	echo ${LOCALIPADDR}
fi

# SUDO Login
if [[ -z "${SUDO_USER}" ]]; then
	echo "You are root login."
else
	echo "You are sudo login."
fi
echo $SUDO_USER

# Just in case
apt update
apt -y upgrade
apt -y install wget
BASEPWD=$(pwd)

# Restart service automatically
if [ -f /etc/needrestart/needrestart.conf ]; then
	grep "{restart} = 'a'" /etc/needrestart/needrestart.conf
	retvalneedrestart=$?
	if [ ${retvalneedrestart} -ne 0 ]; then
		cat <<'EOF' >>/etc/needrestart/needrestart.conf
$nrconf{restart} = 'a';
EOF
	fi
fi
#########################################################

if [ ! -f ${MINIOBINPATH}/minio ]; then
	echo "Downloading minio server."
	#curl --retry 10 --retry-delay 3 --retry-connrefused -SOL https://dl.min.io/server/minio/release/linux-${ARCH}/minio
	wget https://dl.min.io/server/minio/release/linux-${ARCH}/minio
	mv minio ${MINIOBINPATH}
	chmod +x ${MINIOBINPATH}/minio
fi

if [ ! -f /usr/local/bin/mc ]; then
	echo "Downloading minio clent."
	#curl --retry 10 --retry-delay 3 --retry-connrefused -SOL https://dl.min.io/client/mc/release/linux-${ARCH}/mc
	wget https://dl.min.io/client/mc/release/linux-${ARCH}/mc
	mv mc /usr/local/bin/
	chmod +x /usr/local/bin/mc
	echo "complete -C /usr/local/bin/mc mc" >/etc/bash_completion.d/mc.sh
	mc update
else
	mc update
fi

# Create minio data directory
if [ ! -d ${MINIOPATH} ]; then
	#mkdir -p ${MINIOPATH}/data{1..4}
	mkdir -p ${MINIOPATH}/data
fi
chmod -R 755 ${MINIOPATH}/data*

# Create certificate
if [ ! -f ${MINIOCONFIGPATH}/certs/public.crt ]; then
	mkdir -p ${MINIOCONFIGPATH}/certs/CAs
	cd ${MINIOCONFIGPATH}/certs/
	if [ -z ${FORCE_LOCALHOSTNAME} ]; then
		LOCALHOSTNAME=$(hostname)
	else
		LOCALHOSTNAME=${FORCE_LOCALHOSTNAME}
	fi
	openssl genrsa -out rootCA.key 4096
	openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1825 -out rootCA.pem -subj "/C=JP/ST=Tokyo/L=Shibuya/O=cloudshift.corp/OU=development/CN=exmaple CA"
	openssl genrsa -out private.key 2048
	openssl req -subj "/CN=${LOCALIPADDR}" -sha256 -new -key private.key -out cert.csr
	cat <<EOF >extfile.conf
subjectAltName = DNS:${LOCALHOSTNAME}, IP:${LOCALIPADDR}
EOF
	openssl x509 -req -days 365 -sha256 -in cert.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out public.crt -extfile extfile.conf
	chmod 600 ./private.key
	chmod 600 ./public.crt
	chmod 600 ./rootCA.pem
	cp ./rootCA.pem ${MINIOCONFIGPATH}/certs/CAs
	openssl x509 -in public.crt -text -noout | grep IP
	cp public.crt ~/.mc/certs/CAs/
	cp public.crt /usr/share/ca-certificates/minio.crt
	echo "minio.crt" >>/etc/ca-certificates.conf
	update-ca-certificates
	cd || exit
fi

if [ ! -f /etc/default/minio ]; then
	cat <<EOT >/etc/default/minio
# Volume to be used for MinIO server.
MINIO_VOLUMES="${MINIOPATH}/data"
EOT
	cat <<EOT >>/etc/default/minio
# Use if you want to run MinIO on a custom port.
MINIO_OPTS="--address :9000 --console-address :9001"
# Access Key of the server.
MINIO_ROOT_USER=${MINIO_ROOT_USER}
# Secret key of the server.
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
# Minio Server for TLS
MINIO_SERVER_URL=https://${LOCALIPADDR}:9000
EOT
fi
if [ ! -f /etc/systemd/system/minio.service ]; then
	echo "Downloading systemd setting"
	#( cd /etc/systemd/system/ || return ; curl --retry 10 --retry-delay 3 --retry-connrefused -sSO https://raw.githubusercontent.com/minio/minio-service/master/linux-systemd/minio.service )
	(
		cd /etc/systemd/system/ || return
		wget https://raw.githubusercontent.com/minio/minio-service/master/linux-systemd/minio.service
	)
	sed -i -e 's/minio-user/root/g' /etc/systemd/system/minio.service
	ufw allow 9000
	ufw allow 9001
	systemctl enable --now minio.service
	systemctl status minio.service --no-pager
	sleep 3

	mc alias rm local
	MINIO_ENDPOINT=https://${LOCALIPADDR}:9000
	mc alias set local ${MINIO_ENDPOINT} ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} --api S3v4
	cat <<EOF >s3user.json
{
        "Version": "2012-10-17",
        "Statement": [{
                        "Action": [
                                "admin:ServerInfo"
                        ],
                        "Effect": "Allow",
                        "Sid": ""
                },
                {
                        "Action": [
                                "s3:ListenBucketNotification",
                                "s3:PutBucketNotification",
                                "s3:GetBucketNotification",
                                "s3:ListMultipartUploadParts",
                                "s3:ListBucketMultipartUploads",
                                "s3:ListBucket",
                                "s3:HeadBucket",
                                "s3:GetObject",
                                "s3:GetBucketLocation",
                                "s3:AbortMultipartUpload",
                                "s3:CreateBucket",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:DeleteBucket",
                                "s3:PutBucketPolicy",
                                "s3:DeleteBucketPolicy",
                                "s3:GetBucketPolicy"
                        ],
                        "Effect": "Allow",
                        "Resource": [
                                "arn:aws:s3:::*"
                        ],
                        "Sid": ""
                }
        ]
}
EOF
	mc admin policy create local s3user s3user.json
	rm s3user.json
	mc admin user add local ${MCLOGINUSER} ${MCLOGINPASSWORD}
	mc admin policy attach local s3user consoleAdmin --user ${MCLOGINUSER}
	mc alias rm local
	mc alias set local ${MINIO_ENDPOINT} ${MCLOGINUSER} ${MCLOGINPASSWORD} --api S3v4

	if [ -z $SUDO_USER ]; then
		echo "there is no sudo login"
	else
		mkdir -p /home/$SUDO_USER/.mc/certs/CAs/
		cp ~/.mc/certs/CAs/public.crt /home/$SUDO_USER/.mc/certs/CAs/
		chown -R $SUDO_USER /home/$SUDO_USER/.mc/
		sudo -u $SUDO_USER mc alias rm local
		sudo -u $SUDO_USER mc alias set local ${MINIO_ENDPOINT} ${MCLOGINUSER} ${MCLOGINPASSWORD} --api S3v4
	fi

	cd ${BASEPWD}
	if [ -f ./K2-kasten-storage.sh ]; then
		sed -i -e "s/MCLOGINUSER=miniologinuser/MCLOGINUSER=${MCLOGINUSER}/g" K2-kasten-storage.sh
		sed -i -e "s/MCLOGINPASSWORD=miniologinuser/MCLOGINPASSWORD=${MCLOGINPASSWORD}/g" K2-kasten-storage.sh
		sed -i -e "s/ERASURE_CODING=0/ERASURE_CODING=1/g" K2-kasten-storage.sh
	fi
fi
#mc admin update local

echo ""
echo "*************************************************************************************"
mc admin info local/
echo ""
echo -e "\e[32m Minio API endpoint is ${MINIO_ENDPOINT} \e[m"
echo -e "\e[32m Access Key: ${MCLOGINUSER} \e[m"
echo -e "\e[32m Secret Key: ${MCLOGINPASSWORD} \e[m"
echo -e "\e[32m Minio console is https://${LOCALIPADDR}:9001 \e[m"
echo -e "\e[32m username: ${MCLOGINUSER} \e[m"
echo -e "\e[32m password: ${MCLOGINPASSWORD} \e[m"
echo ""
echo "Update"
echo "mc admin update local"
echo "mc update"
echo "*************************************************************************************"
echo "Next Step"
echo ""
echo "run ./1-tools.sh"
echo ""
chmod -x $0
