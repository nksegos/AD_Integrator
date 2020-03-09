#!/bin/bash

# Variable declaration START

DOMAIN=""
DOMAIN_SHORT="" 
DC=""
DC_ADDR=""
BASE_HOSTNAME=""
BIND_USER="Administrator"
BIND_PW=''
AUTO_MODE=0
LOGFILE=/var/log/ad_integrator.log
FAIL_BUFFER=$(mktemp)
conf_backups=()

# Variable declaration END

set -u # Exit on reference to unbound variables

# Function definition START

## Usage function 
Usage(){
	echo "Usage:"
	echo " 		-d DOMAIN: Provide the domain to be joined."
	echo " 		-c DOMAIN CONTROLLER: Provide the hostname of the domain controller."
	echo " 		-b BASE HOSTNAME: Provide the base hostname prefix for the joined machine."
	echo " 		-u DOMAIN BIND USER: Provide the user to join the domain with.(Default: Administrator)"
	echo " 		-p DOMAIN BIND PASSWORD: Provide the password file for the user to join the domain."
	echo " 		-a: Set execution mode to automatic. User won't be queried for host reboot or to setting restoration in case of failure."
	echo " 		-h: Display help menu."
	echo ""
}

## Logging function
log_msg(){
	printf "$1" | tee -a $LOGFILE
}

## User prompt utility function
user_prompt(){
	local USER_REPLY=""
	read -r -p "$2 " USER_REPLY 
 	case $USER_REPLY in
        	[yY][eE][sS]|[yY])
			$1
                 	;;
                 [nN][oO]|[nN])
                 	true
                 	;;
         	"")
              		$3 
                 	;;
        	*)
                 	true
                	;;
	esac
}

## Attain a host's IP from DNS
get_ip(){
	host -4 $1 | head -n 1 | awk -F" " '/has address/ {print $4}'
}

## Utility configuration file backup function
add_backup(){
    local dir=$(dirname $1)
    local filename=$(basename $1)
    backup="${dir}/.${filename}.bkp"
    cp $1 $backup 
    conf_backups+=($backup)
}

## Utility backup restoration function
restore_backups(){
	for backup in "${conf_backups[@]}"; do
        	log_msg "Restoring conf backup: ${backup} \n" 
		local dir=$(dirname $backup)
		local filename=$(basename $backup)
        	cat $backup > ${dir}/${filename: 1: -4}
    	done
}

## Utility backup removal function
remove_backups(){
	for backup in "${conf_backups[@]}"; do
		log_msg "Deleting conf backup: ${backup} \n" 
		rm -f $backup > /dev/null 2>&1
	done
}

## Exit code evaluation function
exit_check(){
	currentTimestamp=$(date '+%Y-%m-%d %H:%M:%S')	
	if [ "$1" -eq 0 ]; then
		log_msg "Done!\n"
	else 
		log_msg "Failed! \n"
		log_msg "$currentTimestamp [${0}:${LINENO}][$$] ERROR: $2 \n"
		if [ -f "$3" ]; then
			log_msg "Dumping error message"
			if [[ "$(wc -l $3 | awk -F" " '{print $1}')" -gt 15 ]]; then
				log_msg "(last 15 lines):\n"
				tail -n 15 $3 | tee -a $LOGFILE
			else
				log_msg ":\n"
				cat $3 | tee -a $LOGFILE
			fi
		fi
		restore_backups
		log_msg "Exiting...\n"
		exit 1
	fi
}

# Function definition END


# Input collection and sanitization START

while getopts ":d:c:b:u:p:ha" opt ; do
	case $opt in
		d)
			DOMAIN=$OPTARG
			;; 
		c)
			DC=$OPTARG
			;;
		b)
			BASE_HOSTNAME=$OPTARG
			;;
		u)
			BIND_USER=$OPTARG
			;;
		p)
			if [ -f "$OPTARG" ]; then
				BIND_PW=$(head -n 1 $OPTARG)
			else
				echo "The file $OPTARG doesn't exit."
			fi
			;;
		a)
			AUTO_MODE=1
			;;
		h)
			Usage
			exit 0
			;;
		\?)
			echo "Invalid option: -$OPTARG"
			Usage
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument."
			Usage
			exit 1
			;;
	esac
