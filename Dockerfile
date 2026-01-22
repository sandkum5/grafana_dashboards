# Use the official Grafana image as a base
FROM grafana/grafana:latest

# Install a specific plugin using grafana-cli
RUN grafana-cli plugins install yesoreyeram-infinity-datasource

# ADD ./dashboards/ /etc/grafana/provisioning/dashboards/
# ADD ./datasources/ /etc/grafana/provisioning/datasources/


# Build your new image using:
# podman build -t itm-grafana .

# Start Container
# podman run -d --name=itm_grafana -p 3000:3000 -v $(pwd)/dashboards:/etc/grafana/provisioning/dashboards -v $(pwd)/datasources:/etc/grafana/provisioning/datasources/ localhost/itm-grafana:latest
