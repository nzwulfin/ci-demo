FROM registry.redhat.io/rhel9/rhel-bootc:9.6-1749484483

#Install base software
RUN dnf -y install tmux mkpasswd

#Configure bootc-user
RUN pass=$(mkpasswd --method=SHA-512 --rounds=4096 redhat) && useradd -m -G wheel bootc-user -p $pass

#Setup sudo to not require password
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo

#Using the optional heredoc format to help simplify the number of times we call RUN
RUN <<EORUN
set -xeuo pipefail

#Install web server and relocate the webroot to managed by this image
dnf -y install httpd && dnf clean all
systemctl enable httpd
mv /var/www /usr/share/www
sed -ie 's,/var/www,/usr/share/www,' /etc/httpd/conf/httpd.conf
echo "Welcome to the bootc-http instance!" > /usr/share/www/html/index.html

EORUN

# Mask the auto timer so we can control this in a downstream image or host
RUN systemctl mask bootc-fetch-apply-updates.timer

#Clean up caches in the image and lint the container
RUN rm /var/{cache,lib}/dnf /var/lib/rhsm /var/cache/ldconfig -rf
RUN bootc container lint

# For testing as a container in a pipeline
EXPOSE 80
