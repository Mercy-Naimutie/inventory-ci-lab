# Lab runbook - commands in order

Your completed project is in `C:\Users\TOTONA\Downloads\Jenkins_WSL_Student_Starter\jenkins_wsl_lab_starter`.
Run everything below in the **Ubuntu (WSL2)** terminal unless it says PowerShell.
Replace `YOUR_USER` with your GitHub username.

## 0. One-time platform setup (skip what you already have)

PowerShell (Admin):
```powershell
wsl --install -d Ubuntu-24.04
wsl --update
wsl --list --verbose          # VERSION must be 2
```
Ubuntu:
```bash
printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf
```
PowerShell: `wsl --shutdown`, reopen Ubuntu, then:
```bash
ps -p 1 -o comm=              # must print: systemd
sudo apt update
sudo apt install -y git curl wget unzip ca-certificates fontconfig openjdk-21-jre python3 python3-venv python3-pip
```

Docker - **either** Docker Desktop (Settings > Resources > WSL Integration > enable Ubuntu-24.04)
**or** native Docker Engine (not both):
```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER && newgrp docker
docker run --rm hello-world
```

Jenkins LTS:
```bash
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
sudo apt update && sudo apt install -y jenkins
sudo systemctl enable --now jenkins
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```
Open http://localhost:8080 > *Install suggested plugins* > create your own admin user.
Check *Manage Jenkins > Plugins > Installed*: Pipeline, Git, JUnit, Timestamper.

Let Jenkins use Docker (local lab only):
```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
sudo -u jenkins docker ps      # must NOT say permission denied
```

**Evidence (versions screenshot):**
```bash
java -version; jenkins --version; docker version --format '{{.Server.Version}}'; python3 --version; git --version
```

## 1. Copy the project into the Linux filesystem

```bash
mkdir -p ~/projects
cp -r /mnt/c/Users/TOTONA/Downloads/Jenkins_WSL_Student_Starter/jenkins_wsl_lab_starter ~/projects/inventory-ci-lab
cd ~/projects/inventory-ci-lab
find . -type f \( -name '*.sh' -o -name Jenkinsfile -o -name '*.py' \) -exec sed -i 's/\r$//' {} +   # strip any CRLF
chmod +x scripts/*.sh
```

## 2. Task A - verify locally

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/ruff check app tests          # All checks passed!
.venv/bin/python -m pytest -v           # 18 passed

docker build -t inventory-api:manual .
docker run -d --name inventory-manual -p 127.0.0.1:5050:5000 inventory-api:manual
sleep 2
curl -i http://127.0.0.1:5050/health
curl -i "http://127.0.0.1:5050/api/items/low-stock?threshold=5"
curl -i "http://127.0.0.1:5050/api/items/low-stock?threshold=abc"
curl -i http://127.0.0.1:5050/api/items/999
docker exec inventory-manual id          # uid=10001(appuser)
docker rm -f inventory-manual
```

Checkpoint answer (port 5050 vs 5000): Gunicorn listens on port 5000 *inside the container's own network
namespace*. `-p 127.0.0.1:5050:5000` tells Docker to forward host loopback port 5050 to container port 5000,
so the two numbers belong to different namespaces and can differ; binding to 127.0.0.1 keeps it off the LAN.

## 3. Push to GitHub

Create an empty repo `inventory-ci-lab` on GitHub (no README), then:
```bash
git config --global user.name  "Your Name"
git config --global user.email "mercynaimutie@gmail.com"
git init -b main
git add .
git commit -m "Inventory API: low-stock endpoint, lint stage, hardened image, deploy with rollback"
git remote add origin https://github.com/YOUR_USER/inventory-ci-lab.git
git push -u origin main        # password prompt = a GitHub Personal Access Token, never your password
```

## 4. Create the Jenkins job

*New Item* > name `InventoryPipeline` > *Pipeline* > OK.
Pipeline section: *Pipeline script from SCM* > SCM *Git* > Repository URL `https://github.com/YOUR_USER/inventory-ci-lab.git`
> Branch `*/main` > Script Path `Jenkinsfile` > Save > **Build Now**.

**Evidence:** Stage View all green; *Test Result* page (18 tests); console log of the smoke-test stage
(shows `container uid=10001`, `OK: 'pytest' not installed in image`); then:
```bash
curl -i http://127.0.0.1:5050/
curl -i "http://127.0.0.1:5050/api/items/low-stock?threshold=5"
```

## 5. Challenge 2 - failure gate

```bash
sed -i "s/status='ok'), 200/status='broken'), 200/" app/main.py
git commit -am "BUG: health returns wrong status (failure-gate demo)"
git push
git rev-parse --short HEAD     # commit ID #1 for the report
```
Build Now > **screenshot**: *Unit tests* red, *Build image / smoke test / Deploy* not run (grey/skipped),
JUnit shows `test_health` failed. Also show `curl http://127.0.0.1:5050/` still returns the previous version.

```bash
sed -i "s/status='broken'), 200/status='ok'), 200/" app/main.py
git commit -am "Fix health status"
git push
git rev-parse --short HEAD     # commit ID #2
```
Build Now > **screenshot** all green + JUnit trend graph (fail then pass).

## 6. Challenge 3 - rollback evidence

After a green build (inventory-live exists):
```bash
cd ~/projects/inventory-ci-lab
bash scripts/test-rollback.sh 2>&1 | tee rollback-evidence.txt
```
Expected tail:
```
[deploy] Post-deployment validation FAILED for inventory-api:broken - rolling back
[deploy] ROLLBACK OK - restored inventory-api:<N>
RESULT: PASS - inventory-api:<N> was restored and is healthy
```
Screenshot it / paste it in the report (do not commit `rollback-evidence.txt` unless you want to).

Manual rollback demo (optional): `bash scripts/deploy.sh inventory-api:<older build number>`.

## 7. Challenge 5 - fresh clone

```bash
rm -rf /tmp/fresh && git clone https://github.com/YOUR_USER/inventory-ci-lab.git /tmp/fresh && cd /tmp/fresh
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt && .venv/bin/python -m pytest -q
```
Screenshot `18 passed`.

## 8. Bonus (optional)

- **Multibranch (10 pts):** New Item > *Multibranch Pipeline* > Branch Source GitHub/Git > same repo.
  ```bash
  git checkout -b feature/demo && git commit --allow-empty -m "feature branch demo" && git push -u origin feature/demo
  ```
  Scan repository > the `feature/demo` build shows *Deploy locally* **skipped**; `main` deploys.
- **Lock/scan (10 pts):** already in the pipeline - see *Build Artifacts* `reports/runtime-lock.txt`.
  For a real scan install Trivy once, then rebuild:
  ```bash
  sudo apt install -y wget gnupg
  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
  sudo apt update && sudo apt install -y trivy
  ```

## 9. Submission checklist

- [ ] GitHub URL (repo public, or instructor added)
- [ ] Screenshots: versions, green pipeline, failed Unit tests stage with later stages skipped, JUnit results, live `curl` response
- [ ] Both Challenge 2 commit IDs
- [ ] Rollback evidence (`test-rollback.sh` output) + cutover explanation (README "Deployment and rollback")
- [ ] Architecture diagram + Docker-socket risk (README)
- [ ] Fresh-clone test output
- [ ] No tokens/passwords anywhere (repo, screenshots, report)
- [ ] 3-5 page PDF report
