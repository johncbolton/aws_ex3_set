$LAUNCH_TEMPLATE_NAME = "porknacho-lt-cli"
$LT_INFO = (aws ec2 describe-launch-templates --launch-template-names $LAUNCH_TEMPLATE_NAME --query "LaunchTemplates[0]" --output json)
$LT_ID = $LT_INFO.LaunchTemplateId
$LT_LATEST_VERSION = $LT_INFO.LatestVersionNumber

$VPC_ID = (aws ec2 describe-vpcs --filters "Name=tag:Name,Values=porknacho-vpc" --query "Vpcs[0].VpcId" --output text)
$SUBNET_1_ID = (aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=porknacho-public-subnet-1" --query "Subnets[0].SubnetId" --output text)
$SUBNET_2_ID = (aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=porknacho-public-subnet-2" --query "Subnets[0].SubnetId" --output text)
$VPC_ZONE_IDENTIFIER = "$SUBNET_1_ID,$SUBNET_2_ID"

$TARGET_GROUP_ARN = (aws elbv2 describe-target-groups --names porknacho-tg --query "TargetGroups[0].TargetGroupArn" --output text)

$ASG_NAME = "porknacho-asg-cli"
$DESIRED_CAPACITY = 2
$MAX_SIZE = 4
$MIN_SIZE = 1
$HEALTH_CHECK_TYPE = "ELB"
$HEALTH_CHECK_GRACE_PERIOD = 300
$WARMUP_PERIOD = 300

aws autoscaling create-auto-scaling-group `
    --auto-scaling-group-name $ASG_NAME `
    --launch-template "LaunchTemplateId=$LT_ID,Version=$LT_LATEST_VERSION" `
    --min-size $MIN_SIZE `
    --max-size $MAX_SIZE `
    --desired-capacity $DESIRED_CAPACITY `
    --vpc-zone-identifier $VPC_ZONE_IDENTIFIER `
    --health-check-type $HEALTH_CHECK_TYPE `
    --health-check-grace-period $HEALTH_CHECK_GRACE_PERIOD `
    --target-group-arns $TARGET_GROUP_ARN `
    --tags `
        "Key=owner,Value=Papi,PropagateAtLaunch=true" `
        "Key=Name,Value=Papi-alb-asg-instance-cli,PropagateAtLaunch=true"

aws autoscaling put-scaling-policy `
    --policy-name "cpu-utilization-scaling-cli" `
    --auto-scaling-group-name $ASG_NAME `
    --policy-type TargetTrackingScaling `
    --target-tracking-configuration "PredefinedMetricSpecification={PredefinedMetricType=ASGAverageCPUUtilization},TargetValue=50.0,DisableScaleIn=false" `
    --estimated-instance-warmup $WARMUP_PERIOD
