FROM postgres:17-bookworm
LABEL org.opencontainers.image.authors="napster@npstr.space"

ENV POSTGRES_USER=postgres

RUN apt-get update && apt-get install -y \
    cron \
    backblaze-b2 \
    pv \
    lbzip2 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

COPY pg_b2_backup.sh /usr/local/bin/
RUN touch /var/log/pg_backup.log
ADD crontab /etc/cron.d/pg_backup
RUN chmod 0644 /etc/cron.d/pg_backup
RUN touch /var/log/cron.log
RUN /usr/bin/crontab /etc/cron.d/pg_backup

COPY initdb.sh /usr/local/bin/
COPY run.sh /usr/local/bin/

ENTRYPOINT ["/bin/bash", "run.sh"]

HEALTHCHECK --interval=30s --retries=1 CMD LAST_DB=$(echo $DB | awk '{print $NF}'); /usr/bin/psql -U $POSTGRES_USER -tAc "SELECT 1 FROM pg_database WHERE datname='$LAST_DB';" | grep -q 1 || exit 1
