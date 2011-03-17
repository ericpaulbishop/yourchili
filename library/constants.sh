#!/bin/bash
#!/bin/bash

export LIBEVENT_VER=1.4.13-stable
export PHP_FPM_VER=0.6
export PHP_VER=5.3.2
export SUHOSIN_PATCH_VER=0.9.9.1
export SUHOSIN_VER=0.9.29
#PHP-FPM for specific PHP versions are no longer, so using the latest applicable which seems to work fine (read: I use it in production)
export PHP_VER_IND=5.3.1

export RUBY_PREFIX="/usr/local/ruby"

export NGINX_VER=0.8.54
export NGINX_PREFIX="/srv/www"
export NGINX_SBIN_PATH="/usr/local/sbin/nginx"
export NGINX_CONF_PATH="/etc/nginx"
export NGINX_PID_PATH="/var/run/nginx.pid"
export NGINX_ERROR_LOG_PATH="/srv/www/nginx_logs/error.log"
export NGINX_HTTP_LOG_PATH="/srv/www/nginx_logs"
export LOGRO_FREQ="monthly"
export LOGRO_ROTA="12"

export APACHE_HTTP_PORT=8080
export APACHE_HTTPS_PORT=8443


export NGINX_SSL_ID="nginx_ssl"
