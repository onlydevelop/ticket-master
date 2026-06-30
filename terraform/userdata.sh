#!/bin/bash
set -euo pipefail
exec > /var/log/userdata.log 2>&1

# ── IMDSv2: obtain a session token and use the IPv6 metadata endpoint ────────
# Nitro-based instances expose instance metadata at fd00:ec2::254 over IPv6.
# IMDSv2 requires a PUT to get a token before any GET.
TOKEN=$(curl -sX PUT "http://[fd00:ec2::254]/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Retrieve this instance's primary IPv6 address so k3s knows which IP to bind
NODE_IPV6=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://[fd00:ec2::254]/latest/meta-data/ipv6")

echo "Node IPv6: ${NODE_IPV6}"

# ── k3s single-node install ──────────────────────────────────────────────────
# --cluster-cidr / --service-cidr: ULA IPv6 ranges for pods (fd00:42::/56)
#   and services (fd00:43::/112); these stay on-node and never hit the internet
# --disable servicelb: skip the built-in MetalLB-like load balancer; NGINX
#   ingress will use hostNetwork instead, binding directly to the public IPv6
# --flannel-ipv6-masq: enables IPv6 masquerading in Flannel so pod egress
#   traffic is correctly NATed to the node's public IPv6 address
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --node-ip=${NODE_IPV6} \
  --cluster-cidr=fd00:42::/56 \
  --service-cidr=fd00:43::/112 \
  --disable=servicelb \
  --flannel-ipv6-masq" sh -

echo "k3s installed, waiting for node to be Ready..."
until k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 5; done
echo "Node is Ready"

# ── NGINX ingress controller (baremetal / hostNetwork mode) ──────────────────
# The baremetal manifest avoids provisioning a cloud load balancer (there is
# none in this setup). We then patch the Deployment to add hostNetwork: true
# so NGINX binds directly to the node's public IPv6 address on ports 80/443.
k3s kubectl apply -f \
  https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml

echo "Waiting for ingress-nginx controller to be ready..."
until k3s kubectl -n ingress-nginx get deployment ingress-nginx-controller 2>/dev/null \
    | awk 'NR==2{print $2}' | grep -q "^1/1$"; do
  sleep 10
done

# hostNetwork: true — NGINX listens on the node's real IP stack, not a cluster IP
# ClusterFirstWithHostNet — maintain kube-dns resolution while on host network
k3s kubectl patch deployment ingress-nginx-controller \
  -n ingress-nginx \
  --type=json \
  -p='[
    {"op":"add","path":"/spec/template/spec/hostNetwork","value":true},
    {"op":"add","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirstWithHostNet"}
  ]'

echo "Setup complete. NGINX ingress is bound to ${NODE_IPV6} on ports 80/443."
