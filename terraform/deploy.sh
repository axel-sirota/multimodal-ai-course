#!/bin/bash
# Deploy script to configure Ollama instance after terraform apply
# Usage: ./deploy.sh <instance-hostname-or-ip>

set -e

# Check if hostname/IP is provided
if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh <instance-hostname-or-ip>"
    echo "Example: ./deploy.sh ec2-XX-XX-XX-XX.compute-1.amazonaws.com"
    exit 1
fi

INSTANCE_HOST=$1
SSH_KEY="${SSH_KEY:-~/.ssh/default_pem.pem}"
API_TOKEN="${API_TOKEN:-4cbd67c87dd9080c464f0427547942eee4b1a9b76ddf6eec241f0ca60fbea2db}"

echo "=== Deploying to $INSTANCE_HOST ==="
echo "Using SSH key: $SSH_KEY"

# Check SSH connectivity
echo "Checking SSH connectivity..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$INSTANCE_HOST" "echo 'SSH connection successful'" || {
    echo "Failed to connect via SSH. Please check:"
    echo "1. Instance is running"
    echo "2. Security group allows SSH on port 22"
    echo "3. SSH key path is correct"
    exit 1
}

# Copy application files to instance
echo "Copying application files..."
scp -i "$SSH_KEY" files/ollama_server.py ubuntu@"$INSTANCE_HOST":/home/ubuntu/
scp -i "$SSH_KEY" files/nginx.conf ubuntu@"$INSTANCE_HOST":/tmp/
scp -i "$SSH_KEY" files/ollama-app.service ubuntu@"$INSTANCE_HOST":/tmp/
scp -i "$SSH_KEY" files/ollama-override.conf ubuntu@"$INSTANCE_HOST":/tmp/

# Configure instance
echo "Configuring instance..."
ssh -i "$SSH_KEY" ubuntu@"$INSTANCE_HOST" << 'REMOTE_SCRIPT'
set -e

echo "=== Starting remote configuration ==="

# Ensure Ollama directory exists with correct permissions
echo "Setting up Ollama directory..."
sudo mkdir -p /home/ubuntu/.ollama
sudo chown -R ubuntu:ubuntu /home/ubuntu/.ollama

# Configure Ollama service to run as ubuntu user
echo "Configuring Ollama service..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo cp /tmp/ollama-override.conf /etc/systemd/system/ollama.service.d/override.conf
sudo systemctl daemon-reload

# Stop nginx temporarily to avoid port conflicts
echo "Stopping nginx temporarily..."
sudo systemctl stop nginx 2>/dev/null || true

# Restart Ollama with correct configuration
echo "Starting Ollama service..."
sudo systemctl restart ollama
sleep 5

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "Ollama is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Configure nginx on port 80
echo "Configuring nginx..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo cp /tmp/nginx.conf /etc/nginx/sites-available/ollama
sudo ln -sf /etc/nginx/sites-available/ollama /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Install Python app service
echo "Installing Python app service..."
sudo cp /tmp/ollama-app.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ollama-app
sudo systemctl restart ollama-app

# Wait for services to stabilize
sleep 5

# Check service status
echo ""
echo "=== Service Status ==="
echo "Ollama:" 
sudo systemctl is-active ollama || echo "NOT RUNNING"
echo "Python App:" 
sudo systemctl is-active ollama-app || echo "NOT RUNNING"
echo "Nginx:" 
sudo systemctl is-active nginx || echo "NOT RUNNING"

# Test endpoints
echo ""
echo "=== Testing Endpoints ==="
echo "Testing Ollama directly..."
curl -s http://localhost:11434/api/tags | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'Models: {len(data.get(\"models\", []))} loaded')" || echo "Ollama test failed"

echo "Testing Python app..."
curl -s http://localhost:8080/health | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'Status: {data.get(\"status\", \"unknown\")}')" || echo "Python app test failed"

echo ""
echo "=== Deployment Complete ==="
REMOTE_SCRIPT

echo ""
echo "=== Local Deployment Complete ==="
echo ""
echo "Instance URL: http://$INSTANCE_HOST"
echo ""
echo "Test endpoints:"
echo "  curl http://$INSTANCE_HOST/health"
echo "  curl http://$INSTANCE_HOST/metrics"
echo ""
echo "Initialize models (this will take a few minutes):"
echo "  curl -X POST -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "       http://$INSTANCE_HOST/startup"
echo ""
echo "Run inference:"
echo "  curl -X POST -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "       -H \"Content-Type: application/json\" \\"
echo "       -d '{\"prompt\": \"What is AI?\"}' \\"
echo "       http://$INSTANCE_HOST/think"
echo ""
echo "Monitor logs:"
echo "  aws logs tail /aws/ec2/ollama-course --follow --region us-east-1"