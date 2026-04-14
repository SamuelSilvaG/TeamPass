FROM richarvey/nginx-php-fpm:latest

# The location of the web files
ARG VOL=/var/www/html
ENV VOL ${VOL}
VOLUME ${VOL}
WORKDIR ${VOL}

# Configure nginx-php-fpm image to use this dir.
ENV WEBROOT ${VOL}
RUN apk add --no-cache gnu-libiconv libldap gmp
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

RUN echo && \
  # Install and configure missing PHP requirements
  /usr/local/bin/docker-php-ext-configure bcmath && \
  /usr/local/bin/docker-php-ext-install bcmath && \
  apk add --no-cache --virtual .docker-php-dependencies \
            openldap-dev gmp-dev && \ 
  /usr/local/bin/docker-php-ext-configure ldap && \
  /usr/local/bin/docker-php-ext-install ldap gmp && \
  apk del .docker-php-dependencies && \
  echo "max_execution_time = 120" >> /usr/local/etc/php/conf.d/docker-vars.ini && \
  echo "post_max_size = 100M" >> /usr/local/etc/php/conf.d/docker-vars.ini && \
  echo "upload_max_filesize = 100M" >> /usr/local/etc/php/conf.d/docker-vars.ini && \
echo

RUN echo && \
  # Fix 'Error when trying to read crontab : crontab: must be suid to work properly'
  apk add --no-cache --update busybox-suid && \
  # Fix 'Error when trying to read crontab : crontab: can't open 'nginx': No such file or directory'
  echo '* * * * * php /var/www/html/sources/scheduler.php #Teampass scheduler' > /var/spool/cron/crontabs/nginx && \
echo

# Fix API URL, BUG: API not working in container. #2100
# Search last } and insert configuration rows before
RUN sed -i "/^}/i \
  location /api/ {\
          try_files \$uri \$uri/ /api/index.php?\$args;\
  }\
  client_max_body_size 100M;" /etc/nginx/sites-enabled/default.conf

COPY teampass-docker-start.sh /teampass-docker-start.sh
# Configure nginx-php-fpm image to pull our code.
ENV REPO_URL https://github.com/MaisCincoGoncalves/TeamPass.git
ENV GIT_TAG 3.1.4.30

# Apply file size limit fix for backups
RUN echo '#!/bin/sh' > /apply-fixes.sh && \
  echo 'if [ -f /var/www/html/pages/backups.js.php ]; then' >> /apply-fixes.sh && \
  echo '  sed -i '\''s/max_file_size: "[^"]*"/max_file_size: "100mb"/g'\'' /var/www/html/pages/backups.js.php' >> /apply-fixes.sh && \
  echo 'fi' >> /apply-fixes.sh && \
  chmod +x /apply-fixes.sh

# Set correct permissions
RUN mkdir -p /var/www/html/sk /var/www/html/includes/libraries/csrfp/log && \
    chown -R nginx:nginx /var/www/html

# Configure nginx-php-fpm image to pull our code.
ENV REPO_URL https://github.com/MaisCincoGoncalves/TeamPass.git
#ENV GIT_TAG 3.0.0.14

# Configure supervisord program:crond
RUN echo && \
  mkdir -pv /etc/supervisor/conf.d && \
  echo -e "\
[program:crond]\n\
command=/usr/sbin/crond -f -L /dev/stdout\n\
autostart=true\n\
autorestart=true\n\
priority=15\n\
user=root\n\
stdout_events_enabled=true\n\
stderr_events_enabled=true\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
stopsignal=QUIT" > /etc/supervisor/conf.d/crond.conf && \
echo


ENTRYPOINT ["/bin/sh"]
CMD ["/teampass-docker-start.sh"]
