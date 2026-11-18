# Module 4 Lab Guide — Production Ops (CI/CD, Probes & Autoscaling)

This directory contains the hands-on Kubernetes manifests, automated test suites, and CI/CD workflow for **Module 4**.

---

## Directory Structure

```text
Module-4/lab/
├── .github/
│   └── workflows/
│       └── ci.yml                     # GitHub Actions CI/CD pipeline (lint → test → build → deploy)
├── k8s/
│   ├── assistant-deployment.yaml      # Deployment with liveness/readiness probes & CPU requests
│   ├── assistant-service.yaml         # NodePort Service exposing port 8501 on port 30501
│   ├── assistant-ingress.yaml         # Ingress routing http://aiops.local to the Service
│   └── assistant-hpa.yaml             # Horizontal Pod Autoscaler (scales 2 -> 5 replicas at 70% CPU)
├── tests/                             # Test suite executed by CI/CD before any deployment
│   ├── test_api_endpoint.py           # Verifies Streamlit /_stcore/health endpoint
│   ├── test_chunking.py               # Verifies RAG document chunking
│   ├── test_db_query.py               # Verifies ChromaDB vector storage & similarity search
│   ├── test_embeddings.py             # Verifies embedding vector dimensions (384-dim)
│   └── test_golden_dataset.py         # Golden dataset ML regression test (accuracy >= 80%)
└── README.md                          # This lab execution guide
```

---

## Frequently Asked Questions (FAQ)

### 1. Where did `image: module2-assistant:latest` come from? Did we build this in Module 2?
**Yes.** In **Module 2 Lesson 04** (`Module-2/lab/Dockerfile`), you packaged the Streamlit RAG assistant into a Docker image.
* **If testing on local nodes (Vagrant / Minikube):** The image was built as `module2-assistant:latest` (or imported into containerd with `sudo ctr -n k8s.io images import /vagrant/image.tar`). `imagePullPolicy: IfNotPresent` ensures Kubernetes uses this local image without attempting to pull from Docker Hub.
* **If deploying via CI/CD (Module 4):** The GitHub Actions pipeline in `.github/workflows/ci.yml` builds and pushes the image to Docker Hub, then automatically updates the deployment image tag using `kubectl set image`.

---

### 2. Why do we need `assistant-service.yaml` and where is it?
A Kubernetes `Deployment` only manages the Pod lifecycle. **Pods have ephemeral IP addresses** that change whenever a pod restarts or scales.
* **The Service (`assistant-service.yaml`)** provides a stable internal IP (`aiops-assistant-service:8501`) and exposes **NodePort `30501`**.
* **Why NodePort 30501 matters:** In Lesson 04, the synthetic load generator (`hey`) sends traffic directly to `http://<worker-ip>:30501/` to drive CPU up and trigger autoscaling. Without this Service, the load tester cannot reach the pods.

---

### 3. Do we need Ingress (`assistant-ingress.yaml`)?
* **For basic access & load testing:** No, the NodePort service (`http://<node-ip>:30501`) is sufficient.
* **For production-like domain routing:** Yes! Ingress (`assistant-ingress.yaml`) routes domain names (e.g., `http://aiops.local`) to `aiops-assistant-service:8501` via the NGINX Ingress Controller configured in Module 3. Both options are provided in `k8s/` so you can use either method.

---

### 4. How does GitHub Actions reach our local Vagrant VMs? Do we need a self-hosted runner?
**Yes!** By default, GitHub Actions runners (`ubuntu-latest`) execute in GitHub's cloud and **cannot reach private local IP addresses** like `192.168.56.24:6443` on your laptop.

To bridge this securely without opening public firewall ports, we run a **GitHub Actions Self-Hosted Runner** directly on the **`master` VM** (or via a containerized runner):
1. The runner connects outward to GitHub via HTTPS and listens for jobs.
2. In `.github/workflows/ci.yml`, the `deploy` job sets `runs-on: [self-hosted, k8s]`.
3. When triggered, the runner executes `kubectl set image` locally inside the VM with native cluster access!

See [Lesson 01 Step 3](../01-cicd-pipeline.md) or run `./setup-runner.sh` inside the `master` VM to configure it in minutes.

---

## Quick Start — Applying the Lab Manifests

### Step 1: Apply the Deployment, Service, and Ingress
On your Kubernetes control plane node (or via configured `kubectl`):

```bash
# 1. Deploy the assistant with health probes & CPU requests
kubectl apply -f k8s/assistant-deployment.yaml

# 2. Expose the assistant via NodePort 30501
kubectl apply -f k8s/assistant-service.yaml

# 3. (Optional) Enable host-based routing (http://aiops.local)
kubectl apply -f k8s/assistant-ingress.yaml
```

### Step 2: Verify Deployment and Health Probes
```bash
# Verify pods are Running and passing readiness probes (1/1)
kubectl get pods -l app=aiops-assistant

# Verify the Service is listening on NodePort 30501
kubectl get svc aiops-assistant-service
```

### Step 3: Configure and Apply HPA (Autoscaler)
```bash
# Apply the declarative HPA manifest
kubectl apply -f k8s/assistant-hpa.yaml

# Verify HPA is monitoring CPU
kubectl get hpa aiops-assistant-hpa
```
*Expected output:*
```text
NAME                  REFERENCE                               TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
aiops-assistant-hpa   Deployment/aiops-assistant-deployment   15%/70%   2         5         2          30s
```

### Step 4: Run the HPA Load Test
From your host machine, generate traffic to NodePort `30501`:
```bash
hey -n 2000 -c 50 http://<WORKER_NODE_IP>:30501/
```

In a separate terminal, watch the pods scale automatically from 2 to 5:
```bash
kubectl get hpa aiops-assistant-hpa --watch
```
