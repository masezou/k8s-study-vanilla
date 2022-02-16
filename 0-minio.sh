#!/usr/bin/env bash

#########################################################

MCLOGINUSER=miniologinuser
MCLOGINPASSWORD=miniologinuser
MINIOPATH=/disk/minio

#FORCE_LOCALIP=192.168.16.2
#########################################################

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
lsb_release -d | grep Ubuntu | grep 20.04
DISTVER=$?
if [ ${DISTVER} = 1 ]; then
    echo "only supports Ubuntu 20.04 server"
    exit 1
else
    echo "Ubuntu 20.04=OK"
fi
if [ ! -f /usr/share/doc/ubuntu-server/copyright ]; then
echo -e "\e[31m It seemed his VM is installed Ubuntu Desktop media. VM which is installed from Ubuntu Desktop media is not supported. Please re-create VM from Ubuntu Server media! \e[m"
exit 255
fi


### ARCH Check ###
PARCH=`arch`
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
        LOCALIPADDR=`ip -f inet -o addr show ens160 |cut -d\  -f 7 | cut -d/ -f 1`
else
  ip address show ens192 >/dev/null
  retval2=$?
   if [ ${retval2} -eq 0 ]; then
         LOCALIPADDR=`ip -f inet -o addr show ens192 |cut -d\  -f 7 | cut -d/ -f 1`
   else
         LOCALIPADDR=`ip -f inet -o addr show eth0 |cut -d\  -f 7 | cut -d/ -f 1`
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

#########################################################
BASEPWD=`pwd`

if [ ! -f /usr/local/bin/minio ]; then
if [ ! -d ${MINIOPATH} ]; then
ufw allow 9000
ufw allow 9001
mkdir -p ${MINIOPATH}/data{1..4}
chmod -R 755 ${MINIOPATH}/data*
fi
mkdir -p ~/.minio/certs
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://dl.min.io/server/minio/release/linux-${ARCH}/minio
mv minio  /usr/local/bin/
chmod +x /usr/local/bin/minio
fi
if [ ! -f /usr/local/bin/mc ]; then
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://dl.min.io/client/mc/release/linux-${ARCH}/mc
mv mc /usr/local/bin/
chmod +x /usr/local/bin/mc
echo "complete -C /usr/local/bin/mc mc" > /etc/bash_completion.d/mc.sh
/usr/local/bin/mc >/dev/null
fi
if [ ! -f /root/.minio/certs/public.crt ]; then
cd /root/.minio/certs/
LOCALHOSTNAME=`hostname`
openssl genrsa -out rootCA.key 4096
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1825 -out rootCA.pem -subj "/C=JP/ST=Tokyo/L=Shibuya/O=cloudshift.corp/OU=development/CN=exmaple CA"
openssl genrsa -out private.key 2048
openssl req -subj "/CN=${LOCALIPADDR}" -sha256 -new -key private.key -out cert.csr
cat << EOF > extfile.conf
subjectAltName = DNS:${LOCALHOSTNAME}, IP:${LOCALIPADDR}
EOF
openssl x509 -req -days 365 -sha256 -in cert.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out public.crt -extfile extfile.conf
chmod 600 ./private.key
chmod 600 ./public.crt
chmod 600 ./rootCA.pem
mkdir -p /root/.minio/certs/CAs
cp ./rootCA.pem /root/.minio/certs/CAs
openssl x509 -in public.crt -text -noout| grep IP
cp public.crt ~/.mc/certs/CAs/
cp /root/.minio/certs/public.crt /usr/share/ca-certificates/minio.crt
echo "minio.crt">>/etc/ca-certificates.conf
update-ca-certificates
cd || exit
fi
if [ ! -f /etc/systemd/system/minio.service ]; then

if [ ! -f /etc/default/minio ]; then
cat <<EOT > /etc/default/minio
# Volume to be used for MinIO server.
MINIO_VOLUMES="${MINIOPATH}/data1 ${MINIOPATH}/data2 ${MINIOPATH}/data3 ${MINIOPATH}/data4"
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

( cd /etc/systemd/system/ || return ; curl --retry 10 --retry-delay 3 --retry-connrefused -sSO https://raw.githubusercontent.com/minio/minio-service/master/linux-systemd/minio.service )
sed -i -e 's/minio-user/root/g' /etc/systemd/system/minio.service
sed -i -e "s@/opt/bin/@/usr/local/bin/@g" /etc/systemd/system/minio.service
systemctl enable --now minio.service
systemctl status minio.service --no-pager
sleep 3

mc alias rm local
MINIO_ENDPOINT=https://${LOCALIPADDR}:9000
mc alias set local ${MINIO_ENDPOINT} ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} --api S3v4
cat << EOF > s3user.json
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
mc admin policy add local/ s3user s3user.json
rm s3user.json
mc admin user add local ${MCLOGINUSER} ${MCLOGINPASSWORD} 
mc admin policy set local s3user,consoleAdmin user=${MCLOGINUSER}
mc alias rm local
mc alias set local ${MINIO_ENDPOINT} ${MCLOGINUSER} ${MCLOGINPASSWORD} --api S3v4
fi


if [ -z $SUDO_USER ]; then
  echo "there is no sudo login"
else
 mkdir -p /home/$SUDO_USER/.mc/certs/CAs/
 cp ~/.mc/certs/CAs/public.crt /home/$SUDO_USER/.mc/certs/CAs/
 chown -R $SUDO_USER  /home/$SUDO_USER/.mc/
 sudo -u $SUDO_USER mc alias rm local
 sudo -u $SUDO_USER mc alias set local ${MINIO_ENDPOINT} ${MCLOGINUSER} ${MCLOGINPASSWORD} --api S3v4
fi

mc admin info local/

cd ${BASEPWD}
if [ -f K2-kasten-storage.sh ]; then
sed -i -e "s/MCLOGINUSER=miniologinuser/MCLOGINUSER=${MCLOGINUSER}/g" K2-kasten-storage.sh
sed -i -e "s/MCLOGINPASSWORD=miniologinuser/MCLOGINPASSWORD=${MCLOGINPASSWORD}/g" K2-kasten-storage.sh
fi

echo ""
echo "*************************************************************************************"
echo -e "\e[32m Minio API endpoint is ${MINIO_ENDPOINT} \e[m"
echo -e "\e[32m Access Key: ${MCLOGINUSER} \e[m"
echo -e "\e[32m Secret Key: ${MCLOGINPASSWORD} \e[m"
echo -e "\e[32m Minio console is https://${LOCALIPADDR}:9001 \e[m"
echo -e "\e[32m username: ${MCLOGINUSER} \e[m"
echo -e "\e[32m password: ${MCLOGINPASSWORD} \e[m"
echo ""
echo "*************************************************************************************"
echo "Next Step"
echo ""
echo "run ./1-tools.sh"
echo ""
chmod -x $0
