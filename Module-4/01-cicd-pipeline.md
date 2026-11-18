# 01 — CI/CD Pipeline with GitHub Actions

In Module 3, you deployed the AIOps assistant manually by running `kubectl apply` commands from the master node. While this works in a lab, manually deploying to production is dangerous. One typo, one forgotten step, and you can bring the system down. In this lesson, you will build an automated **CI/CD pipeline** using GitHub Actions that runs on every push: linting your code, running your tests, building a Docker image, pushing it to a container registry, and deploying to Kubernetes — all without human intervention.

---

## What is CI/CD?

**Continuous Integration (CI)** and **Continuous Deployment (CD)** are practices that automate the process of getting code from a developer's laptop into production.

| Phase | What Happens | Goal |
|---|---|---|
| **CI (Continuous Integration)** | On every push: code is linted, tests are run, and artifacts (Docker images) are built. | Catch bugs before they reach production. |
| **CD (Continuous Deployment)** | On successful CI: the new artifact is automatically deployed to the staging or production environment. | Ship changes rapidly and reliably. |

The entire sequence is called a **pipeline**:

```
  git push → Lint → Unit Tests → Integration Tests → Build Docker Image → Push to Registry → Deploy to K8s
```

---

## GitHub Actions Fundamentals

GitHub Actions is a CI/CD platform built into GitHub. Workflows are defined as YAML files inside the `.github/workflows/` directory of your repository.

### Key Concepts

| Concept | Description |
|---|---|
| **Workflow** | An automated process defined in a YAML file, triggered by events (push, PR, schedule). |
| **Job** | A set of steps that execute on the same runner (virtual machine). |
| **Step** | A single task within a job: running a script, checking out code, or using an action. |
| **Runner** | The machine that executes the job (GitHub-hosted like `ubuntu-latest`, or self-hosted). |
| **Action** | A reusable unit of code (e.g., `actions/checkout@v4` to clone your repo). |

---

## Lab: Building the CI Pipeline

### Step 1: Create the Workflow File

In your AIOps assistant repository, create the following directory structure and file:

```bash
mkdir -p .github/workflows
```

Create `.github/workflows/ci.yml`:

```yaml
name: AIOps Assistant CI/CD Pipeline

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  lint:
    name: Lint Code
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install linter
        run: pip install flake8

      - name: Run flake8
        run: flake8 app/ --max-line-length=120 --statistics

  test:
    name: Run Tests
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest

      - name: Run unit and integration tests
        run: pytest tests/ -v --tb=short

  build:
    name: Build & Push Docker Image
    needs: test
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && (github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master')
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ secrets.DOCKER_USERNAME }}/aiops-assistant:${{ github.sha }}
            ${{ secrets.DOCKER_USERNAME }}/aiops-assistant:latest

  deploy:
    name: Deploy to Kubernetes
    needs: build
    # For local VM / Vagrant clusters: use self-hosted runner installed on the master VM.
    # The runner runs inside your private network and has direct kubectl access to the cluster.
    # (If using a public cloud cluster like EKS/GKE/AKS, change to: ubuntu-latest)
    runs-on: [self-hosted, k8s]
    if: github.event_name == 'push' && (github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master')
    environment: production
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Update deployment image
        run: |
          kubectl set image deployment/aiops-assistant-deployment \
            assistant=${{ secrets.DOCKER_USERNAME }}/aiops-assistant:${{ github.sha }}

      - name: Wait for rollout to complete
        run: kubectl rollout status deployment/aiops-assistant-deployment --timeout=120s
```

### Step 2: Understanding the Pipeline Flow

```mermaid
graph LR
    A["git push"] --> B["Lint (flake8)"]
    B --> C["Test (pytest)"]
    C --> D["Build Docker Image"]
    D --> E["Push to Docker Hub"]
    E --> F["Deploy to K8s"]
    F --> G["Rollout Status Check"]
```

Each job has a `needs` dependency, meaning:
- **`test`** will not run unless **`lint`** passes.
- **`build`** will not run unless **`test`** passes.
- **`deploy`** will not run unless **`build`** passes.

If any step fails, the entire pipeline **stops**, preventing broken code from reaching production.

---

### Step 3: Connecting GitHub to Kubernetes (Self-Hosted Runner vs Cloud Runner)

A crucial real-world question arises when deploying to Kubernetes:

> **"Does GitHub Actions know where my local Kubernetes cluster is, or can it deploy directly to my Vagrant VMs?"**

