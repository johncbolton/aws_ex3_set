$VPC_ID = (aws ec2 describe-vpcs --filters "Name=tag:Name,Values=porknacho-vpc" --query "Vpcs[0].VpcId" --output text)
$EC2_SG_ID = (aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=porknacho-ec2-sg" --query "SecurityGroups[0].GroupId" --output text)
$KEY_NAME = "porknacho-key"
$AMI_ID = (aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=virtualization-type,Values=hvm" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text)
$LAUNCH_TEMPLATE_NAME = "porknacho-lt-cli"
$INSTANCE_TYPE = "t2.micro"

$USER_DATA_SCRIPT = @"
#!/bin/bash
yum update -y
yum install -y httpd stress

systemctl start httpd
systemctl enable httpd

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME=$(hostname)
echo "<html><body><h1>Hello from EC2 Instance: $HOSTNAME ($INSTANCE_ID)</h1>" > /var/www/html/index.html
echo "<p>This page is served by Apache HTTP Server.</p></body></html>" >> /var/www/html/index.html

chmod 644 /var/www/html/index.html
chown apache:apache /var/www/html/index.html
"@

$USER_DATA_ENCODED = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($USER_DATA_SCRIPT))

aws ec2 create-launch-template `
    --launch-template-name $LAUNCH_TEMPLATE_NAME `
    --version-description "Initial version via PowerShell CLI"