done


## Privilege check
if [[ "$EUID" != "0" ]]; then
    printf "\nThis script must be run as root.\n" 
    exit 1
fi


if [ -z "$DOMAIN" ]; then
	read -p "Enter Domain: " DOMAIN
fi

if [ -z "$DC" ]; then
	read -p "Enter Domain Controller hostname: " DC
fi

if [ -z "$BASE_HOSTNAME" ]; then
	read -p "Enter base hostname prefix: " BASE_HOSTNAME
fi

if [ -z "$BIND_USER" ]; then
	read -p "Enter bind user: " BIND_USER
fi

if [ -z "$BIND_PW" ]; then
	read -p "Enter bind password: " -s BIND_PW
fi

## Preliminary checks

if ! grep -q "search ${DOMAIN,,}" /etc/resolv.conf ; then
	log_msg "\nsearch domain is not set to the AD DNS domain in /etc/resolv.conf.\n"
	exit 1
fi
DOMAIN_SHORT=$(echo ${DOMAIN^^} | awk -F. '{print $1}')
DC_ADDR=$(get_ip $DC)
if [ -z "$DC_ADDR" ]; then
	log_msg "\nCannot resolve DC with hostname ${DC}. Check your DNS setup.\n"
	exit 1
fi

# Input collection and sanitization END


# AD Integration START

log_msg "\nStarting AD integration for domain: ${DOMAIN^^}.\n"

## Download necessary packages
log_msg "\nGetting required packages..."
export DEBIAN_FRONTEND=noninteractive
apt install -yq chrony adcli realmd krb5-user samba-common-bin samba-libs samba-dsdb-modules sssd sssd-tools libnss-sss libpam-sss packagekit policykit-1 > $FAIL_BUFFER 2>&1
exit_check $? "Installation failed" $FAIL_BUFFER


