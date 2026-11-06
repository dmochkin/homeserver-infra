# Backup tools: pg_dump and pg_restore matching the server's Postgres, age for
# encryption and rclone for Cloudflare R2. Built on the server by Ansible.
# Ansible passes postgres_image from group_vars; the default only keeps the build self-contained.
ARG POSTGRES_IMAGE=postgres:17.9-alpine3.23
FROM ${POSTGRES_IMAGE}
RUN apk add --no-cache age rclone tzdata
COPY --chmod=0755 backup-databases restore-check restore-all /usr/local/bin/
