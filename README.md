<div align="center">

#  Automated CI/CD Pipeline for a Java Web Application

### Jenkins • Maven • Docker • Apache Tomcat • AWS EC2

An end-to-end, production-style CI/CD pipeline that takes a Java `.war` application from a `git push` to a running, containerized service — with zero manual intervention.

![Build Status](https://img.shields.io/badge/build-passing-brightgreen?style=for-the-badge&logo=jenkins&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Containerized-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EC2-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![Java](https://img.shields.io/badge/Java-11-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Maven](https://img.shields.io/badge/Maven-3.9.3-C71A36?style=for-the-badge&logo=apachemaven&logoColor=white)


</div>

---

##  Table of Contents

- [Overview](#-overview)
- [Architecture & Pipeline Flow](-architecture--pipeline-flow)
- [Pipeline in Action (Screenshots)](#-pipeline-in-action)
- [Tech Stack & Prerequisites](-tech-stack--prerequisites)
- [Step-by-Step Implementation](#-step-by-step-implementation)
- [Application Access](#-application-access)
- [Troubleshooting & Lessons Learned](#-troubleshooting--lessons-learned)
- [Future Roadmap](#-future-roadmap)
- [Author](#-author)

---

##  Overview

This project automates the full build-and-release lifecycle of a **Java Registration Web Application**:

1. **Jenkins** pulls the latest source from GitHub the moment a commit lands.
2. **Maven** compiles the code and packages it into a deployable `registration-app.war`.
3. The artifact is securely shipped to a remote host via **Publish Over SSH**.
4. **Docker** bakes the artifact into a custom **Tomcat** image and (re)launches the container — live, in seconds.

No manual builds. No manual deployments. Just `git push` → running app.

---

##  Architecture & Pipeline Flow
<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/79a65946-68ca-43c1-a762-673b4d28583c" />



| Stage | What Happens |
|:---:|---|
| **1. Source Control** | Jenkins pulls code from GitHub (`registration-app`) |
| **2. Build Phase** | Maven compiles the source and packages `registration-app.war` |
| **3. Artifact Transfer** | Jenkins ships the `.war` to the remote Docker Host over SSH |
| **4. Deployment Phase** | Docker builds a custom Tomcat image and (re)launches the container |

---

##  Pipeline in Action

> Screenshots live in `docs/screenshots/`. The captions below tell you exactly which image from your PDF maps to each file.

<!-- Screenshot 1: AWS Console "Instances (2)" panel — JENKINS-SERV... and Docker-Host, both Running,
     plus the VPC / Subnets / Route Tables / Network Connections diagram beneath it. -->
###  Live AWS Infrastructure
![alt text](image-2.png)
![alt text](image-3.png)





###  Network Security Configuration
![alt text](image-5.png)

###  Successful Jenkins Build
![alt text](image-7.png)
![alt text](image-8.png)


###  Tomcat Container Verified
![alt text](image-9.png)
###  Application Live in Production
![alt text](image-10.png)

##  Tech Stack & Prerequisites

### Tech Stack

| Category | Tool | Details |
|---|---|---|
| ☁️ Cloud Provider | AWS EC2 | 2× `t3.micro` instances |
| ⚙️ CI/CD Automation | Jenkins | Freestyle project |
| ☕ Language Runtime | OpenJDK / Amazon Corretto | Java 11 |
| 📦 Build Tool | Apache Maven | 3.9.3 |
| 🐳 Containerization | Docker | Latest |
| 🐱 Application Server | Apache Tomcat | Latest (official image) |
| 🔑 Deployment Transport | Publish Over SSH (Jenkins plugin) | RSA key auth |
| 🖥️ Jenkins Node OS | Amazon Linux 2 | |
| 🖥️ Docker Host OS | Ubuntu | |
| 🔀 Source Control | Git / GitHub | [`registration-app`](https://github.com/Ashfaque-9x/registration-app) |

### Prerequisites

- An AWS account with permissions to launch EC2 instances and manage security groups
- Two EC2 instances: one for **Jenkins** (Amazon Linux 2), one as the **Docker Host** (Ubuntu)
- Security group rules allowing inbound `22` (SSH), `8080` (Jenkins UI), and `8086` (deployed app)
- An SSH key pair configured for Jenkins → Docker Host communication
- A GitHub repository containing the Java web application source
- Basic familiarity with Jenkins, Docker, and Linux shell administration

---

## Step-by-Step Implementation

### 1️⃣ Jenkins Server Setup (Amazon Linux 2)

```bash
# Update the system and install the Java 11 JDK (includes javac)
sudo yum update -y
sudo amazon-linux-extras install java-openjdk11 -y
sudo yum install java-11-amazon-corretto-devel -y

# Install and enable Jenkins
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum install jenkins -y

sudo systemctl enable --now jenkins
sudo systemctl status jenkins

# Sanity checks
java -version
javac -version
```

### 2️⃣ Maven Installation & Environment Configuration

```bash
# Download and install Maven under /opt
cd /opt
sudo wget https://dlcdn.apache.org/maven/maven-3/3.9.3/binaries/apache-maven-3.9.3-bin.tar.gz
sudo tar -xzvf apache-maven-3.9.3-bin.tar.gz
sudo mv apache-maven-3.9.3 maven
```

Add the following to `~/.bash_profile`:

```bash
M2_HOME=/opt/maven
M2=/opt/maven/bin
JAVA_HOME=/usr/lib/jvm/java-11-openjdk-11.0.19.0.7-1.amzn2.0.1.x86_64
PATH=$PATH:$HOME/bin:$JAVA_HOME:$M2_HOME:$M2
```

```bash
source ~/.bash_profile
mvn -v
```

> 💡 Register this same path as **`MAVEN_HOME: /opt/maven`** under *Jenkins → Global Tool Configuration → Maven Installations*.

### 3️⃣ Docker Host Setup (Ubuntu)

```bash
# Install Docker and grant the ubuntu user permission to use it
sudo apt update && sudo apt-get update
sudo apt install docker.io -y
sudo usermod -aG docker ubuntu

# Create the deployment directory Jenkins will publish artifacts into
sudo mkdir -p /opt/Docker
sudo chown -R ubuntu:ubuntu /opt/Docker
```

### 4️⃣ Dockerfile

Located at `/opt/Docker/Dockerfile` on the Docker Host:

```dockerfile
FROM tomcat:latest

# Enable the manager/examples webapps
RUN cp -R /usr/local/tomcat/webapps.dist/* /usr/local/tomcat/webapps

# Drop the freshly-built artifact straight into Tomcat's webapps directory
COPY ./*.war /usr/local/tomcat/webapps/
```

### 5️⃣ Jenkins Job Configuration

| Setting | Value |
|---|---|
| **Item Type** | Freestyle Project |
| **Source Code Management** | Git — `https://github.com/Ashfaque-9x/registration-app` |
| **Build Step** | Invoke top-level Maven targets → Goals: `clean package` |
| **Post-build Action** | Send build artifacts over SSH |
| **Source files** | `target/*.war` |
| **Remove prefix** | `target` |
| **Remote directory** | `//opt//Docker` |

**Exec command** (runs on the Docker Host after transfer):

```bash
cd /opt/Docker

docker build -t webapp:v1 .

docker stop registerapp || true
docker rm registerapp || true

docker run -d --name registerapp -p 8086:8080 webapp:v1
```

---

##  Application Access

Once the pipeline completes successfully, the application is live at:

```
http://<DOCKER-HOST-IP>:8086/registration-app
```

---

##  Troubleshooting & Lessons Learned

Three real issues surfaced (and were resolved) while building this pipeline — documented here so nobody else has to rediscover them the hard way.

> ### 🩹 Pro-Tip #1 — Missing `javac` Compiler
> **Symptom:** Maven's build step failed because the Jenkins node had a JRE but no compiler.
> **Root Cause:** `java-openjdk11` installs the runtime only, not the development tools.
> **Fix:**
> ```bash
> sudo yum install java-11-amazon-corretto-devel -y
> ```
> Installing the `-devel` package on the Jenkins master supplies `javac` and the rest of the JDK toolchain Maven needs.

> ### 🩹 Pro-Tip #2 — SSH Authentication Failure (`JSchException: Auth fail for methods 'publickey'`)
> **Symptom:** The "Publish Over SSH" plugin couldn't authenticate to the Docker Host.
> **Root Cause:** Modern OpenSSH on the Ubuntu AMI disabled the legacy RSA key-exchange algorithm the Jenkins SSH plugin relies on.
> **Fix:** Add the following to `/etc/ssh/sshd_config` on the Docker Host, then restart `sshd`:
> ```
> PubkeyAcceptedKeyTypes +ssh-rsa
> HostKeyAlgorithms +ssh-rsa
> KbdInteractiveAuthentication yes
> PasswordAuthentication yes
> ```

> ### 🩹 Pro-Tip #3 — Remote Directory Not Resolving
> **Symptom:** The "Publish Over SSH" plugin wasn't reliably landing files at the intended absolute path.
> **Root Cause:** How the plugin concatenates the configured SSH server's root directory with the job's "Remote directory" field.
> **Fix:** Set the **Remote directory** field to `//opt//Docker` — the double-slash forces the plugin to resolve it as the correct absolute path on the Docker Host.

---

## Future Roadmap

- [ ] Replace the Freestyle job with a **declarative Jenkinsfile** (Pipeline-as-Code)
- [ ] Migrate from a single Docker container to **Kubernetes** — `regapp-deployment` (2 replicas, rolling updates) and a `LoadBalancer` `regapp-service` manifest are already scaffolded for this
- [ ] Add **Slack/Email notifications** on build success/failure
- [ ] Integrate **SonarQube** for static code analysis and quality gates
- [ ] Provision the AWS infrastructure with **Terraform** instead of manual console setup
- [ ] Add **automated tests** as a dedicated pipeline stage before packaging

---

##  Contributing

Contributions, issues, and feature requests are welcome. Feel free to open an issue or submit a PR.

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.

## 👤 Author

**Abdallah ELsayed Mohamed ELsadek**
DevOps / Cloud Engineer

[![GitHub](https://img.shields.io/badge/GitHub-181717?style=flat&logo=github&logoColor=white)](https://github.com/abdallahelsayedmohamed2004-code?tab=repositories)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=flat&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/abdallahel-syd2oo4/)

<div align="center">

⭐️ If this project helped you understand CI/CD on AWS, consider giving it a star!

</div>
