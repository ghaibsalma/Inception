FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    mariadb-server \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/mysqld \
    && chown -R mysql:mysql /var/run/mysqld \
    && chmod 777 /var/run/mysqld

COPY ./conf/my.cnf /etc/mysql/mariadb.conf.d/50-server.cnf 

COPY ./tools/mariadb.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/mariadb.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/mariadb.sh"]
CMD ["mysqld", "--bind-address=0.0.0.0"]


