#!/bin/bash
# Minimal startup script - only installs essential packages and services

export HOME=/home/ubuntu

# Update and install essential packages
apt-get update
apt-get install -y python3-venv python3-pip curl nginx

# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Create .ollama directory with correct permissions
mkdir -p /home/ubuntu/.ollama
chown -R ubuntu:ubuntu /home/ubuntu/.ollama

# Configure Ollama service to run as ubuntu user
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
User=ubuntu
Group=ubuntu
Environment="HOME=/home/ubuntu"
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
EOF

# Start Ollama
systemctl daemon-reload
systemctl enable ollama
systemctl start ollama

# Create Python virtual environment
sudo -u ubuntu python3 -m venv /home/ubuntu/.venv
sudo -u ubuntu /home/ubuntu/.venv/bin/python3 -m pip install --upgrade pip
sudo -u ubuntu /home/ubuntu/.venv/bin/python3 -m pip install flask requests boto3 psutil

echo "Basic setup complete. Run deploy.sh to configure the application."