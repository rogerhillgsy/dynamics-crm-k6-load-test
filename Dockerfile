FROM grafana/k6:0.56.0

COPY k6 /scripts

ENTRYPOINT ["k6", "run", "/scripts/dynamics-crm.js"]
