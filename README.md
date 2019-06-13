## Fetchmail GnuPG Web Key Directory Service

This repository holds the working configuration for my multi-domain Gnupg Web
Key Directory install.

This install runs `fetchmail` against external POP & SMTP servers, checking at
a prescribed interval.

## How it works

To start, `fetchmail`, running as a daemon, checks for new messages every
`4 minutes`, if a message is received, `procmail` process the message and passes
it off to `gpg-wks-server`.

Once `gpg-wks-server` finishes processing the message, it normally will send a
reply, this is accomplished via `ssmtp`.

## Installing the Repository

First we need to install the needed software.

    apt update; apt -y install gnupg git fetchmail ssmtp procmail

Then install the config.

    mkdir -p /var/lib/gnupg
    git clone git@git.mattrude.com:secure/gnupg-wks-config.git /var/lib/gnupg/wks

Run the install script.

    /var/lib/gnupg/wks/wks-maintance-script.sh

Confirm fetchmail is running

    ps aux |grep fetchmail |grep -v grep

Update Cron.

    18 2   *   *   *   /usr/bin/gpg-wks-server --cron
    28 *   *   *   *   /var/lib/gnupg/wks/wks-maintance-script.sh

## Adding a new Domain

At this point, adding a new domain consists of adding a new, domain specific,
section to the already existing `fetchmail.conf` file, `/var/lib/gnupg/wks/etc`
directory.  Then you must create new `procmail-example.com.conf` and
`ssmtp-example.com.conf` in the same directory so each file can find them.

### fetchmail.conf

Start out by going into the `/var/lib/gnupg/wks/etc` directory and modify the
`fetchmail.conf` file.  Each domain must have its own section in the file similar
to the following.

    poll "pop.googlemail.com" protocol pop3 auth password
    username "wkd-submission@example.com" is apprentice here
    password '###### POP3 Password ######'
    ssl sslproto tls1, sslcertck, idle
    fetchall
    nokeep
    mda "/usr/bin/procmail -m /var/lib/gnupg/wks/etc/procmail-example.com.conf"

After you have added the needed section to `fetchmail.conf`, you need to create
the domains corresponding `procmail-example.com.conf` file.

### procmail-example.com.conf

The provided example `procmail-example.conf` files are a stable staring point,
just change the `DOMAIN` line to be the domain you wish to process and save the
the file accordingly.

    DOMAIN=example.com
    BASE=/var/lib/gnupg/wks
    PATH=$HOME/bin:/usr/bin:/bin:/usr/local/bin
    LD_LIBRARY_PATH=$HOME/lib
    CORRECTHOME=${BASE}/mailstore/${DOMAIN}
    MAILDIR=$CORRECTHOME/
    PMDIR=${BASE}/mailstore/${DOMAIN}/procmail
    LOGFILE=${BASE}/logs/procmail-${DOMAIN}.log
    LOCKFILE=${PMDIR}/.lockmail
    VERBOSE=on
    
    :0
    * ^FROM_DAEMON
    from-daemon/
    
    :0 c
    archive/
    
    :0 w
    * !^From: wkd-submission@${DOMAIN}
    * !^X-WKS-Loop: wks.${DOMAIN}
    |/usr/local/bin/gpg-wks-server -v --receive \
        --header X-WKS-Loop=wks.${DOMAIN} \
        --from wkd-submission@${DOMAIN} \
        |/usr/sbin/ssmtp -C ${BASE}/etc/ssmtp-${DOMAIN}.conf -t
    
    :0 e
    cruft/

And once you are finished with the `procmail-example.com.conf` file, you need
to create the domains corresponding `ssmtp-example.com.conf` file.

### ssmtp-example.com.conf

Finely after `gpg-wks-server` finishes its processing, it normally sends a
response to the sender.  This is accomplished via `ssmtp` and the something 
similar to the below `ssmtp-example.com.conf` file.

All you should have to change on this file is the AuthUser (username) and the
AuthPass (password) and save it as the name the domains procemail config file
is looking for.

    root=wkd-submission
    hostname=ns0.another-domain-or-the-same.com
    mailhub=smtp.googlemail.com:587
    FromLineOverride=YES
    UseSTARTTLS=YES
    AuthUser=wkd-submission@example.com
    AuthPass=###### SMTP Password ######
    FromLineOverride=YES


## Repository License

This repository is licensed under the 3-Clause BSD License as seen below.

    Copyright 2019 Matt Rude <matt@mattrude.com>
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    1. Redistributions of source code must retain the above copyright notice, 
    this list of conditions and the following disclaimer.
    
    2. Redistributions in binary form must reproduce the above copyright notice, 
    this list of conditions and the following disclaimer in the documentation 
    and/or other materials provided with the distribution.
    
    3. Neither the name of the copyright holder nor the names of its 
    contributors may be used to endorse or promote products derived from this 
    software without specific prior written permission.
    
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.

