# Kubernetes Cluster Troubleshooting Guide

Common issues and solutions encountered during cluster provisioning and management.

## 📋 Quick Diagnostics

### Cluster Health Check
```bash
# Overall cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Component status
kubectl get componentstatuses
kubectl cluster-info

# Check system pods
kubectl get pods -n kube-system
kubectl get pods -n calico-system
```

## 🔧 AWS SSM Issues

### SSM Parameter Not Found
```bash
# List all cluster SSM parameters
aws ssm get-parameters-by-path --path "/k8s/your-cluster-name" --recursive

# Check specific parameter
aws ssm get-parameter --name "/k8s/your-cluster-name/join-token" --with-decryption

# Common parameters to check
aws ssm get-parameter --name "/k8s/your-cluster-name/control-plane-endpoint"
aws ssm get-parameter --name "/k8s/your-cluster-name/cacert-hash"
```

### SSM Permission Issues
```bash
# Check IAM role attached to EC2 instance
aws sts get-caller-identity
aws iam list-attached-role-policies --role-name your-ec2-role

# Test SSM connectivity
aws ssm describe-instance-information
```

## 🖥️ AWS EC2 Issues

### Instance Launch Failures
```bash
# Check instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=*your-cluster*"

# Check security groups
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx

# Check subnets and availability
aws ec2 describe-subnets --subnet-ids subnet-xxxxxxxxx
```

### AMI Issues
```bash
# List available AMIs
aws ec2 describe-images --owners self --filters "Name=name,Values=kubernetes-*"

# Check AMI details
aws ec2 describe-images --image-ids ami-xxxxxxxxx
```

### Network Connectivity
```bash
# Test connectivity between nodes
ping <node-ip>
telnet <node-ip> 6443  # API server
telnet <node-ip> 2379  # etcd
telnet <node-ip> 10250 # kubelet
```

## 🏗️ Terraform Issues

### State Lock Issues
```bash
# List DynamoDB locks
aws dynamodb scan --table-name terraform-state-lock

# Force unlock (use with caution)
terraform force-unlock <lock-id>
```

### Resource Creation Failures
```bash
# Detailed plan with debug
terraform plan -detailed-exitcode
TF_LOG=DEBUG terraform apply

# Target specific resources
terraform apply -target=module.vpc
terraform apply -target=module.control
```

### Backend Issues
```bash
# Verify backend configuration
terraform init -backend-config="bucket=your-bucket"

# Reconfigure backend
terraform init -reconfigure
```

## 📦 Packer Issues

### Build Failures
```bash
# Debug packer build
PACKER_LOG=1 packer build -var-file=variables.pkrvars.hcl kubernetes-control.pkr.hcl

# Validate configuration
packer validate -var-file=variables.pkrvars.hcl kubernetes-control.pkr.hcl

# Check AWS credentials
aws sts get-caller-identity
```

### AMI Registration Issues
```bash
# Check if AMI exists
aws ec2 describe-images --owners self --filters "Name=name,Values=kubernetes-control-*"

# Deregister old AMI if needed
aws ec2 deregister-image --image-id ami-xxxxxxxxx
```

## ⚙️ kubeadm Issues

### Cluster Initialization Failures
```bash
# Check kubeadm logs on control plane
sudo journalctl -u kubelet -f
sudo kubeadm reset  # Reset if needed

# Check system requirements
sudo kubeadm config images list
sudo kubeadm config images pull
```

### Node Join Failures
```bash
# Generate new join token
sudo kubeadm token create --print-join-command

# Check join token validity
sudo kubeadm token list

# Debug join process
sudo kubeadm join --v=5 <control-plane-endpoint>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
```

### Certificate Issues
```bash
# Check certificate expiration
sudo kubeadm certs check-expiration

# Renew certificates
sudo kubeadm certs renew all

# Verify API server certs
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout
```

## 🎛️ kubectl Issues

### Connection Problems
```bash
# Check kubeconfig
kubectl config view
kubectl config current-context

# Test API server connectivity
kubectl cluster-info
kubectl get --raw /healthz

# Check certificates
kubectl config view --raw | grep certificate-authority-data | cut -d' ' -f6 | base64 -d | openssl x509 -text -noout
```

### Permission Issues
```bash
# Check user permissions
kubectl auth can-i --list
kubectl auth can-i create pods

# Check RBAC
kubectl get clusterrolebindings
kubectl describe clusterrolebinding cluster-admin
```

## 🐳 crictl Issues

