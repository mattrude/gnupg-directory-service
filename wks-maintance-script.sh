#!/bin/bash

BASE="/var/lib/gnupg/wks"
REMOTE="ws1.mattrude.com"
REMOTEUID="root"
VERBOSE=1

################################################################################

PACKETS="gnupg fetchmail ssmtp procmail"
UPDATE=""
dpkg --get-selections |sed 's/:/ /g' |awk '{print $1}' > /tmp/installed-packages.txt

for a in $PACKETS
do
    if [ `egrep "^$a$" /tmp/installed-packages.txt |wc -l` != "1" ]; then
        echo "$a is not installed"
        UPDATE="$a $UPDATE"
    fi
done

rm -f /tmp/installed-packages.txt

if [ "$UPDATE" != "" ]; then
    apt install -y $UPDATE
fi

################################################################################

mkdir -p ${BASE}/hashs; cd ${BASE}/
if [ `find ${BASE}/hashs/ -type f -print |wc -l` != 0 ]; then
    find ${BASE}/hashs/ -type f -mmin +600 -delete
fi

if [ `ps aux |grep fetchmail.conf |grep -v 'grep' |wc -l` != 1 ]; then
    chown 0:0 ${BASE}/etc/fetchmail.conf
    chmod 600 ${BASE}/etc/fetchmail.conf
    /usr/bin/fetchmail -f ${BASE}/etc/fetchmail.conf -d 360 --sslcertpath /etc/ssl/certs/ 2> /dev/null
fi

for Domain in `ls -d */hu |sed 's/\/hu//'`; do
    chmod 644 ${BASE}/${Domain}/hu/*
    if [ `ls ${Domain}/hu/ |wc -l` != 0 ]; then
        mkdir -p ${BASE}/mailstore/${Domain}/{archive,cruft,from-daemon}/{cur,new,tmp} ${BASE}/mailstore/${Domain}/procmail/mail
        chown -R 0:0 ${BASE}/mailstore/${Domain} ${BASE}/${Domain}/
        chmod ug=rwX,o= ${BASE}/mailstore/${Domain}; rm -f current.sha256 old.sha256
        if [ ! -f hashs/${Domain}.sha256 ]; then touch hashs/${Domain}.sha256; fi
        sha256sum hashs/${Domain}.sha256 > old.sha256
        sha256sum ${Domain}/hu/* > hashs/${Domain}.sha256
        sha256sum hashs/${Domain}.sha256 > current.sha256
	    if [ `cat current.sha256 |awk '{ print $1 }'` != `cat old.sha256 |awk '{ print $1 }'` ]; then
            QUITE="-q"
            if [ ${VERBOSE} == 1 ]; then echo ""; echo "Updating ${Domain}!"; QUITE=""; fi

	        ## Confirm the temp keyring is gone and that we are in the correct directory.
            rm -rf /var/tmp/wkd.gpg /var/tmp/keys/${Domain}; cd ${BASE}
            
            ## Creating the temp keyring
            mkdir -p /var/www/${Domain}/keys /var/tmp/keys/${Domain}
            gpg ${QUITE} --no-default-keyring --keyring /var/tmp/wkd.gpg --import ${Domain}/hu/*
            
            ## Run the PKA & DANE export
            File=`echo ${Domain} |sed 's/\./_/g'`
            rm -f /etc/bind/zones/gnupg/${File}.gnupg; touch /etc/bind/zones/gnupg/${File}.gnupg
            for User in `gpg --no-default-keyring --keyring /var/tmp/wkd.gpg --keyid-format long --list-keys ${Domain} |grep '^pub' |sed 's/\// 0x/' |awk '{ print $3 }' |tr '[:upper:]' '[:lower:]'`
            do
                if [ ${VERBOSE} == 1 ]; then echo -n " - Processing user ${User}"; fi
                gpg --no-default-keyring --keyring /var/tmp/wkd.gpg --export-options export-dane --export ${User} >> /etc/bind/zones/gnupg/${File}.gnupg
                if [ ${VERBOSE} == 1 ]; then echo -n ", DANE"; fi
                gpg --no-default-keyring --keyring /var/tmp/wkd.gpg -a --export ${User} > /var/tmp/keys/${Domain}/${User}.asc
                KEYID="`gpg --no-default-keyring --keyring /var/tmp/wkd.gpg --list-keys ${User} |head -2 |tail -1 |awk '{ print $1 }'`"
                URL="`echo https://${Domain}/keys/0x${KEYID:24}.asc |tr '[:upper:]' '[:lower:]'`"
                origin=''
                # Let GPG generate most of the info
                data=$(gpg --no-default-keyring --keyring /var/tmp/wkd.gpg --export-options export-pka --export ${User})

                while read -r line; do
                  # Do not parse lines that do not contain a record
                  if [[ "$line" != *"TYPE37"* ]]; then
                    # Save the origin
                    if [[ "$line" == "\$ORIGIN"* ]]; then
                      origin=$(cut -d' ' -f2 <<<"${line}")
                    else
                      # Output all other lines
                      echo "${line}"
                    fi
                    continue
                  fi

                  # Get useful data
                  name=$(cut -d' ' -f1 <<<"${line}")
                  len=$(cut -d' ' -f8 <<<"${line}")
                  fpr=$(cut -d' ' -f9 <<<"${line}")

                  # Decode the hexadecimal length and fingerprint
                  fp_hex=$(xxd -r -p <<<"${len}${fpr}")

                  # Encode the above together with the url as base64
                  rdata=$(echo -n ${fp_hex}${URL} | base64 -w0)

                  # Show the record
                  echo "${name}.${origin} 3600 IN CERT 6 0 0 ${rdata}"
                done <<< "$data" >> /etc/bind/zones/gnupg/${File}.gnupg
                if [ ${VERBOSE} == 1 ]; then echo ", and PKA"; fi
            done
            
            ## Transmit the WKD files to the webserver.
            ssh ${REMOTEUID}@${REMOTE} mkdir -p /var/www/${Domain}/.well-known/openpgpkey /var/www/openpgpkey/.well-known/openpgpkey/${Domain} /var/www/${Domain}/keys
            rsync -a --del /var/tmp/keys/${Domain}/* ${REMOTEUID}@${REMOTE}:/var/www/${Domain}/keys/ --exclude pending
            rsync -a --del ${BASE}/${Domain}/* ${REMOTEUID}@${REMOTE}:/var/www/${Domain}/.well-known/openpgpkey/ --exclude pending
            rsync -a --del ${BASE}/${Domain} ${REMOTEUID}@${REMOTE}:/var/www/openpgpkey/.well-known/openpgpkey/ --exclude pending
            
            ## Deleing the temp keyring
            rm -rf /var/tmp/wkd.gpg /var/tmp/keys/${Domain}
            sha256sum ${Domain}/hu/* > hashs/${Domain}.sha256
        fi
        rm -f current.sha256 old.sha256
        find ${BASE}/mailstore/${Domain}/{archive,cruft,from-daemon} -type f -mtime +3 -delete
    fi
done
