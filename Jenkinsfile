// Inventory API - CI/CD pipeline (Jenkins native on Ubuntu WSL2).
// Sequence: Checkout -> Setup -> Lint -> Unit tests -> Build image -> Smoke test
//           -> [Bonus] Image report -> Deploy (with automatic rollback).
// Any failing stage stops every later stage, so a broken commit is never deployed.
// No credentials are stored here: a public repo needs none; for a private repo use a
// Jenkins credential (Manage Jenkins > Credentials) selected in the job's SCM config.
pipeline {
  agent any
  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 20, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }
  environment {
    IMAGE     = 'inventory-api'
    TAG       = "${env.BUILD_NUMBER}"
    CANDIDATE = 'inventory-candidate'
    SMOKE     = 'http://127.0.0.1:5051'
  }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD'
      }
    }

    stage('Setup') {
      steps {
        sh '''
          set -eu
          python3 -m venv .venv
          .venv/bin/pip install -q --upgrade pip
          .venv/bin/pip install -q -r requirements-dev.txt
        '''
      }
    }

    stage('Lint') {                       // Challenge 4: static check as its own stage
      steps { sh '.venv/bin/ruff check app tests' }
    }

    stage('Unit tests') {
      steps {
        sh '''
          set -eu
          mkdir -p reports
          .venv/bin/python -m pytest -v --junitxml=reports/pytest.xml
        '''
      }
      post {
        always { junit allowEmptyResults: true, testResults: 'reports/pytest.xml' }
      }
    }

    stage('Build image') {
      steps { sh 'docker build -t "$IMAGE:$TAG" .' }
    }

    stage('Container smoke test') {
      steps {
        sh '''
          set -eu
          docker rm -f "$CANDIDATE" >/dev/null 2>&1 || true
          docker run -d --name "$CANDIDATE" -p 127.0.0.1:5051:5000 "$IMAGE:$TAG"

          ready=0
          for i in $(seq 1 20); do
            if curl -fsS "$SMOKE/health" | grep -q '"status":"ok"'; then ready=1; break; fi
            sleep 1
          done
          test "$ready" -eq 1 || { docker logs "$CANDIDATE"; exit 1; }

          code() { curl -s -o /dev/null -w '%{http_code}' "$1"; }

          echo "--- functional checks"
          curl -fsS "$SMOKE/api/items" | grep -q 'router'
          test "$(code "$SMOKE/api/items/1")"                           = 200
          test "$(code "$SMOKE/api/items/999")"                         = 404
          test "$(code "$SMOKE/api/items/low-stock?threshold=5")"       = 200
          test "$(code "$SMOKE/api/items/low-stock?threshold=abc")"     = 400
          test "$(code "$SMOKE/api/items/low-stock?threshold=101")"     = 400
          curl -fsS "$SMOKE/api/items/low-stock?threshold=5" | grep -q 'switch'

          echo "--- security checks (Challenge 4)"
          uid="$(docker exec "$CANDIDATE" id -u)"
          echo "container uid=$uid"
          test "$uid" != 0
          for pkg in pytest ruff; do
            if docker exec "$CANDIDATE" python -c "import $pkg" 2>/dev/null; then
              echo "FAIL: dev dependency '$pkg' present in production image"; exit 1
            fi
            echo "OK: '$pkg' not installed in image"
          done
          if docker exec "$CANDIDATE" sh -c 'ls -A /service' | grep -Eq '^(tests|\\.venv|\\.git|\\.env|Jenkinsfile)$'; then
            echo "FAIL: build context leaked into image"; exit 1
          fi
          docker exec "$CANDIDATE" ls -A /service
        '''
      }
      post {
        always { sh 'docker rm -f "$CANDIDATE" >/dev/null 2>&1 || true' }
      }
    }

    stage('Image report (bonus)') {       // Stretch 2: dependency lock + optional scan
      steps {
        sh '''
          set -eu
          mkdir -p reports
          docker run --rm --entrypoint pip "$IMAGE:$TAG" freeze > reports/runtime-lock.txt
          cat reports/runtime-lock.txt
          if command -v trivy >/dev/null 2>&1; then
            trivy image --no-progress --severity HIGH,CRITICAL --format table \
              -o reports/trivy.txt "$IMAGE:$TAG"
          else
            echo "trivy not installed - scan skipped" > reports/trivy.txt
          fi
        '''
        archiveArtifacts artifacts: 'reports/runtime-lock.txt, reports/trivy.txt', allowEmptyArchive: true
      }
    }

    stage('Deploy locally') {
      // Plain Pipeline job: BRANCH_NAME is unset -> deploy.
      // Multibranch job (Stretch 1): only main deploys; feature branches/PRs stop after the smoke test.
      when { expression { env.BRANCH_NAME == null || env.BRANCH_NAME == 'main' } }
      steps {
        sh 'bash scripts/deploy.sh "$IMAGE:$TAG"'   // Challenge 3: automatic rollback on failure
        sh 'curl -fsS http://127.0.0.1:5050/ && echo'
      }
    }
  }
  post {
    always {
      sh 'docker rm -f inventory-candidate >/dev/null 2>&1 || true'
      archiveArtifacts artifacts: 'reports/*.xml', allowEmptyArchive: true
    }
    success { echo "Deployed ${env.IMAGE}:${env.TAG} at http://127.0.0.1:5050" }
    failure { echo 'Pipeline failed - later stages were skipped, live service left unchanged (or rolled back).' }
  }
}
