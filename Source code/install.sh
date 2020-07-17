#!/bin/bash
SCRIPT=$(realpath $0)
SCRIPTPATH=$(dirname "$SCRIPT")
LIBPATH="/usr/local/bin/w-tools/Source code" # Access must remain after install
SOURCEPATH="$SCRIPTPATH/src"

# Includes
FILE="$LIBPATH"/stdio.sh
if ! [ -f "$FILE" ]; then
  echo "Libraries not found"
  exit
else
  . "$LIBPATH"/stdio.sh
  . "$LIBPATH"/string.sh
fi

# Check syntax
if [ -z "$1" ]; then
  echo "Syntax : $0 [configuration file]"
  exit
fi

# Check file and load parameters
FILE="$1"
if [ -f "$FILE" ]; then
  . "$1"
else
  echo "Configuration file not found : $1"
  exit
fi

# DEBUG
# if false; then

case $cfgprofile in

server)

    # Set hostname
    echo $openvpnserverhostname > /etc/hostname
    hostname $openvpnserverhostname

    # Update and Upgrade
    export DEBIAN_FRONTEND=noninteractive
    apt -y update && apt -y upgrade

    # Select packages
    pkglist="openvpn"

    # Install packages
    apt-get -qy install $pkglist

    # Copy Easy-Rsa files
    rm -rf "$easyrsabasedir"
    mkdir -p "$easyrsabasedir"
    cd "$easyrsabasedir"
    tar -xvf "$SOURCEPATH/$easyrsatgz"
    cd "$easyrsasubdir"

    # Generate and copy certificate
    ./easyrsa init-pki
    ./easyrsa --batch gen-req $openvpnserverhostname nopass

    cp -f pki/private/$openvpnserverhostname.key /etc/openvpn

    echo Private key and certificate request generated.
    echo You can now transfer the server.req file to your CA machine using a secure method.
    echo Local path on CA machine : "$PWD/pki/reqs/$openvpnserverhostname.req"
    echo Remote path on Openvpn server : displayed by install script
    echo
    echo Continue when you have transfered $openvpnserverhostname.crt and ca.crt files into "/etc/openvpn"
    echo
    echo Press any key to continue...
    pressakey

    # Create a strong Diffie-Hellman key to use during key exchange
    ./easyrsa gen-dh

    # Generate an HMAC signature to strengthen the server's TLS integrity verification capabilities
    /usr/sbin/openvpn --genkey --secret ta.key

    # Copy files into /etc/openvpn
    cp -f ./ta.key /etc/openvpn
    cp -f ./pki/dh.pem /etc/openvpn

    # Message
    echo All the certificate and key files needed by the server have been generated.

    # Prepare client configs
    mkdir -p "$ccdir/keys"
    chmod -R 700 "$ccdir"
    cp -f ./ta.key "$ccdir/keys/"
    cp -f /etc/openvpn/ca.crt "$ccdir/keys/"
    cp -f "$SOURCEPATH/gencckp.sh" "$gencckpfile"
    chmod 700 "$gencckpfile"
    declare -A confs
    confs=(
          [%%LIBPATH%%]="$LIBPATH"
          [%%CCDIR%%]="$ccdir"
          [%%EASYRSADIR%%]="$easyrsabasedir/$easyrsasubdir"
    )
    strreplaceinfile "$gencckpfile"

    echo "Server and client's certificates and keys have all been generated and are stored in the appropriate directories on your server."
    echo "We can now move to configuring OpenVPN server"

;;

ca)

    # Set hostname
    echo $camachinehostname > /etc/hostname
    hostname $camachinehostname

    # Update and Upgrade
    export DEBIAN_FRONTEND=noninteractive
    apt -y update && apt -y upgrade

    # Install Easy-Rsa
    rm -rf "$easyrsabasedir"
    mkdir -p "$easyrsabasedir"
    cd "$easyrsabasedir"
    tar -xvf "$SOURCEPATH/$easyrsatgz"

    # Easy RSA vars
    declare -A confs
    confs=(
        [%%EASYRSA_REQ_COUNTRY%%]="$EASYRSA_REQ_COUNTRY"
        [%%EASYRSA_REQ_PROVINCE%%]="$EASYRSA_REQ_PROVINCE"
        [%%EASYRSA_REQ_CITY%%]="$EASYRSA_REQ_CITY"
        [%%EASYRSA_REQ_ORG%%]="$EASYRSA_REQ_ORG"
        [%%EASYRSA_REQ_EMAIL%%]="$EASYRSA_REQ_EMAIL"
        [%%EASYRSA_REQ_OU%%]="$EASYRSA_REQ_OU"
    )
    varsfile="$easyrsabasedir/$easyrsasubdir/$varsfilename"
    cp -f "$SOURCEPATH/vars" "$varsfile"
    strreplaceinfile "$varsfile"

    # Client request signing script
    cp -f "$SOURCEPATH/signclientreq.sh" "$signclientreqscriptfile"
    chmod 700 "$signclientreqscriptfile"
    declare -A confs
    confs=(
          [%%LIBPATH%%]="$LIBPATH"
          [%%EASYRSADIR%%]="$easyrsabasedir/$easyrsasubdir"
    )
    strreplaceinfile "$signclientreqscriptfile"

    # Generate public certificate (ca.crt) and private key (ca.key)
    cd "$easyrsasubdir"
    ./easyrsa init-pki
    ./easyrsa build-ca nopass
#    ./easyrsa --batch build-ca nopass

    # Ready to start signing certificate requests
    echo Ready to start signing certificate requests. Please now run the install script on Openvpn server.
    echo Continue when you have transferred certificate request "$openvpnserverhostname.req" into directory "$easyrsabasedir"
    echo
    echo Press any key to continue...
    pressakey

    # Import server.req
    ./easyrsa import-req "$easyrsabasedir/$openvpnserverhostname.req" $openvpnserverhostname

    # Sign the request
    ./easyrsa sign-req server $openvpnserverhostname

    # Ask for transfer to Openvpn server
    echo Next, copy the server.crt and ca.crt files into Openvpn server "/etc/openvpn/" directory
    echo local path : "$easyrsabasedir/$easyrsasubdir/pki/issued/$openvpnserverhostname.crt" and "$easyrsabasedir/$easyrsasubdir/pki/ca.crt"
    echo
    echo CA machine configuration complete.
    echo Client request signing script moved to "$signclientreqscriptfile"

;;

*) echo Unknow type "$cfgprofile" ;;

esac