## Set up new hostname
### Build new hostname as per naming convention
ADDRESS=$(ip a | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' )
CN=$(echo $ADDRESS | cut -d . -f 4)
NEW_HOSTNAME="${BASE_HOSTNAME}-$(printf "%02d" $CN)"
log_msg "Changing hostname to \"${NEW_HOSTNAME}\"..."
### Update /etc/hostname file and set it via the hostname command for it to take effect immediately
add_backup /etc/hostname
cat << EOF > /etc/hostname
$NEW_HOSTNAME
EOF

hostname "$NEW_HOSTNAME" > $FAIL_BUFFER 2>&1
exit_check $? "Changing hostname failed!" $FAIL_BUFFER # Pure paranoia

### Update /etc/hosts file
log_msg "Modding /etc/hosts file..."
add_backup /etc/hosts
cat << EOF > /etc/hosts
127.0.0.1 	localhost
$ADDRESS 	${NEW_HOSTNAME,,}.${DOMAIN,,} 	${NEW_HOSTNAME,,}
EOF
log_msg "Done!\n"


## Set up NTP synchronization
log_msg "Synchronizing Time..."
add_backup /etc/chrony/chrony.conf
cat << EOF > /etc/chrony/chrony.conf
# Welcome to the chrony configuration file. See chrony.conf(5) for more
# information about usuable directives.
server ${DC,,}.${DOMAIN,,} iburst

# This directive specify the location of the file containing ID/key pairs for
# NTP authentication.
keyfile /etc/chrony/chrony.keys

# This directive specify the file into which chronyd will store the rate
# information.
driftfile /var/lib/chrony/chrony.drift

# Uncomment the following line to turn logging on.
#log tracking measurements statistics

# Log files location.
logdir /var/log/chrony

# Stop bad estimates upsetting machine clock.
maxupdateskew 100.0

# This directive enables kernel synchronisation (every 11 minutes) of the
# real-time clock. Note that it can’t be used along with the 'rtcfile' directive.
rtcsync

# Step the system clock instead of slewing it if the adjustment is larger than
# one second, but only in the first three clock updates.
makestep 1 3
EOF

timedatectl set-ntp true  > /dev/null 2>&1
systemctl enable chrony  > /dev/null 2>&1
systemctl restart chrony  > /dev/null 2>&1

chronyc sources | grep -q "${DC,,}.${DOMAIN,,}\|$DC_ADDR" > /dev/null 2>&1
exit_check $? "DC is not found by chrony." 


## Set up MIT Kerberos client configuration
log_msg "Setting up Kerberos..."
add_backup /etc/krb5.conf
cat > /etc/krb5.conf << EOF 
[logging]
default = FILE:/var/log/krb5libs.log
kdc = FILE:/var/log/krb5kdc.log
admin_server = FILE:/var/log/kadmind.log

[libdefaults]
default_realm = ${DOMAIN^^}
dns_lookup_realm = true
dns_lookup_kdc = true
ticket_lifetime = 24h
renew_lifetime = 7d
forwardable = true

[realms]
${DOMAIN^^} = {
kdc = ${DC,,}.${DOMAIN,,}:88
}

[domain_realm]
.${DOMAIN,,} = ${DOMAIN^^}
${DOMAIN,,} = ${DOMAIN^^}
EOF

log_msg "Done!\n"


## Set up Samba client configuration
log_msg "Setting up Samba..."
add_backup /etc/samba/smb.conf
cat << EOF > /etc/samba/smb.conf
[global]
    workgroup = ${DOMAIN_SHORT^^}
    client signing = yes
    client use spnego = yes
    kerberos method = secrets and keytab
    log file = /var/log/samba/%m.log
    realm = ${DOMAIN^^}
    security = ads
EOF

log_msg "Done!\n"


## Get Kerberos keytab
log_msg "Starting Kerberos Connection..." 
echo $BIND_PW | kinit Administrator > $FAIL_BUFFER 2>&1
exit_check $? "reee" $FAIL_BUFFER


## Join the domain
log_msg "Joining the Domain..."
net ads join -k -S ${DC^^}.${DOMAIN^^} > $FAIL_BUFFER 2>&1
exit_check $? "Join failed!" $FAIL_BUFFER

/usr/sbin/realm permit --all


## Set up SSSD configuration
log_msg "Configuring SSSD..."
touch /etc/sssd/sssd.conf # Just to make sure it exists
add_backup /etc/sssd/sssd.conf
cat > /etc/sssd/sssd.conf << EOF
[domain/${DOMAIN,,}]
id_provider = ad
access_provider = ad
override_shell=/bin/bash
override_homedir=/tmp/home/%u
debug_level = 0

[sssd]
services = nss, pam
config_file_version = 2
domains = ${DOMAIN,,}

[nss]

[pam]

EOF

chmod 600 /etc/sssd/sssd.conf

systemctl restart sssd > $FAIL_BUFFER 2>&1
exit_check $? "SSSD restart failed." $FAIL_BUFFER


## Set up Pam Auth and homedir autocreation
log_msg "Setting up Pluggable Auth Modules..."
add_backup /etc/pam.d/common-account
echo "session    required    pam_mkhomedir.so    skel=/etc/skel/    umask=0022" >> /etc/pam.d/common-account
log_msg "Done! \n"

log_msg "\nAD integration for domain ${DOMAIN^^} has been completed.\n\n"

# AD Integration END

# Cleanup
if [ "$AUTO_MODE" -eq 0 ]; then
	user_prompt remove_backups "Remove backup configuration files? [y/N]" true
	printf "\n"
	user_prompt /usr/sbin/reboot "Reboot system now? [Y/n]" /usr/sbin/reboot
else
	log_msg "Rebooting.\n"
	/usr/sbin/reboot
fi
