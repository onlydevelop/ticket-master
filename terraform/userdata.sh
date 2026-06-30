#!/bin/bash
set -euo pipefail
exec > /var/log/userdata.log 2>&1
set -x

# ── k3s single-node install ──────────────────────────────────────────────────
# --disable servicelb: skip the built-in load balancer; NGINX ingress will
#   use hostNetwork instead, binding directly to the node's public IP
# --tls-san: include the public hostname so the API cert is valid for remote kubectl
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable=servicelb \
  --tls-san=ticket-master.onlydevelop.net" sh -

echo "k3s installed, waiting for node to be Ready..."
until k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 5; done
echo "Node is Ready"

# ── NGINX ingress controller (baremetal / hostNetwork mode) ──────────────────
k3s kubectl apply -f \
  https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml

echo "Waiting for ingress-nginx controller to be ready..."
until k3s kubectl -n ingress-nginx get deployment ingress-nginx-controller 2>/dev/null \
    | awk 'NR==2{print $2}' | grep -q "^1/1$"; do
  sleep 10
done

# hostNetwork: true — NGINX listens on the node's real IP, not a cluster IP
# ClusterFirstWithHostNet — maintain kube-dns resolution while on host network
k3s kubectl patch deployment ingress-nginx-controller \
  -n ingress-nginx \
  --type=json \
  -p='[
    {"op":"add","path":"/spec/template/spec/hostNetwork","value":true},
    {"op":"add","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirstWithHostNet"}
  ]'

echo "Setup complete."
