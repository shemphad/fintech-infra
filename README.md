# fintech-infra
1) Install required plugins

Manage Jenkins → Plugins → Available (or “Installed” to confirm):

Pipeline

Pipeline: Multibranch

Git + GitHub Branch Source

Credentials Binding

AWS Credentials

Timestamper

(Optional) Terraform plugin (only if you want to use the tools { terraform 'terraform-1.5.0' } stanza)

Restart Jenkins after installing.

2) Provide an agent with label linux

Your pipeline starts with agent { label 'linux' }. You need at least one node with that label.

Option A — use the controller as the agent (quickest)

Manage Jenkins → Nodes → Built-In Node → Configure

Set # of executors = 1 (or more)

Labels: linux

Save

Option B — add a separate build agent (recommended)

Provision a small Amazon Linux EC2, install Java and the agent, and connect via SSH/Inbound.

On that node, make sure Terraform + AWS CLI are installed (next step).

Give it the label linux.

3) Install Terraform & AWS CLI on the agent

Your tools { terraform 'terraform-1.5.0' } requires either:

The Terraform plugin with a tool named exactly terraform-1.5.0, or

Remove the tools { … } stanza and have terraform available on PATH.

A. Using the Terraform plugin (keeps your Jenkinsfile as-is)

Manage Jenkins → Tools → Terraform installations

Name: terraform-1.5.0

(If “Install automatically” is available, use it; otherwise point to a local dir where the binary lives)

Still install AWS CLI system-wide:

# On the Jenkins agent (Amazon Linux 2/2023)
sudo yum -y install unzip || sudo dnf -y install unzip
curl -LO "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
unzip -q awscli-exe-linux-x86_64.zip
sudo ./aws/install --update
aws --version

B. Without the Terraform plugin (simpler path)

Install Terraform on the agent and remove the tools { terraform 'terraform-1.5.0' } block from the Jenkinsfile.

# On the Jenkins agent
sudo yum -y install unzip || sudo dnf -y install unzip
TF_VER="1.5.0"
curl -LO "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_amd64.zip"
sudo unzip -o "terraform_${TF_VER}_linux_amd64.zip" -d /usr/local/bin
terraform -version

# AWS CLI (same as above)
curl -LO "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
unzip -q awscli-exe-linux-x86_64.zip
sudo ./aws/install --update
aws --version

4) Add AWS credentials in Jenkins

Your pipeline uses:

withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
  credentialsId: 'aws-creds',
  accessKeyVariable: 'AWS_ACCESS_KEY_ID',
  secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']])


So create that credential:

Manage Jenkins → Credentials → (global) → Add Credentials

Kind: AWS Credentials

ID: aws-creds

Access key ID / Secret access key: (use a least-privileged IAM user or consider an instance profile/assume-role pattern)

Save

(If your Jenkins runs on an EC2 with an instance profile and you don’t want static keys, we can switch your Jenkinsfile to use withAWS(role: 'arn:aws:iam::<acct>:role/<RoleName>', region: params.REGION) { … } from the AWS Steps plugin. For now, your Jenkinsfile expects aws-creds.)

5) Ensure repo layout matches the Jenkinsfile

Your Jenkinsfile expects Terraform working dirs:

dev/ (used when branch == dev)

prod/ (used when branch == main or release)

Each directory should contain the Terraform code (main.tf, variables.tf, backend.tf, etc.). The pipeline uses:

terraform init -backend-config="key=${TF_ENV}/terraform.tfstate"


So your backend (S3/DynamoDB) must accept keys like dev/terraform.tfstate and prod/terraform.tfstate.

6) Create a Multibranch Pipeline job

New Item → Multibranch Pipeline

Name: e.g., terraform-aws-infra

Branch Sources: Git/GitHub

Repo URL: your repo

Credentials (if private): add your Git credentials or GitHub App creds

Behaviors: Discover branches

Build Configuration: by Jenkinsfile (at repo root; default Jenkinsfile)

Scan Repository Triggers: Periodic (e.g., every 1–5 min) and/or set a GitHub webhook to notify Jenkins on push

Save → Scan Multibranch Pipeline Now

It will discover dev, release, and main and create separate sub-jobs. Each sub-job inherits parameters (ACTION, REGION, DEPLOY_OVERRIDE) from your Jenkinsfile.

7) Run the pipeline

Open the sub-job for the branch you want:

release: By default, SHOULD_DEPLOY=true → you’ll get the Approval input step before the “Deploy” stage.

dev or main: Deploy is off by default; to deploy, check DEPLOY_OVERRIDE=true when building.

Steps:

“Build with Parameters”

Choose:

ACTION: apply (default) or destroy

REGION: us-east-2 (default) or your choice

DEPLOY_OVERRIDE: true only if you’re on dev/main and want a deploy

Start build → watch “Terraform Plan”

If deploy is enabled, you’ll hit the Approval gate:

Click the build → Proceed (or Abort)

Artifacts: The plan output is archived as plan-<env>.txt.

8) Common gotchas (and quick fixes)

BRANCH_NAME is empty / wrong
Use Multibranch Pipeline (not a single classic pipeline). BRANCH_NAME is set by MBP jobs.

“No such DSL method ‘terraform’ in tools”
The tools { terraform 'terraform-1.5.0' } block requires the Terraform plugin and a tool named exactly terraform-1.5.0.
Fix: Install/define the tool (Step 3A) or remove the tools block and install Terraform on PATH (Step 3B).

withCredentials AmazonWebServicesCredentialsBinding class not found
Install/enable the AWS Credentials and Credentials Binding plugins.

Terraform init backend errors
Make sure the S3 bucket, DynamoDB lock table, and IAM perms are correct. The key will be dev/terraform.tfstate or prod/terraform.tfstate.

Plan succeeds but apply fails with IAM errors
The aws-creds user/role must have permissions for the resources you’re creating (S3 backend, DynamoDB, plus all TF-managed resources). Start with a scoped policy and expand as needed.

Approval stage appears on PRs
You already guard with not { changeRequest() }, so PR builds won’t deploy.

9) (Optional) Safer credentials: assume role instead of static keys

If Jenkins runs in AWS, prefer assuming a role:

Give the Jenkins node instance profile permission to sts:AssumeRole on a target role.

Replace your deploy block with AWS Steps plugin:

stage('Deploy') {
  when { allOf { expression { env.BUILD_SUPPORTED == 'true' }
                 expression { env.SHOULD_DEPLOY == 'true' }
                 not { changeRequest() } } }
  steps {
    withAWS(role: 'arn:aws:iam::<ACCOUNT_ID>:role/<DeployRole>', region: params.REGION) {
      dir("${env.TF_DIR}") {
        sh 'terraform init -backend-config="key=${TF_ENV}/terraform.tfstate"'
        if ((params.ACTION ?: 'apply').toLowerCase() == 'destroy') {
          sh 'terraform destroy -auto-approve -lock=false -input=false'
        } else {
          sh 'terraform apply -auto-approve -lock=false -input=false'
        }
      }
    }
  }
}