The short answer is **No**:
* **GitHub's cloud runners (`ubuntu-latest`)** execute in Microsoft Azure data centers.
* Your Kubernetes cluster in Module 3 runs on **VirtualBox VMs with private IPs** (e.g., `192.168.56.24:6443`).
* Because `192.168.x.x` is a private, non-routable address behind your home/office NAT, a cloud runner cannot reach your master VM over the public internet.

```
[ GitHub Cloud Runner (ubuntu-latest) ]
              │
              │  kubectl set image ... (to https://192.168.56.24:6443)
              ▼
       ❌ CONNECTION TIMEOUT
       (Public cloud runner cannot reach private RFC-1918 local IPs)
```

#### The Solution: GitHub Self-Hosted Runner on the `master` VM

Instead of opening firewall ports or buying public domain names, you run a **GitHub Actions Self-Hosted Runner directly on your cluster's `master` node**:

```
[ GitHub Cloud ]
      ▲
      │ (1) Persistent OUTBOUND poll: Runner listens for jobs
      │     (No inbound firewall ports, no public IP needed!)
      │
[ Vagrant VM: master (192.168.56.24) ]
  ┌─────────────────────────────────────────────────────────┐
  │ Self-Hosted Runner (runs-on: [self-hosted, k8s])        │
  │   └── Executes: kubectl set image ...                   │
  │       (Talks to localhost:6443 natively!)               │
  └───────────────────────────┬─────────────────────────────┘
                              │
                              ▼
            Kubernetes Cluster Rollout (Zero network friction!)
```

#### How to Set Up the Runner on the Master VM (3 Minutes):

1. **SSH into the master node:**
   ```bash
   cd Module-3/lab
   vagrant ssh master
   ```

2. **Register the runner with GitHub:**
   In your GitHub repository, open **Settings** → **Actions** → **Runners** → Click **New self-hosted runner** → Select **Linux** / **x64**. Copy and run the generated commands inside the `master` VM:
   ```bash
   mkdir -p actions-runner && cd actions-runner
   curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
   tar xzf actions-runner-linux-x64-2.321.0.tar.gz

   # Replace with your repository URL and token from the GitHub UI:
   ./config.sh --url https://github.com/YOUR_USERNAME/aiops-assistant --token YOUR_TOKEN --labels self-hosted,k8s --unattended
   ```

3. **Start the runner service:**
   ```bash
   sudo ./svc.sh install vagrant
   sudo ./svc.sh start
   ```
   *(The runner is now running in the background and ready to accept deployment jobs!)*

> [!TIP]
> **Containerized Runner Pattern:** You can also run the runner as a Docker container mounting `/home/vagrant/.kube:/root/.kube:ro`. This is the exact enterprise pattern used for containerized runners, where the runner container has `kubectl` pre-installed and registers dynamically on boot via GitHub PAT tokens.

---

### Step 4: Configure GitHub Secrets

Navigate to your GitHub repository → **Settings** → **Secrets and variables** → **Actions**, and create the following secrets:

| Secret Name | Value | Purpose |
|---|---|---|
| `DOCKER_USERNAME` | Your Docker Hub username | Authenticating to Docker Hub |
| `DOCKER_PASSWORD` | Docker Hub Access Token | Pushing the built container image |
| `KUBE_CONFIG` | *(Optional - only needed if deploying via cloud `ubuntu-latest` to an EKS/GKE cluster)* | Base64-encoded kubeconfig |

---

### Step 5: The Manual Approval Gate

Notice the `environment: production` line in the deploy job. In GitHub, you can configure **Environment Protection Rules** that require a manual approval before deployment proceeds:

1. Go to **Settings** → **Environments** → **New environment** → Name it `production`.
2. Check **Required reviewers** and add yourself (or a teammate).
3. Now when the pipeline reaches the `deploy` job, it will pause and wait for a human to click **"Approve"** before deploying to the cluster.

This is a critical safety net for production systems!

---

## Understanding Pipeline Dependencies

The `needs` keyword creates a **Directed Acyclic Graph (DAG)** of job dependencies:

| Job | Depends On | Runs When |
|---|---|---|
| `lint` | — | Every push and PR |
| `test` | `lint` | Only if lint passes |
| `build` | `test` | Only on `main` branch push, after tests pass |
| `deploy` | `build` | Only on `main` branch push, after image is built |

---

## What's Next

You have a pipeline, but it runs `pytest tests/` — and the `tests/` directory doesn't exist yet! In the next lesson, we will write **5 automated tests** covering unit tests, integration tests, and a golden dataset ML accuracy test.