### Container Runtime Problems
```bash
# Check containerd status
sudo systemctl status containerd
sudo crictl info

# List containers and images
sudo crictl ps -a
sudo crictl images

# Check container logs
sudo crictl logs <container-id>

# Debug pod issues
sudo crictl pods
sudo crictl inspectp <pod-id>
```

### Runtime Configuration
```bash
# Check crictl configuration
sudo crictl config --help
cat /etc/crictl.yaml

# Set runtime endpoint
sudo crictl config runtime-endpoint unix:///run/containerd/containerd.sock
```

## 🌐 calicoctl Issues

### Network Policy Problems
```bash
# Check Calico status
calicoctl node status
calicoctl get nodes

# Check IP pools
calicoctl get ippools -o wide

# Network policy debugging
calicoctl get networkpolicies --all-namespaces
calicoctl get globalnetworkpolicies
```

### BGP Issues
```bash
# Check BGP peers (if BGP enabled)
calicoctl get bgppeer
calicoctl node status

# Check routes
ip route show
calicoctl get ippool -o yaml
```

## 🗄️ etcdctl Issues

### etcd Cluster Problems
```bash
# Check etcd cluster health
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint health

# List etcd members
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  member list

# Check etcd status
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint status --write-out=table
```

### etcd Data Issues
```bash
# Backup etcd
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save /tmp/etcd-backup.db

# Check etcd logs
sudo journalctl -u etcd -f
```

## 🚨 Common Error Patterns

### "connection refused" Errors
1. Check if service is running: `sudo systemctl status <service>`
2. Verify firewall/security groups allow the port
3. Check if process is listening: `sudo netstat -tlnp | grep <port>`

### "certificate signed by unknown authority"
1. Check CA certificate in kubeconfig
2. Verify certificate SANs include the endpoint you're using
3. Check certificate expiration: `kubeadm certs check-expiration`

### "unable to connect to the server"
1. Check API server status: `kubectl get --raw /healthz`
2. Verify NLB health checks are passing
3. Check control plane node status

### "pod has unbound immediate PersistentVolumeClaims"
1. Check if EBS CSI driver is installed
2. Verify storage class exists: `kubectl get storageclass`
3. Check PVC status: `kubectl get pvc`

## 🔍 Log Locations

### System Logs
```bash
# Kubelet logs
sudo journalctl -u kubelet -f

# Containerd logs
sudo journalctl -u containerd -f

# System messages
sudo tail -f /var/log/syslog
```

### Kubernetes Logs
```bash
# API server logs
sudo tail -f /var/log/pods/kube-system_kube-apiserver-*/*.log

# etcd logs
sudo tail -f /var/log/pods/kube-system_etcd-*/*.log

# Control manager logs
sudo tail -f /var/log/pods/kube-system_kube-controller-manager-*/*.log
```

## 🛠️ Recovery Procedures

### Reset Single Node
```bash
# On the problematic node
sudo kubeadm reset
sudo systemctl stop kubelet
sudo systemctl stop containerd
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/kubelet/
sudo rm -rf /etc/cni/net.d/
sudo systemctl start containerd
sudo systemctl start kubelet
```

### Recreate Cluster
```bash
# Destroy infrastructure
terraform destroy

# Clean up local state if needed
rm -rf .terraform/
rm terraform.tfstate*

# Redeploy
terraform init
terraform apply
```

## 📞 Getting Help

### Useful Commands for Support
```bash
# Gather cluster information
kubectl cluster-info dump > cluster-info.txt

# Get node information
kubectl describe nodes > nodes-info.txt

# Get all events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' > events.txt

# System information
uname -a > system-info.txt
docker version >> system-info.txt
kubectl version >> system-info.txt
```

### Log Collection Script
```bash
#!/bin/bash
# Create troubleshooting bundle
mkdir -p troubleshooting-$(date +%Y%m%d-%H%M)
cd troubleshooting-$(date +%Y%m%d-%H%M)

kubectl cluster-info dump > cluster-dump.yaml
kubectl get nodes -o wide > nodes.txt
kubectl get pods --all-namespaces > pods.txt
kubectl get events --all-namespaces --sort-by='.lastTimestamp' > events.txt
sudo journalctl -u kubelet --since "1 hour ago" > kubelet.log
sudo journalctl -u containerd --since "1 hour ago" > containerd.log

echo "Troubleshooting bundle created in $(pwd)"
```

Remember to check the specific error messages and logs for your particular issue. This guide covers the most common problems encountered during cluster setup and operation.
