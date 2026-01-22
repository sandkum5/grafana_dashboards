#!/bin/bash

echo "Building New image"
podman build -t itm-grafana .

echo "Starting Container"
podman run -d --name=itm_grafana -p 3000:3000 -v $(pwd)/dashboards:/etc/grafana/provisioning/dashboards -v $(pwd)/datasources:/etc/grafana/provisioning/datasources/ localhost/itm-grafana:latest
